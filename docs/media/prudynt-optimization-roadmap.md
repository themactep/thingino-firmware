# prudynt Optimization Roadmap

Scope: memory footprint (flash and RAM) and latency of the `prudynt` streamer.
All baseline numbers below were measured on a T31 build
(`cinnado_d1_t31l_sc2336_atbm6031`, uClibc, dynamically linked).

## Baseline (measured)

| Artifact | Size | Notes |
|---|---|---|
| `prudynt` binary (stripped, dynamic) | 1,006,320 B (~983 KB) | `.text` = 674 KB |
| Exception unwind tables in binary | ~94 KB | `.eh_frame` 51 KB + `.eh_frame_hdr` 11 KB + `.gcc_except_table` 32 KB |
| `libstdc++.so.6.0.35` in rootfs | 2,180,716 B (~2.08 MiB) | sole consumers: `prudynt` + `prudyntctl` |
| `libgcc_s.so.1` in rootfs | 200,320 B | required by the C toolchain too, not droppable |
| `prudynt` source (`src/`) | ~34 KLOC | 44 `.cpp`, 54 `.h`/`.hpp` |

Two facts drive this roadmap:

1. **Unwind tables are ~9.4% of the binary and are dead weight.** The entire
   `src/` tree has 2 `throw` sites (`IMPSystem.hpp:22`, `IMPAudio.hpp:43`) and
   ~8 `try`/`catch` blocks, none of which fire in normal operation. The 94 KB
   exists only because exceptions are enabled.
2. **`libstdc++` is linked by exactly two binaries**, both in this package.
   `jct` and `curl` are pure C. A C port of `prudynt` + `prudyntctl` would let
   the whole library leave the image.

## Ground rules

- **Latency is set by silicon, not language.** The hot path is
  sensor -> ISP -> hardware H.264/H.265 encoder -> poll loop -> `memcpy` ->
  RTSP/RTP socket send. Every cycle that matters happens in hardware or in
  syscalls. C vs C++ changes nothing here; measure glass-to-glass latency, not
  "C++ overhead", when validating.
- **Flash and RAM are different numbers.** `libstdc++` costs 2.08 MiB of
  *flash* (stored whole) but only the pages actually touched are *resident* in
  RAM. Removing it saves flash first, RAM second.
- **Allocation jitter is a code problem, not a language problem.** You can
  write allocation-free C++ and you can write malloc-happy C. The fixes in
  Phase 2 do not require leaving C++.
- **Each phase has a measurable success criterion.** "It compiled" is not
  success. The baseline numbers above are the bar.

---

## Phase 0 -- Instrument and reproduce the baseline

Do this first. Every later phase is judged against these numbers, and the
measurement must be reproducible by anyone.

```sh
BIN=<output>/target/usr/bin/prudynt
READELF=<output>/host/bin/mipsel-linux-readelf

ls -la "$BIN"
$READELF -S "$BIN" | grep -E '\.text|\.eh_frame|\.gcc_except_table'
$READELF -d "$BIN" | grep NEEDED
ls -la <output>/target/usr/lib/libstdc++*
```

On-camera, capture runtime RAM and frame cadence under a fixed load:

```sh
# RSS of the running streamer
grep -E 'VmRSS|VmSize' /proc/$(pidof prudynt)/status
# per-frame cadence (see docs/dev/rtsp-stress-test.md)
timeout 25 ffprobe -v error -show_entries frame=pkt_pts_time \
  -select_streams v:0 -of compact=nk=1 \
  rtsp://thingino:thingino@<ip>/ch0 > /tmp/frames.txt
```

Success criteria: a single documented command set that reproduces the baseline
table above to within a few percent.

---

## Phase 1 -- Kill exception and RTTI overhead

**Cost: a few hours. Expected win: ~94 KB off the binary, no behavior change.**

Steps:

1. Add `-fno-exceptions -fno-rtti -fno-threadsafe-statics` to `CXXFLAGS` in
   `overrides/prudynt-t/Makefile` (line 21 today).
