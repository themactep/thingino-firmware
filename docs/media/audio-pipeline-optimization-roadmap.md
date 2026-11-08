# Audio pipeline optimization roadmap

Status: Proposed

Scope: reduce CPU spent on microphone audio processing in Thingino without
changing the `libaudioProcess` ABI or degrading audio quality. This covers the
IMP audio input path shared by prudynt, raptor, timps, and strero. Video
encoding, ISP, and networking are out of scope.

Status: Phase 0 tooling and Phase 2 are implemented. Phase 1, 3, and 4 still
need target measurements. See [Implementation log](#implementation-log).

## What the pipeline does today

With NS enabled and AAC output:

1. `IMP_AI_EnableNs` installs noise suppression in libimp's AI channel.
   libimp `dlopen`s `libaudioProcess.so` and calls `audio_process_ns_*`.
2. `audio_process_ns_process()` calls `WebRtcNs_Analyze()` and then
   `WebRtcNs_Process()` on the same 10 ms frame.
3. Analyze does one forward FFT of the 256-point low band.
4. Process does a second forward FFT of the same frame, then the IFFT.
5. FAAC AAC-LC does one forward FFT per 1024-sample frame inside the MDCT.

So per 10 ms frame the chain is FFT, FFT, IFFT, plus one extra FFT per AAC
frame. The second forward FFT is pure duplication: same input, same window,
same transform.

Evidence from the pinned `libaudioprocess-neo` source:

- `src/ns.c:31` calls `WebRtcNs_Analyze`.
- `src/ns.c:32` calls `WebRtcNs_Process`.
- `src/webrtc/modules/audio_processing/ns/ns_core.c:1087` is the FFT in
  Analyze.
- `src/webrtc/modules/audio_processing/ns/ns_core.c:1266` is the second FFT in
  Process.
- `src/webrtc/modules/audio_processing/ns/ns_core.c:1312` is the IFFT.
- `faac-2.2/libfaac/filtbank.c:222` is the FFT inside the AAC MDCT.

The stock Ingenic `libaudioProcess.so` has the same Analyze + Process pattern
and cannot be patched. The firmware already selects the MIT replacement by
default (`package/prudynt-t/Config.in:17`,
`package/thingino-raptor-hal/Config.in:19`, `package/timps/Config.in:17`).

## Static transform budget

At 16 kHz, one second of audio:

| Stage | Transforms/s | N log N units |
|---|---:|---:|
| NS Analyze | 100 x FFT(256) | 204,800 |
| NS Process | 100 x FFT(256) + 100 x IFFT(256) | 409,600 |
| AAC-LC | 15.6 x FFT(512) | 72,000 |
| Total | | 686,400 |

After merging Analyze and Process:

| Stage | Transforms/s | N log N units |
|---|---:|---:|
| NS combined | 100 x FFT(256) + 100 x IFFT(256) | 409,600 |
| AAC-LC | 15.6 x FFT(512) | 72,000 |
| Total | | 481,600 |

That is about 30% less transform work at 16 kHz and about 25% at 48 kHz. Real
CPU saving is smaller because windowing, feature extraction, noise estimation,
and filtering remain. Phase 0 measures the real share.

## Non-goals

- Do not share the NS FFT with the AAC MDCT. Different transform sizes,
  windows, and alignment. AAC runs on the NS output.
- Do not remove the IFFT. It reconstructs the time-domain signal.
- Do not change the `audio_process_*` ABI. libimp calls those symbols.
- Do not replace FAAC with `IMP_AENC` as part of this work. Prudynt and raptor
  bypass `IMP_AENC` for a known ring-buffer heap-corruption bug, and its AAC
  path still uses an FFT.
- Do not change default audio quality. Any quality change is a separate
  decision.

## Phase 0: baseline and harness

Goal: make the optimization measurable and repeatable.

Tasks:

1. Extend `package/thingino-imp-test/imp-test-audio.c` with:
   - `-N <0-3>` to call `IMP_AI_EnableNs`.
   - `-H` to call `IMP_AI_EnableHpf`.
   - `-A` to call `IMP_AI_EnableAgc` where the SoC supports it.
   - `getrusage(RUSAGE_SELF)` user+sys before and after the capture loop.
   - Keep `-o` for raw PCM output.
2. Add a host-side deterministic NS harness in `libaudioprocess-neo`:
   - feed a fixed raw PCM corpus: speech, pink noise, silence.
   - call `audio_process_ns_*` with 160-sample frames.
   - time with `clock_gettime(CLOCK_PROCESS_CPUTIME_ID)`.
   - write output for old/new comparison.
   - build natively and with the target cross compiler.
3. Measure the streamer:
   - sample `/proc/<pid>/stat` utime+stime for prudynt or raptor over a fixed
     60 s window.
   - compare audio active vs muted, NS on vs off, AAC vs G.711.
   - keep the video configuration fixed.
4. Record a baseline table:
   - SoC, streamer, sample rate, codec, NS level.
   - user+sys CPU time per 60 s.
   - raw PCM captures for quality checks.
5. Confirm NS is actually enabled on the target. The checked T31 build shipped
   `mic_noise_suppression: 0` in `prudynt.json`, and raptor defaults
   `ns_enabled=false`.

Success criteria: one command set reproduces the CPU and quality baseline
within a few percent, and the harness can switch NS on/off without rebuilding.

## Phase 1: cheap wins

Goal: remove easy overhead before touching the NS core.

Tasks:

1. A/B the neo build flags. The current Makefile uses `-Os -flto`
   (`libaudioprocess-neo/Makefile:6-8`). Test `-O2` and `-O3` for `ns_core.c`,
   `fft4g.c`, and `ns.c`; keep `-Os` for the rest if flash size matters.
2. A/B FAAC flags. It already uses `-ffast-math`; test `-O2` and `-O3`.
   Measure CPU and binary size.
3. Confirm the sample rate. Use 16 kHz unless `mic_hq` is required. At 48 kHz
   the AAC FFT is larger and the path does more work.
4. Document whether `mic_noise_suppression` and `mic_hq` are enabled on the
   target.

Success criteria: a measured win with no quality change, or a documented
no-op and revert.

## Phase 2: merge NS analyze and process

Goal: remove the duplicate forward FFT. This is the main optimization.

Design:

- Keep `audio_process_ns_process()` as the only public entry point.
- Add an internal `WebRtcNs_AnalyzeProcessCore()` in `ns_core.c` that:
  1. updates the analysis and process buffers once,
  2. windows and FFTs the 10 ms low band once,
  3. runs the existing feature extraction and noise estimate on that spectrum,
  4. runs the existing filter computation on the same spectrum,
  5. IFFTs and produces the output.
- Keep the old `WebRtcNs_Analyze()` and `WebRtcNs_Process()` functions for API
  compatibility. Only `audio_process_ns_process()` uses the combined path.
- Keep the high-band path unchanged. Analyze does not FFT high bands today, and
  Process applies a time-domain gain.

Implementation options:

1. Preferred: upstream the combined function to
   `gtxaspec/libaudioProcess-neo`, bump
   `LIBAUDIOPROCESS_NEO_VERSION` in
   `package/libaudioprocess-neo/libaudioprocess-neo.mk:10`, and rebuild.
2. If upstream is not ready: add
   `package/libaudioprocess-neo/0001-ns-merge-analyze-process.patch` and keep
   the pinned version. Remove the patch when the bump lands.

Refactor notes:

- `WebRtcNs_AnalyzeCore` uses `self->analyzeBuf`; `WebRtcNs_ProcessCore` uses
  `self->dataBuf`. Both receive the same frame here. Preserve both buffer
  updates, but compute the window and FFT once.
- Reuse `winData`, `energy`, `real`, `imag`, and `magn` for both halves.
  Analysis must run before the filter so the noise estimate includes the
  current frame, exactly as today.
- Keep the zero-input special case, the `blockInd` update, and the high-band
  handling.
- Do not export new symbols. `libaudioProcess.map` must keep the same
  `audio_process_*` surface.

Validation:

1. Deterministic null test. Feed the same PCM corpus through the old and new
   `audio_process_ns_process()`. Compare output with `cmp`. The merge should be
   bit-identical because the operations are unchanged. A near-identical result
   needs an explanation before it is accepted.
2. Device A/B. Build two images, one with the old library and one with the
   merged library. Capture raw PCM with `imp-test-audio -N 1` from a fixed
   playback (speech plus noise). Compare captures and run a listening test.
3. CPU. Re-run the Phase 0 streamer sampling at 16 kHz and, if supported, at
   48 kHz.
4. Regression. Test prudynt, raptor, and timps on at least one T31 and one T23
   camera. Check NS levels 0 through 3, HPF, AGC, and NS disabled.

Success criteria:

- Transform count drops from 2 forward plus 1 inverse to 1 forward plus
  1 inverse per NS frame.
- Measured NS CPU drop on the target, with a passing null test and no audible
  difference.
- No ABI break. `nm -D libaudioProcess.so` still shows the same
  `audio_process_*` exports.
- Patch is upstreamed or carried cleanly.

## Phase 3: fixed-point NSX (optional)

Goal: evaluate a faster NS core if Phase 2 is not enough.

The WebRTC fixed-point NS already does analysis and synthesis in one pass:
`WebRtcNsx_ProcessCore()` at `nsx_core.c:1500`, forward FFT at `:1245`, IFFT
at `:1456`. The tree also vendors `nsx_core_mips.c`, which the current Makefile
does not compile (`NS_SRC` lists only `ns_core.c` and
`noise_suppression.c`, `libaudioprocess-neo/Makefile:35-37`).

Tasks:

1. Add `nsx_core.c`, `noise_suppression_x.c`, and the matching SPL sources to
   the build.
2. Add a compile-time switch in `audio_process_ns_process()` to use NSX.
3. Convert the float bands to int16 and back. Confirm the libimp input range.
4. Benchmark on MIPS with and without `nsx_core_mips.c`.
5. A/B quality against the float NS with the same corpus.

Success criteria: meaningful CPU reduction with acceptable quality. Otherwise
keep the float merged path and drop the experiment.

Risks: NSX is a different algorithm, quality may change, and the float to int16
conversion can eat the gain. Do not ship without listening tests.

## Phase 4: AAC encoder (optional)

Goal: confirm the AAC side is already minimal.

Tasks:

1. Confirm FAAC is the encoder in all default streamers. It is a dependency of
   prudynt, raptor, and timps.
2. Confirm the MDCT uses one FFT (`filtbank.c:222`). There is no second
   transform to remove.
3. A/B compile flags and LTO; measure CPU and size.
4. Re-evaluate `IMP_AENC` only if the ring-buffer corruption is fixed. Do not
   make it a dependency of this roadmap.
5. If audio CPU still matters more than bitrate, document G.711 as the no-FFT
   fallback.

Success criteria: documented best flags and no change to the encoder path unless
it is a clear win.

## Phase 5: upstream, document, release

Tasks:

1. Upstream the NS merge to `gtxaspec/libaudioProcess-neo`.
2. Bump the pinned version in
   `package/libaudioprocess-neo/libaudioprocess-neo.mk` and drop the local
   patch if upstreamed.
3. Update this roadmap with measured before and after numbers.
4. Link this roadmap from `docs/media/libimp-userspace.md`.
5. Add a short note to `docs/media/streamer.md` if audio defaults change.

Success criteria: the optimization is in the default build, documented, and
reproducible from a clean checkout.

## Effort and ordering

| Phase | Scope | Effort | Expected win | Risk |
|---|---|---|---:|---|
| 0 | Harness and baseline | 1 to 2 days | Measurement only | Low |
| 1 | Flags, rate, defaults | 0.5 to 1 day | Small, possibly zero | Low |
| 2 | Merge NS FFTs | 3 to 5 days | About 25 to 30% less transform work | Medium |
| 3 | Fixed-point NSX | 5 to 10 days | Unknown, potentially larger | High |
| 4 | AAC flags and encoder | 2 to 3 days | Small | Low |
| 5 | Upstream and docs | 1 to 2 days | Sustainability | Low |

Do Phase 0 and Phase 2 first. Phase 3 is a fallback only if Phase 2 is
insufficient. Phase 1 and Phase 4 are cheap but should not block Phase 2.

## Implementation log

What is in the tree:

- `package/thingino-imp-test/imp-test-audio.c` gained `-N <0-3>` (enable NS),
  `-H` (HPF), `-A` (AGC, target 10 dBFS, compression 20 dB), and user+sys CPU
  accounting with `getrusage(RUSAGE_SELF)` around the capture loop.
- `package/libaudioprocess-neo/0001-ns-merge-analyze-process.patch` adds
  `WebRtcNs_AnalyzeProcessCore()`. `audio_process_ns_process()` calls it; the
  old `WebRtcNs_Analyze()` and `WebRtcNs_Process()` stay in the source.
- `package/libaudioprocess-neo/0002-ns-bench-harness.patch` adds
  `tests/ns_bench.c` and `make bench`. The module is not part of the default
  build. Build it natively with `make bench CROSS_COMPILE=` inside the package
  source tree, or with the target cross compiler.

Null test (host x86-64, same corpus into old and new paths):

```sh
make bench CROSS_COMPILE=
./ns_bench -r 16000 -p 1 -n 20000 -b 1 -o old.raw
# rebuild with 0001 and repeat as new.raw
cmp old.raw new.raw
```

Output was bit-identical at 8, 16, 32, and 48 kHz, policies 0 through 3, with
1 and 2 bands. The zero-input path and the warm-up state machine are included
in the corpus.

Host CPU time, 20000 frames, mean of 5 runs (`tests/ns_bench.c`, x86-64, not
the target):

| Rate | Old | Merged | Change |
|---|---:|---:|---:|
| 16 kHz, 1 band | 0.1144 s | 0.1077 s | -5.9% |
| 48 kHz, 1 band | 0.1193 s | 0.1082 s | -9.4% |

The host FFT is a small part of the run, so the target saving should be larger.
Do not quote these as target numbers.

Cross build (`wyze_cam3_t31x_gc2053_atbm6031`, uClibc, Buildroot):

- Both patches apply with `patch -p1`.
- `libaudioProcess.so` builds and strips.
- `nm -D --defined-only` shows the same 31 `audio_process_*` symbols.
- `WebRtcNs_AnalyzeProcessCore` is not exported; the version script hides it.
- `.text` does not grow: the merged path no longer references
  `WebRtcNs_AnalyzeCore` and `WebRtcNs_ProcessCore`, so `--gc-sections` drops
  them and their wrappers from the shared object. They remain in the source
  and in `libaudioProcess.a`.

Still open, because it needs hardware:

- Phase 0 steps 3 to 5: streamer CPU sampling, and confirming that NS is on.
- Phase 2 device A/B with `imp-test-audio -N 1` and a listening test.
- Phase 1 and Phase 4 flag A/B.
- Upstreaming the merge to `gtxaspec/libaudioProcess-neo` and dropping 0001.

Phases 1 and 4 need no code change yet. The neo flags are still `-Os -flto`,
and FAAC still owns the AAC path with a single MDCT FFT.

## Open questions

- Is NS enabled in the deployment being optimized, or is this theoretical?
- Which SoCs and sample rates matter: T31 and T23 at 16 kHz, or 48 kHz
  `mic_hq`?
- How much of the streamer CPU is audio versus video? Phase 0 answers this.
- Is upstreaming to `gtxaspec/libaudioProcess-neo` acceptable, or should the
  patch live in the firmware package?
- Is a fixed-point NS acceptable if it sounds different?

## References

- `package/libaudioprocess-neo/` for the MIT replacement.
- `package/prudynt-t/Config.in:17`, `package/thingino-raptor-hal/Config.in:19`,
  and `package/timps/Config.in:17` for library selection.
- `package/thingino-imp-test/imp-test-audio.c` for raw PCM capture.
- Build output used for the evidence above:
  `build/libaudioprocess-neo-475278e2.../` and `build/faac-2.2/`.