2. Remove the 2 `throw` sites. They are init guards:
   - `IMPSystem.hpp:22` -- `throw std::invalid_argument(...)` becomes an error
     return / `fprintf(stderr)` + `exit`.
   - `IMPAudio.hpp:43` -- `throw std::runtime_error(...)`, same treatment.
3. Convert the ~8 `try`/`catch` blocks to explicit error handling. Most already
   have a single `catch (...)` that swallows the error; replace with the
   underlying call's return-code check. `Config.cpp:1025` and
   `VideoWorker.cpp:1036` are the only ones to read carefully -- they wrap
   code that can actually fail.
4. Rebuild, confirm the binary still runs, and re-run Phase 0.

Success criteria: `.eh_frame` + `.gcc_except_table` sections shrink to ~0 in
the binary, and `-fno-exceptions` compiles clean (no `throw`/`try` remain).

Result (measured, `cinnado_d1_t31l_sc2336_atbm6031`, uClibc dynamic build):

| Section | Before | After |
|---|---|---|
| `.eh_frame` | 51,176 B | 4 B |
| `.eh_frame_hdr` | 11,180 B | gone |
| `.gcc_except_table` | 31,987 B | gone |
| `.text` | 689,728 B | 591,120 B |
| total binary | 1,006,320 B | 779,228 B |

Net: **-227 KB (-22.6%)**. The unwind tables (-94 KB) match the prediction;
the extra ~98 KB of `.text` is the removal of exception landing pads and
cleanup code that every function with automatic destructors carried. Binary
is still a valid dynamically-linked ELF; dependencies unchanged.

---

## Phase 2 -- Zero allocation in the per-frame path

**Cost: a few days. Expected win: no malloc/copy churn in the hot loop;
removes the only plausible source of C++-induced jitter.**

`VideoWorker.cpp` already does the heavy lifting with `NaluPool` (32 pooled
buffers, `borrow()`/`returnBuf()`). What remained in the per-frame path:

| Site | Status |
|---|---|
| `wrap_buf` | **fixed** -- persistent buffer in `run()` scope |
| `taps_copy` / `sei_taps_copy` | **fixed** -- one persistent vector, reused |
| `vps_copy` / `sps_copy` / `pps_copy` | **fixed** -- appended under lock, no temporaries |
| `nalu.data = nalu_buf` (channel copy) | **open** -- per-NAL alloc; needs a pool-backed channel |
| `sei_nal` via `SEIWriter::buildSEI` | **open** -- per-IDR alloc |
| `mp4_sample` | amortized (reserved + cleared, capacity retained) |

None of these is a language problem; all are fixable in C++:

1. Give each a persistent buffer with a capacity bound instead of a fresh
   `std::vector` (reuse the `NaluPool` pattern for the per-NAL temporaries).
2. `reserve()` once to a provable worst case (NAL size is bounded by the
   encoder's output buffer) instead of relying on growth.
3. The `NaluPool::borrow()` `insert(nalu_buf.end(), start+4, end)` at
   `VideoWorker.cpp:1004` is correct but re-checks capacity on every IDR NAL;
   size the pool against the max NAL, not the hint.

Instrument to prove it: run under a `malloc` interposer (LD_PRELOAD wrapper
counting allocations) for a fixed 10-minute stream and assert zero allocations
after warm-up.

Success criteria: malloc counter flat after the first GOP, at both 1080p/25fps
and 640x360/25fps, with recording on and off.

### Remaining per-NAL allocation (not yet fixed)

The channel copy `nalu.data = nalu_buf` still allocates one buffer per NAL:
`MsgChannel::write` stores an owned `std::vector<uint8_t>` in a
`std::deque`, so the encoder thread must hand over a fresh buffer. Moving the
pooled buffer into the channel would empty `NaluPool` (borrowed buffers never
return), so this is only fixable by making the channel pool-backed --
consumers return the buffer to the pool after copying out. That touches
`MsgChannel` and every reader (RTSP drain, taps, websocket), so it is split
out as its own piece of work rather than a hot-path edit.

Expected result: eliminates the remaining allocation stalls in the frame
path. Latency impact only measurable if the churn was actually causing
stalls -- Phase 0's frame-cadence data is the before picture.

---

## Phase 3 -- Flash diet: remove libstdc++ from the image

**Cost: weeks. Expected win: up to 2.08 MiB flash; RAM win is secondary.**

`libstdc++.so.6` (2.08 MiB) ships because `prudynt` and `prudyntctl` link it
dynamically. Options, in order of preference:

1. **Port `prudyntctl` to C.** It is small (`prudyntctl.cpp`, ~272 lines). A C
   reimplementation using the existing `libjct` (pure C) removes one of the two
   consumers cheaply. This does not drop libstdc++ yet, but halves the
   consumer count.
2. **Shrink the STL surface in `prudynt`.** The heavy users are `std::string`
   (534 uses), `std::vector` (310), `std::mutex` (90), `std::atomic` (56),
   `std::shared_ptr` (40), `std::thread` (27). Replace string/vector in the
   hot path (Phase 2) and in config/JSON paths with fixed buffers + `libjct`.
   The threading primitives can map onto `pthread` directly.
3. **Then decide between the two end-states:**
   - **Static-link the remainder** (`-static-libstdc++`): the `.so` leaves the
     image, but both binaries now carry their own copy of the used stdlib
     code. If `prudyntctl` is C and `prudynt`'s remaining stdlib use is small,
     this is a net flash win. If not, it can be a wash or a loss -- measure
     binary growth before committing.
   - **Full C port** (Phase 4): drops libstdc++ entirely.

Success criteria: `readelf -d` on every binary in the rootfs shows no
`libstdc++` NEEDED entry, and the rootfs no longer ships `libstdc++.so.6`.

---

## Phase 4 -- Decision gate: full C rewrite

**Cost: ~1 person-month for 34 KLOC. Expected win: the Phase 3 flash savings
plus ~94 KB (already captured in Phase 1). Latency win: zero.**

This is the honest answer to "rewrite prudynt in C":

| Metric | Expected change | Why |
|---|---|---|
| Flash | -2.08 MiB (libstdc++) | only if libstdc++ is dropped from the image |
| Binary size | ~-94 KB | already achieved by Phase 1's flags, not the rewrite |
| RAM (RSS) | tens of KB | C++ runtime static data/vtables/TLS is tiny vs frame buffers |
| Latency | **zero** | encoder and network set the latency, not the language |

The rewrite's real cost is not time, it is **risk**. RAII currently guarantees
cleanup on every error path. A manual C port of 34 KLOC -- with hand-rolled
`goto` cleanup and manual `free` -- is a net *increase* in use-after-free /
double-free surface on a no-MMU MIPS core where UB corrupts NAND.

**Recommendation:** do Phase 1-3 first. If, after Phase 3, flash is still the
hard constraint, port only the leaf modules that must be C (JSON/config,
NALU handling, the pool) and keep C++ where RAII earns its keep (thread
lifecycle, the RTSP server). A targeted C core beats a full rewrite on both
risk and effort, and buys the same flash number.

---

## Success criteria summary

| Phase | Measurable outcome |
|---|---|
| 0 | reproducible baseline commands |
| 1 | `.eh_frame` + `.gcc_except_table` ~0; binary -94 KB |
| 2 | malloc counter flat after first GOP in the frame path |
| 3 | no `libstdc++` NEEDED in any rootfs binary; `libstdc++.so.6` absent |
| 4 | (only if reached) same as 3, with an audited error-path cleanup story |

## Non-goals

- Re-architecting the encoder pipeline. The hardware encoder and its DMA
  buffers are not a source of the costs measured here.
- Chasing latency. Per the ground rules, latency is set by silicon and the
  network; any "latency" work belongs in a separate encoder/IPC investigation,
  not this roadmap.
