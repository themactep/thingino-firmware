# Session Handoff - Cinnado D1 T31L (sc2336) bring-up

Date: 2026-10-09
Camera: `cinnado_d1_t31l_sc2336_atbm6031`, IP `192.168.88.141`, T31 (4.4.94, uclibc)
Build tree: `/home/paul/thingino/firmware/ciao` (branch `ciao`). Overrides live in
`/home/paul/thingino/overrides/` (`BR2_OVERRIDES_DIR`).
Goal of the session: clear boot warnings/oopses and get prudynt to stream.

## mainline-7x (Linux 7.1-rc1) - status (2026-10-11)

The camera also runs a mainline **Linux 7.1-rc1** build on branch `mainline-7x`
(camera defconfig `KERNEL_VERSION_7`, uclibc, `BR2_THINGINO_DEV_EXPERIMENTAL`).
This section is self-contained; the 4.4 material below is a different branch.

**Works**
- Builds an 8 MB image and boots to the Thingino userspace (login prompt on the
  serial console); squashfs rootfs on `mtdblock4` mounts.
- JFFS2 data partition / overlayfs: fixed and clean (`/proc/mtd` `erasesize 0x10000`,
  no "wrong erase size", write-through and reboot-persistent).
- MSC1/SDIO bus: pins PB8-14 func 1 (vendor-confirmed), clock running, WLAN power
  on GPIO 47 - the SDIO card still does not answer CMD5 (see W0 below).
- `isp` node present and enabled; camera `.dtsi` fragment now applies (LEDs/keys/
  i2c1/mac-disable/msc1).
- Network via **USB-Ethernet** on the OTG port (`asix`/`r8153_ecm` built in) ->
  SSH + `make ota` + a fast kernel-flash loop (see "Fast kernel iteration over SSH").

**Open**
- **ATBM6031 WiFi**: the vendor driver does not build on 7.x, and the mainline
  `jz4740_mmc` cannot bring up the SDIO card (W0). Needs the vendor SDIO driver
  (see the SDK reference below) - a port, not a tweak.
- **ISP / video**: the `.dtsi` applies and the `isp` node is enabled, but the open
  ISP stack has not been brought up on 7.x.
- The `ttyS1` boot-console handover stop (worked around with `keep_bootcon` in the
  kernel fragment) is still not root-caused.

**Kernel patches** (`package/all-patches/linux/7.1-rc1/`):
`0001` FIT image, `0002` thingino-t31 SFC partition map, `0003` mtdblock
`BLK_MQ_F_NO_SCHED_BY_DEFAULT` (boot-hang fix), `0004` bound the SFC `SR_END` poll,
`0005` T31 `mmc1` pin groups, `0006` `isp` node + `msc1_pb` group, `0007`
`ingenic-pinctrl.h` compat shim, `0008` `jz4740_mmc` `ingenic,sdio_clk` handling,
`0009` (temporary) SDIO clock debug trace.

**Key commits on `mainline-7x`**: `5e95e3440` (boot hang), `cfa6c30b6` (SDIO DT
plumbing), `3e530c8c2` (JFFS2 erase size), `915214b57` (keep_bootcon), W0 SDIO
driver work through `c5d15d17c`.

See "SDIO / WiFi (atbm6031) - in progress" and "W0 - newer Ingenic SDK" below for
the full W0 analysis, and `docs/dev/cinnado-d1-wifi-roadmap.md` for the WiFi
conversion plan.

## TL;DR

- Several boot-time driver bugs fixed and deployed (motor IRQ, wifi RX, IR-CUT/i2c1).
- **Breakthrough**: the encoder now initializes and prudynt streams, after fixing the
  SDK avpu driver to use `clk_prepare_enable()` (was bare `clk_enable()`, which WARNs and
  fails on 4.4 -> AVPU unclocked -> whole video pipeline wedged).
- ~~**Still open**: hard-wedge of the video pipeline.~~ **ROOT-CAUSED (2026-10-09):**
  the wedge is the **OSD burn-in path** - `IMP_OSD_Start()` at the first RTSP PLAY,
  which the open ISP stack + vendor libimp does not implement correctly, stalls an ISP
  register access -> IRQs off -> watchdog reset. Fixed for this device by shipping
  `"osd":{"burnin":{"enabled":false}}` (device-scoped `prudynt.json`); a 90 s ch1 pull
  then runs clean. See "RESOLVED: OSD burn-in..." below. Prudynt is re-enabled.
- **Probe run**: instrumented prudynt + tx-isp and reproduced the wedge on demand. It
  is triggered by an RTSP client reading (PLAY), needs only a **single** client, and is
  stable while idle - all consistent with the OSD-start-at-PLAY cause. Probe details and
  the earlier (pre-OSD) MSCA-handoff observations are in
  "Video-pipeline wedge - probe findings".
- **ch0 fixed (2026-10-09)**: the main stream showed only ~6-10 image rows then green.
  The open-tx-isp reimpl fed the MSCA a bogus frame crop (`fcrop=1/38,38 1882x6`) so the
  ch0 output size register held height **6**. Root cause + fix in
  "RESOLVED: ch0 MSCA output...". Both ch0 (1920x1080) and ch1 (768x432) now decode full
  frames with correct chroma, and a 60 s dual-stream pull runs clean.
- **fMP4 preview fixed (2026-10-10)**: browser showed MJPEG but no fMP4. Two causes:
  (1) the on-board AAC encoder does not open ("faac_encoder_get_info failed"), yet
  prudynt still declared an mp4a track with 0 samples, so MSE buffered nothing - fixed by
  disabling audio for this device; (2) `MP4Muxer_simple` wrote each fragment's `tfdt` as
  the raw (jittery) encoder PTS with the previous-delta duration, so fragments overlapped
  and MSE dropped them, driving the preview's "drifted behind live edge" resync loop -
  fixed by emitting `tfdt` from an accumulator of sample durations so fragments tile
  exactly. Preview now plays at 1.0x with contiguous buffering. See the two
  "RESOLVED: fMP4 preview..." sections below.

## What changed (all deployed via cleanbuild + OTA unless noted)

1. **Motor IRQ sleeping bug** - `overrides/ingenic-sdk/common/misc/motors-pp/motor.c`
   `jz_timer_interrupt -> motor_move_step` called `gpio_direction_output()` (takes the
   pinctrl mutex -> sleeps) from IRQ context. Changed to `gpio_set_value()`; direction is
   established once in `motor_power_on/off` and at probe for `motor_switch_gpio`.
   Fixes: `BUG: sleeping function called from invalid context at mutex.c`.

2. **Wifi RX kthread** - `overrides/wifi-atbm6031/hal_apollo/apollo_sdio.c`
   `atbm_sdio_wait_action()` ran `period_handle`/`pre_sched` (which call `sdio_claim_host`
   -> sleeps) while the task was `TASK_INTERRUPTIBLE`. Set `__set_current_state(TASK_RUNNING)`
   across those handlers. Fixes: `do not call blocking ops when !TASK_RUNNING` in `phy0-sdio_rx`.
   NOTE: the wifi override must have `package/wifi-atbm6031/0001-*.patch` applied manually
   (overrides bypass Buildroot patches); it is applied in that override tree.

3. **IR-CUT / i2c1 pinmux conflict** - `configs/cameras/cinnado_d1_t31l_sc2336_atbm6031/*.dtsi`
   The base `swan_t31.dts` enables I2C1 on PB25/PB26; this board wires PB25/PB26 to the
   IR-CUT (thingino.json `gpio.ircut: "57 58"`). Added `&i2c1 { status = "disabled"; };`.
   Fixes: `pinctrl-ingenic.c: gpio functions has redefinition` on IR-CUT init.

4. **ciao<->master clock-resolver parity** - `ciao/thingino.mk`
   `ISP_CLKA` gained `VPLL:vpll`; added the missing `ISP_CLKV` block + `export ISP_CLKV_CLK_SRC/CLK`.

5. **THE encoder fix** - `overrides/ingenic-sdk/common/avpu/avpu_main.c` (T31 branch).
   The SDK T31 branch used 3.10-era clock names and bare `clk_enable()`. Fixed to:
   - names `gate_ahb1` / `gate_el150` / `div_el150` (matching the SDK's own T40 branch);
   - source PLL selected on `mux_el150` (`mux_el150 -> div_el150 -> gate_el150`);
   - `clk_prepare_enable()` instead of `clk_enable()` (4.4 `clk.c:740` WARNs and returns
     `-ESHUTDOWN` when `prepare_count==0` -> clocks never enabled -> AVPU unclocked -> hang).
   Result: `/dev/avpu` present, avpu probe ok, sensor `s_stream` ret=0, encoder channels
   init, RTSP on :554 (1080p@15 + sub@10).

6. **Diagnostic probes** (still compiled in, harmless, remove when done):
   - `overrides/ingenic-sdk/common/sensor/t31/sc2336.c` - logs `sc2336 s_stream` enter + write ret.
   - `overrides/open-tx-isp/driver/t31/tx_isp_module.c` - logs `sd.clk_num/cgu_isp/isp_clk/csi_clk`.

## Video-pipeline wedge - probe findings (2026-10-09, same day)

Instrumentation added (temporary, `grep WEDGE` / `grep PWEDGE` to find every site):

- Kernel (open-tx-isp override, `[WEDGE]` `pr_err`):
  - `driver/t31/tx_isp_core.c` `ispcore_interrupt_service_routine`: `ISR in`/`ISR out`
    for frame-end (`int & 1`) and error (`int & 0x3f8`) bits plus a 1/16 heartbeat;
    drain counts per channel; bounded the two ISP rel-ack busy-waits.
  - `driver/t31/tx_isp_frame_done.c` `isp_frame_done_wakeup`: frame counter (1/4).
  - `driver/t31/tx_isp_vic.c`: `vic_start`/`vic_stop` enter/ok, `vic_frd`/`vic_mdma`
    counts (1/4), `tx_isp_vic_wait_frame_done` timeout.
  - `driver/t31/tx_isp_module.c`: frame-channel ioctl entry (QBUF/DQBUF/REQBUFS),
    `DQBUF ... done`, `QBUF ... done`, and sub-steps inside
    `__submit_buffer_to_msca` (`msca ... y/built/wr-y/wr-uv/wr-done`), plus the
    ISR `dqbuf ... y=` handoff in `frame_chan_event`.
- prudynt (override tree at `ef72164`, `[PWEDGE]`): `src/util/WedgeProbe.hpp` writes
  `<3>[PWEDGE] ...` to `/dev/kmsg` (prudynt's stdout is `/dev/null` in S31prudynt, so
  `/dev/kmsg` is the only way the userspace breadcrumbs reach the serial console and
  syslog at once). Call sites: `VideoWorker.cpp` (`poll`, `get-begin`, `get-done`,
  `mp4 emit`) and `MP4Muxer_simple.cpp` (`muxVideo`).

Console gotcha: `overlay/etc/sysctl.conf` sets `kernel.printk = 3 3 1 3`, so `pr_err`
(level 3) never reaches the serial console. `echo 4 > /proc/sys/kernel/printk` at
runtime makes the probes visible; no persistent config was changed.

Reproduction: boot to login, then connect one RTSP client
(`ffmpeg -rtsp_transport tcp -i rtsp://thingino:thingino@192.168.88.141:554/ch0 ...`).
The wedge fires within ~1-2 s of playback starting; while idle the pipeline runs
indefinitely. Two clients reproduce just as readily as one, so it is **not**
load-dependent.

Symptom: serial output stops mid-stream with no panic/oops; IRQs are off (no further
ISR heartbeat), and the hardware watchdog resets the SoC. The camera came back on its
own every time in these runs (no cloner needed).

Where it hangs: the last printed line is always a *completed* handoff operation, and
which one varies per run:

- frame-end `ISR out` (`drains=1/0/0`),
- `DQBUF ch0 ... done`,
- `QBUF ch0 idx=0 done`,
- one run stopped inside `__submit_buffer_to_msca` right after its entry print, before
  the `built`/`wr-y` prints.

The submit path only does arithmetic (`tx_isp_nv12_buffer_build`,
`tx_isp_dma_range_validate`, both loop-free) and two `writel`s to the MSCA FIFO ports
`core_regs + (ch << 8) + 0x996c` (Y) and `+ 0x9984` (UV). A wedge that moves between
the ISR, DQBUF and QBUF, and always lands on an MMIO access, reads as an **ISP/MSCA AXI
stall (or clock/rmem glitch) entered during buffer handoff**, not a deterministic
single-instruction bug. The identical writes exist in the OEM queue-buffer path
(`tx_isp_core.c` `ispcore_pad_event_handle` case 0x3000005) with no polling, so it is
not a software FIFO-full guard that is missing per se.

Next threads (not yet run):

- Probe the encoder side: `IMP_Encoder_GetStream`/`PollingStream` map to `/dev/avpu`
  (`avpu_main.c`, `wait_event_interruptible(chan->irq_queue, ...)` at line 236). The
  userspace `get-begin`/`poll` probes are already in place to tell whether the hang is
  in the encoder path instead of tx-isp; every captured hang so far ended on a tx-isp
  op, but a couple more runs would make that conclusive.
- Re-audit ISP/MSCA clocks: the ciao<->master clock-resolver parity fix (item 4 above)
  may still be missing the MSCA/AXI clock; a gated-block MMIO access stalls the bus
  exactly like this.
- Consider `CONFIG_DEBUG_SPINLOCK`/lockdep or a bounded MSCA status check to rule a
  spinlock deadlock and a FIFO-full stall in/out.

### RESOLVED: OSD burn-in is what wedges the ISP

The wedge is the **OSD burn-in path**, not the MSCA buffer handoff itself. On the
first reader (RTSP PLAY on ch1) prudynt creates and starts the timestamp overlay:

    IMP_OSD_CreateRgn -> IMP_OSD_RegisterRgn -> IMP_OSD_SetRgnAttr
      -> IMP_OSD_SetGrpRgnAttr -> IMP_OSD_Start(osdGrp)

`IMP_OSD_Start()` is the last call before the hang (the `OSD: burned-in timestamp`
log is the line right before it). The open ISP stack + vendor libimp does not drive
the ISP OSD/region hardware correctly, so starting the OSD group stalls an ISP
register access -> IRQs off -> watchdog reset. That is why "it runs until someone
reads it", and why the fatal trace line drifts between ISP register accesses.

Proof (device test, 2026-10-09):

- `osd.burnin.enabled=true` (default): PLAY -> `IMP_FrameSource_EnableChn(1)` ->
  `encoder resumed` -> `OSD: burned-in timestamp` -> hang.
- `osd.burnin.enabled=false`: PLAY -> `encoder resumed` -> `ch1 prepending SPS/PPS
  to frame`; a 90 s RTSP pull (`ffmpeg -t 90 ... ch1`) finished with exit 0, camera
  up, no reboot.

Fix shipped (device-scoped, written to
`$THINGINO_USER_DIR/cinnado_d1_t31l_sc2336_atbm6031/192.168.88.141/prudynt.json`,
`/home/paul/.thingino/user/...` on this machine):

    { "osd": { "burnin": { "enabled": false } } }

`prudynt-t.mk` deep-merges user `prudynt.json` files (common/camera/device, in that
order) into `/etc/prudynt.json` via `jct import`, so this flips only that one key.

This is still a workaround: the correct fix is to implement the OSD/region path in
the open stack and re-enable burn-in. SEI and privacy OSD are also off in the config,
so no other `IMP_OSD_*` path is exercised. Watch for anything that turns OSD back on
(WebUI toggle, other camera configs) - that reintroduces the wedge.

Retired crutch: while the cause was unknown, prudynt was disabled with a
non-executable shadow (`overlay/usr/bin/prudynt`). That stub is now parked at
`$THINGINO_USER_DIR/cinnado_d1_t31l_sc2336_atbm6031/192.168.88.141/prudynt-stub.disabled`
(outside the overlay, so it is not deployed). Restore it to
`overlay/usr/bin/prudynt` and rebuild if a future build regresses and the camera
must boot without the streamer (`S31prudynt` exec fails, `S32prudyntwd` sees
`[ ! -x /usr/bin/prudynt ]` and exits). `chmod -x` on the real binary does **not**
work here: this 4.4 overlayfs has no metadata-only copy-up.

If `make ota` ever fails with `scp: /sbin/sysupgrade-stage2: No such file or
directory`, the device overlay upperdir is in a bad state (seen after manual `rm`s:
`/usr`/`/usr/sbin` reject new files with ENOENT). Recover by flashing with the
in-place wrapper (the camera already carries a matching stage2):
`scp -O images/thingino-*.bin root@<ip>:/tmp/fw.bin && ssh root@<ip> '/tmp/sup -x /tmp/fw.bin'`.

### RESOLVED: ch0 MSCA output was a bogus frame crop

Symptom: ch0 (main) showed only ~6-10 image rows then all green; ch1 was fine.

Diagnosis - live `devmem` at the ISP base `0x13300000` while ch0 streamed:

    0x9900 (ch0 MSCA output size) = 0x075A0006  -> 1882 x 6    (WRONG)
    0x9A00 (ch1 MSCA output size) = 0x030001B0  ->  768 x 432  (correct)

so the ch0 output-height register literally held **6** -> the MSCA wrote only a handful
of lines per frame. (The earlier "all green" was just the RGB view of an all-zero NV12
buffer.)

The driver trace (`echo 1 > /sys/module/tx_isp_t31/parameters/t31_runtime_trace`)
pinned it:

    SET_FORMAT ch=0 ... fcrop=1/38,38 1882x6
    ATTR_SET   ch=0 ... fcrop=1/1882x6+38+38 attr=0/0x0 -> out=0x075a0006

Two reimplementation bugs in `tx_isp_core.c`:

1. `tisp_channel_attr_set` read the *global* frame crop out of `ds0_attr` words 8..12.
   Those words are the per-channel attr (`memcpy(ds0_attr, arg2, 0x34)` just above), not
   the fcrop. The OEM keeps the fcrop in dedicated globals (`data_a2df4..data_a2e04`,
   set by `tisp_s_fcrop_control`), which the memcpy cannot disturb. Fix: use the
   `data_b2e04/e08/e0c/e10/e14` globals and drop the block that wrote them from
   `ds0_attr`. (With no crop armed, `data_b2e04 == 0` -> full sensor size.)
2. `ispcore_pad_event_handle` SET_FORMAT armed the crop from the VIC payload
   (`format->fcrop_*`). The OEM never does that - it sets the fcrop only through its
   dedicated control (ioctl 0x80000e3 / the netlink param path). The VIC payload carries
   a bogus `fcrop=1/38,38 1882x6` (ch0) / `1/38,38 730x394` (ch1). Fix: drop the
   `tisp_s_fcrop_control()` call from SET_FORMAT.

After the fix: live registers `0x9900 = 0x07800438` (1920x1080), `0x9A00 = 0x030001B0`
(768x432); plane capture shows ch0 rows 0..1079 with normal chroma, ch1 unchanged, and a
60 s dual-stream pull exits clean with no reboot.

Not chased further: *where* libimp's VIC payload sources the `38,38 1882x6` fcrop (likely
a vendor-libimp <-> open-struct mismatch). The fix makes the driver ignore it, matching
OEM. If a real frame crop is ever needed, it must come through the 0x80000e3 path.

### RESOLVED: fMP4 preview declared a broken audio track

Symptom: the WebUI preview showed MJPEG but never fMP4 (main `/preview.html` uses
`/a/preview-fmp4.js` with an MJPEG fallback).

Diagnosis (headless Chrome + playwright against the real page, session cookie):

- The fMP4 endpoint is fine: `:8080/chN.mp4` and `/x/fmp4.cgi?ch=N` both return 200
  `video/mp4` with valid `ftyp`/`moov`/`moof+mdat` and decode in ffmpeg.
- In the browser, `MediaSource.addSourceBuffer('video/mp4; codecs="avc1.4D001E,
  mp4a.40.2"')` succeeded and every `appendBuffer` succeeded, but `buffered` stayed
  **empty** and `readyState` stayed 1 forever.
- The `moov` declared **two** tracks (video + aac) but every fragment carried a single
  (video) `traf`, and the audio track had **0 packets** - because the AAC encoder never
  opened ("faac_encoder_get_info failed: invalid argument" / "IMPAudio::createNew
  failed"). MSE initialised for `avc1+mp4a` then buffered nothing.
- With audio disabled the fMP4 is video-only (muxer emits one `traf`, no mp4a in the
  `moov`); MSE buffered and played (reached `readyState=4`, `currentTime` advancing).

Fix (device-scoped `prudynt.json`, merged by `prudynt-t.mk`):

    { "audio": {"mic_enabled": false},
      "stream0": {"audio_enabled": false},
      "stream1": {"audio_enabled": false} }

This is a workaround for the broken on-board AAC encoder. The real fix is either to make
the AAC encoder open (audio bring-up) or to make prudynt's MP4 muxer omit the audio track
when the encoder is unavailable - then audio can be re-enabled.

Note: while probing I hit a transient overload (load ~10, `isp_fw_process` in D-state,
a stale `fmp4.cgi`->`curl` left holding a `ch0.mp4` client). Not the cause, but the fMP4
CGI `exec`s `curl`; a browser that reconnect-loops on a stalled stream can leave those
around. Reboot clears it.

### RESOLVED: fMP4 preview - fragment timing (tfdt)

With the audio track gone the fMP4 is video-only and MSE can decode it, but the
preview still showed "Preview drifted behind live edge, resyncing..." and blank,
because MSE buffered only a couple of small ranges (e.g. `[[0.07,0.33],
[6.07,6.53]]`) out of ~80 `appendBuffer` calls.

`MP4Muxer_simple::write_fragment` wrote each one-sample fragment's `tfdt` as the
raw encoder PTS while the sample `duration` was the *previous* delta. The ch1
substream is 10 fps off a 15 fps source, so its PTS steps 66/134 ms; jittered PTS
plus previous-delta durations makes consecutive fragments overlap (and gap). MSE
discards the overlapping fragments (ffmpeg tolerates them), so the buffer stayed
sparse, the media edge lagged the wall clock by more than `MAX_DRIFT_S` (5 s), and
`preview-fmp4.js` resynced in a loop.

Fix: emit `tfdt` from a running accumulator of the sample durations
(`TrackState::accum_ticks`) instead of the raw PTS, so consecutive fragments tile
exactly. It still tracks the encoder PTS in aggregate (the accumulator sums the
same deltas), so the live edge stays in sync. This is prudynt code:
`overrides/prudynt-t/src/recording/MP4Muxer_simple.cpp` (also affects the recorder
muxer, which is the same class).

### RESOLVED: fMP4 preview stall - lost wakeup resuming the substream

Even after the tfdt fix the preview still stalled/resynced intermittently: the
ch1 fMP4 client received only the cached init segment (~663 bytes) and no
frames, the JS drift guard fired, and the resync loop froze the view.

`VideoWorker`'s idle path waited with a bare `should_grab_frames.wait(lock)`
after checking the wake conditions once. `video_consumer_add()` (called by the
HTTP fMP4/MJPEG path) sets `hasDataCallback` and `notify_one()` *without* taking
`mutex_main`, so a notification landing between that check and the wait was
lost. The ch1 worker then stayed parked with the substream encoder paused and
never resumed it, so the per-client fMP4 tap got no frames (ch0 is unaffected -
it never pauses).

Fix: replace the bare wait with a predicate wait that re-evaluates every wake
condition, so the notification cannot be lost. `overrides/prudynt-t/src/video/
VideoWorker.cpp`, idle-path loop.

After the fix, ch1 fMP4 streams from the first request (TTFB ~0.2 s, ~200 KB in
8 s) and the browser preview runs 120 s at 1.0x with contiguous buffering and no
resync.

## Commands

Build (ALWAYS cleanbuild while debugging - user's rule; staging incremental rebuilds into
`target/` repeatedly shipped stale modules):
```
cd /home/paul/thingino/firmware/ciao
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.141 make cleanbuild
CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.141 make ota      # full image, reboots
```
Recovery from a hard wedge (bootrom; SoC enumerates as `a108:c309`):
```
thingino-cloner -l
thingino-cloner -i 0 -b -w <image.bin> --cpu t31x --reboot -v
```
Image: `$(THINGINO_OUTPUT_ROOT_DIR)/ciao/cinnado_d1_t31l_sc2336_atbm6031-4.4.94-uclibc-192.168.88.141/images/thingino-cinnado_d1_t31l_sc2336_atbm6031.bin`

Useful on-device:
- `/proc/jz/isp/clks` (ISP clocks), `/proc/jz/sensor/*` (`mclk` here is NOT the live MCLK - red herring)
- `dmesg | grep '\[CLK\]'`, `logcat`, `/etc/init.d/S31prudynt {start|stop}`

## Open follow-ups

1. **Video-pipeline wedge** (main open issue). With prudynt enabled it intermittently
   hard-wedges the kernel (IRQs off, serial dead) at boot or shortly after. Confirmed NOT
   audio (a build with `mic_enabled:false` + stream `audio_enabled:false` still wedged).
   Next: `pr_err` probes through prudynt's `VideoWorker`/`MP4Muxer_simple` frame path and
   the kernel VIC/ISP frame IRQ + buffer handoff (`tx_isp_core.c` VIC start,
   `tx_isp_vic.c` frame done); also try reduced load (lower res / 1 stream / lower fps)
   to test whether it is load/race triggered.

2. **Daemon heartbeat / WebUI**: `json-heartbeat.cgi` is an SSE stream; main.js's XHR to it
   times out by design. Heartbeat daemon (`S99heartbeat` -> `/run/thingino/heartbeat.json`)
   was healthy (cache age ~4s). `fmp4.cgi` (preview) is not in `thingino-webui`.
   Re-check only if the preview is actually broken.

3. **Upstream the real fixes**: avpu `clk_prepare_enable` (SDK), motor `gpio_set_value`
   (SDK motors-pp), wifi `apollo_sdio.c` state fix (gtxaspec/atbm-wifi), and remove the
   diagnostic probes.

## Uncommitted dev-tree changes (all revertible)

- `overrides/ingenic-sdk`: `Kbuild`, `common/avpu/avpu_main.c`, `common/misc/motors-pp/motor.c`,
  `common/sensor/t31/sc2336.c`, `common/sensor/t32/gc2063.c`, `common/sensor/t32/gc2083.c`
- `overrides/open-tx-isp` (not a git repo): the temporary `[WEDGE]` probes in
  `driver/t31/{tx_isp_core,tx_isp_vic,tx_isp_module,tx_isp_frame_done}.c` have been
  **reverted** (`tx_isp_vic/module/frame_done` are back to their pre-probe state). The
  only remaining change is the **ch0 fcrop fix** in `tx_isp_core.c` (two hunks:
  globals in `tisp_channel_attr_set`, and no crop arming in SET_FORMAT). The probe
  `pr_err` firehose was starving the pipeline: with it in, ch0 ran ~11 fps; after
  removing it, ch0 holds 15.01 fps over 90 s. Backups (pre-probe) in
  `/tmp/kilo/wedge-backup/` for this session only.
- `overrides/prudynt-t`: `src/video/VideoWorker.cpp` and
  `src/recording/MP4Muxer_simple.cpp` probe edits and `src/util/WedgeProbe.hpp` have
  also been **reverted** - prudynt is back to the plain `ef72164` tree.
- `overrides/wifi-atbm6031`: `hal_apollo/apollo_sdio.c` (+ `0001` patch applied manually)
- `ciao/local.mk`: `INGENIC_SDK_OVERRIDE_SRCDIR`, `OPEN_TX_ISP_OVERRIDE_SRCDIR`,
  `WIFI_ATBM6031_OVERRIDE_SRCDIR` enabled, and now also
  `PRUDYNT_T_OVERRIDE_SRCDIR` enabled so the instrumented prudynt-t tree is built
  (`local.mk` backs up to `/tmp/kilo/wedge-backup/local.mk`; revert to disable probes)
- `ciao/thingino.mk`: clock-resolver parity
- `ciao/configs/cameras/cinnado_d1_t31l_sc2336_atbm6031/*.dtsi`: i2c1 disabled

## Risks / assumptions

- The i2c1 disable assumes IR-CUT is truly on PB25/PB26 (user confirmed the dtsi is
  hardware-bound). Sensor is on i2c0 (`0-0030`).
- `override` builds bypass Buildroot patches; apply `package/<pkg>/*.patch` into the
  override tree manually (bit the wifi override).
- Incremental `make rebuild-<pkg>` leaves the final `target/` stale / shadowed between
  per-package snapshots (seen with motor.ko and avpu.ko) - hence the cleanbuild rule.
- The camera currently only boots with prudynt disabled; do not re-enable until the
  video-pipeline wedge is fixed.

# Mainline 7.x bring-up (branch `mainline-7x`)

Goal: run the Cinnado D1 (T31L + SC2336) on **mainline Linux 7.x** with the open
tx-isp driver - no vendor kernel, no blob `tx-isp.ko`, libimp still the vendor one
(the AKoo7 / gtxaspec approach). Do **not** fall back to 4.4.

## Current state: BOOTS to userspace on mainline 7.1-rc1

- cleanbuild produces a fitting 8 MB image (kernel 7.1-rc1 + DTB + open ISP +
  SC2336 + rootfs), and the kernel **boots all the way to the Thingino login
  prompt** (`Welcome to Thingino!` / `...-cinnado-d1-f8a3 login:`) with the
  squashfs rootfs mounted from `mtdblock4`.
- The former boot hang (once attributed to the SFC driver) is **root-caused and
  fixed** - see "RESOLVED: the boot hang was a blk-mq scheduler init hang".
- Still open for a *usable* camera: atbm6031 WiFi does not build on 7.1, so the
  image is networkless; and the camera `.dtsi` is skipped (no `isp`/`msc1_pb`
  labels), so GPIOs / open ISP are not applied. See "Also open for mainline".

## Branch / wiring (all local, not pushed)

- Branch `mainline-7x`, branched from `open-4.4.94`.
- `local.mk` (gitignored, so NOT in the commit): `OPEN_TX_ISP_OVERRIDE_SRCDIR`
  points at `overrides/open-tx-isp-mainline`.
- **Override `overrides/open-tx-isp-mainline`** = AKoo7 `t31-6.12-port-v2`
  (github.com/AKoo7/open-tx-isp) + our ch0 fcrop fix (both hunks) + new
  `sensor-src/t31/sc2336.c` (copied from `overrides/ingenic-sdk/common/sensor/t31/`,
  includes adapted, registered in `sensor-src/t31/Kbuild`) + compat:
  `#include <linux/clk-provider.h>` in `driver/t31/include/tx_isp_kernel_compat.h`
  (for `__clk_is_enabled`), and `V4L2_MBUS_FMT_SBGGR10_1X10`/`SGBRG10_1X10` ->
  `MEDIA_BUS_FMT_*` aliases in `sensor-src/t31/include/sensor-common.h`.
- `package/open-tx-isp/Config.in`: `..._SUPPORTED` also `KERNEL_VERSION_7` for
  t31; `BR2_PACKAGE_OPEN_TX_ISP` `depends on BR2_PACKAGE_INGENIC_SDK ||
  KERNEL_VERSION_7`.
- `package/open-tx-isp/open-tx-isp.mk`: on `7.1-rc1` drop `ingenic-sdk`, add
  `sensor-src/$(SOC_FAMILY)` to `MODULE_SUBDIRS`, skip the xburst `EXTRA_CFLAGS`.
- `package/thingino-isp/Config.in`: `select BR2_PACKAGE_INGENIC_SDK` made
  `if !KERNEL_VERSION_7` (was the "selects SDK even on kernel 7" bug).
- Camera defconfig: `KERNEL_VERSION_7=y`; `BR2_THINGINO_DEV_PACKAGES=y`
  (required, because `BR2_THINGINO_DEV_EXPERIMENTAL` - which gates the kernel-7
  choice - lives inside `if BR2_THINGINO_DEV_PACKAGES`); `BR2_LINUX_KERNEL_PATCH`
  -> `package/all-patches/linux/7.1-rc1`; `# BR2_PACKAGE_THINGINO_KOPT_IPV6 is
  not set`; WiFi package lines removed (atbm6031 doesn't build on 7.1 yet); the
  4.4.94-mmc patch line dropped.
- `Makefile`: `KERNEL_PARTITION_SIZE` = 2621440 (2560K) for `KERNEL_VERSION_7`,
  else the 1728K universal. Must match the DT.
- `package/all-patches/linux/7.1-rc1/`:
  - `0001-mips-only-build-FIT-image-for-generic-kernel.patch` (pre-existing, by
    gtxaspec; it was never wired before - that's why the MIPS FIT `.itb` step
    failed the whole kernel build).
  - `0002-dt-thingino-t31-match-sfc-layout.patch` (ours) rewrites
    `thingino-t31.dts` partitions to the thingino SFC map:
    `320k(boot),64k(env),64k(backup),2560k(kernel)@0x70000,4416k(rootfs)@0x2f0000,768k(data)@0x740000,8192k@0(all)`.
  - `0003-mtd-mtdblock-avoid-blk-mq-sched-init-hang.patch` (ours) - the boot
    fix; see "RESOLVED: the boot hang was a blk-mq scheduler init hang".
  - `0004-spi-ingenic-sfc-bound-sr-end-poll.patch` (ours) - defensive bound of
    the PIO RX `SR_END` poll (was `timeout_us = 0`).

## The hang

Serial, booting with `earlycon ignore_loglevel initcall_debug` (earlycon kept
working even after the real console would appear):

```
calling 0x8077b944 @ 1                     = ingenic_sfc_driver_init
7 fixed-partitions partitions found on MTD device spi0.0
Creating 7 MTD partitions on "spi0.0":
0x000000000000-0x000000050000 : "boot"
<hang - no more output, no SFC PIO timeout log>
```

Addresses resolve against `System.map` with `mipsel-linux-nm` on the built
`vmlinux` (`vmlinux` text base 0x80000000; e.g. `0x8077b944 ->
ingenic_sfc_driver_init`).

Prime suspect: in `spi-ingenic-sfc.c`, the PIO READ path does
`readl_poll_timeout(sfc->base + SFC_REG_SR, val, val & SR_END, 10, 0)` - the
trailing `timeout_us = 0` means **no timeout / infinite poll** on `SR_END`. If
`SR_END` never asserts it spins forever. The IRQ-completion wait just above uses
`SFC_TRANSFER_TIMEOUT = 1000` ms and would log `SFC PIO timeout: SR=… GLB=…
CONF=…` instead. DT: `sfc: spi@13440000`, `compatible = "ingenic,t31-sfc"`,
`interrupts = <7>`, `clocks = <&cgu T31_CLK_SFC>` (node ships `status =
"disabled"`, enabled by `thingino-t31.dts` `&sfc`).

Next: patch `spi-ingenic-sfc.c` to bound that poll (real timeout) and add an
explicit `dev_err` where `SR_END` never sets; if the transfer IRQ isn't arriving,
diagnose IRQ 7 / `T31_CLK_SFC` (AKoo7's notes flag the T31 CGU CE/busy/stop
handshake as still-to-upstream). Rebuild + re-flash. Whether the flash op truly
never completes matters: if not, squashfs can't mount, so the poll fix alone may
not boot.

### RESOLVED: the boot hang was a blk-mq scheduler init hang

The SFC poll was **not** the cause. Instrumenting the kernel (with
`CONFIG_CMDLINE="earlycon keep_bootcon"` so the boot console survives the
`ttyS1` handover, plus `pr_err` breadcrumbs) showed the flash and MTD paths work
and the hang is one layer above the flash:

```
ingenic_sfc_driver_init
  spi-nor probe: RDID 0x9f + SFDP 0x5a reads  -> OK
  mtd_device_parse_register -> add_mtd_partitions
    allocate_partition "boot"                  -> OK
    add_mtd_device("boot")
      device_register                          -> OK
      blktrans_notify_add -> add_mtd_blktrans_dev
        blk_mq_alloc_disk                      -> OK
        device_add_disk
          __add_disk: device_add ... blk_register_queue
            elevator_set_default -> elevator_change
              elevator_switch                  -> HANG
```

So the last serial line ("... : \"boot\"") is just the last print before the
first MTD partition's **mtdblock** device is registered; no flash read happens
there. `elevator_switch()` spins with preemption disabled (no soft-lockup or
hung-task backtrace is emitted even with both detectors enabled).

Fix (patch `0003-mtd-mtdblock-avoid-blk-mq-sched-init-hang.patch`): mark the
mtdblock tag set with `BLK_MQ_F_NO_SCHED_BY_DEFAULT` so
`elevator_set_default()` returns before `elevator_change()`. mtdblock is happy
with the "none" scheduler, and the mtdblock4 squashfs rootfs mounts. This is a
workaround - the real bug (why `elevator_switch()`/`blk_mq_init_sched()` spins
for this queue on T31/7.1) is still open.

Defensive extra (patch `0004-spi-ingenic-sfc-bound-sr-end-poll.patch`): bound
the PIO RX `readl_poll_timeout(..., SR_END, 10, 0)` (a trailing 0 means "no
timeout") and log SFC state if `SR_END` is never seen. Verified on the T31 that
this poll does pass (SFDP + `0x03` page reads step through it), so it only turns
a theoretical infinite loop into a bounded failure.

Reproduction / debug recipe that made this visible:
- Boot via U-Boot with `setenv bootargs ... earlycon ignore_loglevel
  initcall_debug keep_bootcon` then `sf probe; sf read $loadaddr $kern_addr
  $kern_size; bootm $loadaddr`. **Without `keep_bootcon` the real ttyS1 console
  stops after the bootconsole handover**, so all later output (including panic
  or breadcrumbs) is invisible - always boot with `keep_bootcon` when debugging.
- `make dfu` (thingino-dfu over USB bootrom) flashes the whole 8 MB image;
  entering bootrom: at U-Boot `sf erase 0 10000` then `reset`.

## Also open for mainline

- **WiFi (`atbm6031`) doesn't build on 7.1**: `hal_apollo/Makefile` `k-dir`
  resolves to the kernel tree (`$(k-dir)/../include/linux/compat-2.6.h` ->
  `<linux>/include/...`, no such file) and it's a 4.4-era backport. The camera is
  WiFi-only, so the flashed image is networkless - fix this to get remote access.
  See "SDIO / WiFi (atbm6031)" below for the bus-side progress.
- **Camera `.dtsi` is now applied on 7.1** (patches 0005-0007); it used to be
  skipped because the tree had no `isp` label and no `msc1_pb` group. It is still
  worth watching on other 7.1 cameras: the fragments are the 4.4-vendor
  3-cell-GPIO form and now rely on the `ingenic-pinctrl.h` shim
  (`INGENIC_GPIO_*` defined empty).

## SDIO / WiFi (atbm6031) - in progress

Planned conversion work, options and decision points are in
[docs/dev/cinnado-d1-wifi-roadmap.md](cinnado-d1-wifi-roadmap.md). Summary of
where it stands:

MSC1 is the SDIO bus for the atbm6031. The bus now comes up on 7.1:

- `t31_chip_info` had no `mmc1` pin groups at all (only `mmc0` on GPB0-5), so
  the pins could never mux. Patch `0005` adds the PB8-11/PB13-14 groups
  (function 1) and the `msc1`/`msc1_pb` plumbing is added in `0006`.
- The board is WiFi-only, so the camera fragment also disables `&mac` (the
  generic T31 leaf enables it and its `mac-rmii` group claims PB6-14, the same
  pins MSC1 needs).
- With that, `jz4740-mmc 13460000.mmc` probes and starts SDIO init
  (`mmc1: Using PIO, 1-bit mode`).

**Still failing:** the SDIO card does not finish initialising -
`jz4740-mmc 13460000.mmc: no support for card's volts` -> `mmc1: error -22
whilst initialising SDIO card` -> `mmc1: Card stuck being busy!
__mmc_poll_for_busy` (repeats). W0 investigation so far:
- `Card stuck being busy` means the card drives DAT0, so it **is** powered -
  this is an SDIO OCR/protocol failure, not a missing WLAN power rail.
  `no support for card's volts` is `mmc_select_voltage()` finding the CMD5
  OCR with no bits in `host->ocr_avail` (only `MMC_VDD_32_33 | MMC_VDD_33_34`).
- Re-probing msc1 (`echo 13460000.mmc > .../jz4740-mmc/unbind` then `bind`)
  reproduces it exactly, so it is not a one-shot init race.
- The mainline `jz4740_mmc` driver parses **no** DT properties: the fragment's
  `ingenic,sdio_clk = <1>` and `bus-width` are ignored. LPM only engages above
  25 MHz (`jz4740_mmc_set_clock_rate`), and `max-frequency = <25000000>` is at
  the boundary, so LPM is not the cause here.
- Userspace is not ready to help on 7.x: `/etc/init.d/S36wireless` only powers
  the WLAN GPIO for `3.10|4.4` (`*)` branch prints "Skipping WLAN GPIO
  toggling") and it exits with `line 188: syntax error: unexpected end of file`;
  `/sbin/gpio` uses the **sysfs** GPIO ABI but this kernel exposes no
  `gpiochipN` nodes (only `export`/`unexport`), so `gpio set 47 1` fails with
  `Invalid argument`; the `mmc` / `mmc_gpio` helpers are not installed.
- WLAN power is GPIO 47 active-high (`gpio_default` in the camera `uenv.txt`
  has `47O`, and `thingino.json` `gpio.wlan` is 47) - U-Boot likely already
  asserts it.

Next experiment for W0: instrument `mmc_select_voltage()` (or
`mmc_sdio_init_card`) to print the card's raw CMD5 OCR and `ocr_avail`, then
decide between widening `ocr_avail`, adding an `mmc-pwrseq`/`regulator-fixed`
for GPIO 47 on msc1, and a `bus-width = <4>` + timing fixup.

W0 results (all done, still not enumerating):
- `mmc_select_voltage()` shows `card_ocr=0x00000000 host_ocr_avail=0x00300000`
  - the card answers nothing to CMD5, so this is not a voltage-window mismatch.
- The first real bug was the pinmux: the `msc1_pb` group only listed
  `"mmc1-4bit"`, so only PB11/PB13/PB14 were muxed and PB8-10 (CLK/CMD/DAT0)
  stayed GPIO. Fixed (patch 0006 now lists `"mmc1-1bit", "mmc1-4bit"`), and
  debugfs `pinmux-pins` confirms all six pins now belong to `13460000.mmc`.
- Made the mainline `jz4740_mmc` honour `ingenic,sdio_clk` (patch 0008) so the
  clock stays out of LPM; `clock:` debug showed `real_rate=187500 lpm=0`.
- Added a `regulator-fixed` (`wlan_pwr`, GPIO 47/PB15 active high) and wired it
  as `vmmc-supply` on msc1 in the camera `.dtsi`.

Despite pins + clock + power being correct, CMD5 still returns OCR 0 and the
card reports `Card stuck being busy`. Remaining hypotheses: pin bias/pull-ups on
CMD/DAT (mainline `mmc1` groups set no bias), the exact vendor pinmux group
(`msc1_pb` here vs `msc1_4bit` in the 4.4 node) / func number, a reset sequence
(vendor `ingenic,sdio-reset`), or a bus-width/clock timing quirk. Needs the
vendor 4.4 mmc driver/DTS diffed pin-for-pin.

### W0 - reference box comparison (2026-10-11)

A hardware-identical camera running the vendor 3.10 firmware was made
reachable (SSH), which gives ground truth:

- **Pins confirmed:** `/sbin/mmc_gpio` (run by `S09mmc`) sets **pb08-pb14,
  function 1** (`gpio-diag mode func1`, pb08 drive 2, the rest drive 1). Our
  `mmc1-1bit`+`mmc1-4bit` (PB8-14, func 1) is correct. The vendor also sets
  **pin drive strengths** we do not.
- **Driver:** in-tree `jzmmc_v1.2` (not mainline `jz4740_mmc`); the card is
  brought up by a userspace **"card insert via sysfs"** (~7.7 s) ->
  `mmc1: new SDIO card at address 0001`, then `S36wireless` loads `atbm6031`.
- **WLAN power:** `gpio.wlan = 47` (thingino.json). U-Boot does not leave it
  asserted; the vendor's `S36wireless` drives it for 3.10/4.4.
- **No DTB on the box** (embedded in the kernel image).

Direct register comparison (both cameras, same SoC):

| reg | `.141` (mainline, failing) | `.109` (vendor, working) |
|---|---|---|
| GPB `PAT0` (out) | `0x01555015` | `0x01555015` |
| GPB `PAT1` (dir) | `0x55555000` | `0x55555000` |
| `MSC1CDR` (CGU) | `0x080000FF` | `0x00000014` |
| `CLKGR0` bit5 (msc1 gate) | set (gated) | clear (running) |

So the **GPIO/power state is byte-for-byte identical**: power, pins and pin
function are not the difference. The mmc **driver/clock configuration** is. The
vendor's `jzmmc_v12.c` `jzmmc_set_ios()` keeps the SD clock running for SDIO:

```c
if (host->pdata->sdio_clk) {
        msc_writel(host, LPM, lpm);            /* no LPM_LPM bit */
        msc_writel(host, CTRL, CTRL_CLOCK_START);
} else {
        lpm |= LPM_LPM;
        msc_writel(host, LPM, lpm);
}
```

and `jzmmc_reset()` likewise writes `CTRL_CLOCK_START` for SDIO. The mainline
`jz4740_mmc` writes the divisor with a 16-bit `writew(..., JZ_REG_MMC_CLKRT)`
and uses the CGU clock framework (CE/stop/busy handshake) instead. Note the
`MSC1CDR` mismatch above - the mainline leaves a very different divisor.

**W0 conclusion:** not power, not pins, not timing (a re-probe at 89 s uptime
still fails). It is the MSC/SDIO clock programming: mirror the vendor's SDIO
behaviour in `jz4740_mmc` (keep the SD clock running via `CTRL_CLOCK_START`,
never `LPM_LPM`, and match the `CLKRT`/`MSC1CDR` divisor) and re-test.

**Tried (2026-10-11):** extended patch 0008 so `jz4740_mmc_clock_disable()` does
not gate the clock for `sdio_clk` hosts (keeps the SD clock running, mirroring
`jzmmc_set_ios()`). Built, flashed, and the card **still** returns OCR 0 /
`Card stuck being busy`. So the continuous clock alone is not enough - the
mainline `jz4740_mmc` still differs from the vendor `jzmmc_v1.2` somewhere in
the SDIO power-up/reset or CGU clock programming (`MSC1CDR` is still nowhere
near the vendor's `0x14`).

Open paths, in effort order:
1. Mirror the vendor's CGU clock programming for `sdio_clk` (set the CGU clock
   to the target rate like `jzmmc_set_ios()` does, not `f_max` + CLKRT divide)
   and its `jzmmc_reset()`/`jzmmc_power_on()` sequence.
2. Set the vendor pin drive strengths (pb08 drive 2, rest drive 1) via pinconf.
3. Port `jzmmc_v12.c` (source is in the 3.10 patch) onto the mainline mmc core
   - a real driver port, the fallback if the mainline driver can't drive this
   SoC's SDIO.

### W0 - newer Ingenic SDK (5.15.170) SDIO reference (2026-10-11)

The user provided a newer Ingenic SDK (`~/thingino/sdk/t32-33-2.0.0`, kernels
3.10/4.4/**5.15.170**). The 5.15 tree has a dedicated SDIO path:

- `drivers/mmc/host/ingenic_sdio.c` (uses `ingenic_mmc.h` or `sdhci-ingenic.h`)
  - a vendor SDIO glue, not mainline `jz4740_mmc`.
- SDIO bring-up is explicit and userspace-driven, `ingenic_sdio_wlan_power_onoff()`:
  1. power regulators (`wlreg_on`, `wl_vccio`);
  2. **`ingenic_mmc_clk_ctrl(index, 1)`** - turn the MSC clock gate ON;
  3. **reset pulse** - `gpio_set_value(reset, 0); msleep(10); gpio_set_value(reset, 1);`
     (with the clock already running);
  4. **`jzmmc_manual_detect(index, 1)`** - manual insert
     (`set_bit(CARD_PRESENT); mmc_detect_change()`).
- The driver keeps the clock running for `sdio_clk` hosts (`CTRL_CLOCK_START`,
  no `LPM_LPM`) - the same thing patch 0008 now does - and uses two clocks
  (`clk_cgu` + `clk_gate`).
- `ingenic_sdio_wlan_init()` requires an `ingenic,sdio-reset` GPIO (via the
  `android,bcmdhd_wlan` / `rtk,rtl8723ds_wlan` child node); without it the
  power-on helper returns `-EINVAL`.

**Implication:** the mainline `jz4740_mmc` never does the **reset pulse** (with
the clock on) or a **manual detect**; it relies on auto-detect. That - plus a
proper SDIO-capable driver - is the missing piece. Next test: pulse the WLAN
enable/reset (GPIO 47) low->high with the MSC clock running and force a rescan
on `.141`; if the card then answers CMD5, the fix is a reset-pulse+detect path
in the driver (or porting `ingenic_mmc`/`sdhci-ingenic`).

- Multi-issue: (1) port the atbm6031 module build to 7.1, (2) fix the
  `S36wireless` script for 7.1, (3) decide how the WLAN power/clock is driven
  (userspace vs. a `mmc-pwrseq`/`ingenic,sdio_clk` in the mmc driver), then
  re-check `no support for card's volts` / `Card stuck being busy`.

## Overlay corruption: JFFS2 erase-size mismatch (2026-10-11)

The 7.1 data partition (the overlayfs upperdir, `jffs2` on `/dev/mtdblock5`)
did not mount cleanly:

```
jffs2: Node at 0x00000e14 with length 0x000001ef would run over the end of the erase block
jffs2: Perhaps the file system was created with the wrong erase size?
jffs2: jffs2_scan_eraseblock(): Magic bitmask 0x1985 not found at 0x00001000: 0x1951 instead
jffs2: Truncating ino #25 to 7206 bytes failed because it only had 4096 bytes to start with!
overlayfs: upper fs does not support tmpfile / RENAME_WHITEOUT   <- benign, JFFS2 limitation
```

Root cause: erase-block mismatch. The mainline SPI NOR stack selects **4 KiB**
sectors (`CONFIG_MTD_SPI_NOR_USE_4K_SECTORS` defaults to `y`), so
`mtd->erasesize == 4096`, while the data image is packed with 64 KiB erase
blocks, so nodes straddle the kernel's 4 KiB scan boundary and are discarded.
4 KiB is not usable anyway: `mkfs.jffs2` rejects it ("Erase size 0x1000 too
small. Increasing to 8KiB minimum").

Fix:
- `board/ingenic/xburst1/kernel/7.1-rc1/t31.generic.config`: disable
  `CONFIG_MTD_SPI_NOR_USE_4K_SECTORS`. The 25Q64 has uniform 64 KiB blocks, so
  the driver then reports `erasesize == 65536`.
- `Makefile` / `Makefile.utils`: `JFFS2_ERASE_BLOCK` is 64 KiB for the mainline
  SPI NOR stack (and vendor `CONFIG_ERASE_SIZE_64K`), 32 KiB otherwise, and the
  `mkfs.jffs2` rule now uses it instead of the hardcoded `ALIGN_BLOCK`.

Built (kernel + 64 KiB `data.jffs2`) and flashed via bootrom DFU. Verified on
the next boot: `/proc/mtd` reports `erasesize 0x10000` on every partition, the
`jffs2` scan is clean (`0 xdatum / 0 xref`, no "wrong erase size") and the
overlay mounts (the `tmpfile` / `RENAME_WHITEOUT` lines are benign JFFS2
limitations). Persistence also confirmed: a file written through the overlay
before a reboot (`/etc/ovtest`) survived the reboot with a clean re-scan.

The earlier "wedged at ~0.036 s" was **not** the 4 KiB change: the config
regeneration that came with it dropped the local `keep_bootcon` tweak that had
been living only in the output tree, so the boot stopped at the 8250 handover
(`printk: legacy bootconsole [t31_uart0] disabled`) and needed a power cycle.
`keep_bootcon` is now carried in the fragment
(`board/ingenic/xburst1/kernel/7.1-rc1/t31.generic.config`,
`CONFIG_CMDLINE="earlycon keep_bootcon"`), so a clean rebuild keeps it. The
root cause of the handover stop (why the real `ttyS1` console goes silent
without the boot console) is still open - `keep_bootcon` is a workaround, and
it doubles every console line.

## Recovering / reflashing the camera

As of the boot fix the camera comes up on its own (login prompt on the serial
console), so the normal `make ota` path works again.

With an attached USB-Ethernet adapter the camera gets network (see below), so
`make ota` / SSH work and kernel iteration is fast. Without it, mainline 7.x has
no network (the ATBM6031 is not up), `make ota` is unavailable, and DFU is the
only path. U-Boot autoboot is keyed: it waits 1 s and stops on Ctrl-C
(`CONFIG_AUTOBOOT_STOP_STR "\x3"`, prompt `isvp_t31#`). If a `screen` already
holds `/dev/ttyUSB0` it can be driven from another shell with
`screen -S <session> -X stuff '...'` and read back with `-X hardcopy <file>`.

### Fast kernel iteration over SSH (USB-Ethernet attached)

The USB-Ethernet dongle (in-tree `asix`/`r8153_ecm`, `&otg` enabled) gives the
camera an IP (e.g. `192.168.88.111`) and SSH. Then a kernel-only change can be
flashed without bootrom/DFU:

```sh
make -C "$LINUX_DIR" ARCH=mips CROSS_COMPILE=mipsel-linux- -j"$(nproc)" uImage
scp -O "$OUT/images/uImage" root@<cam>:/tmp/uImage
ssh root@<cam> 'flashcp -v /tmp/uImage /dev/mtd3 && reboot'
```

`/dev/mtd3` is the kernel partition and is writable (unlike the read-only
`/dev/mtd0` boot partition), and `flashcp` erases+writes+verifies. This turns a
~12-minute bootrom+DFU cycle into seconds. Root password is `987987`.

For flashing without a booted userspace (e.g. iterating a kernel patch while the
camera is hung), use `make dfu` - `thingino-dfu` bootstraps the SoC over USB
bootrom and writes the whole 8 MB image (`thingino-<camera>.bin`). To *enter*
bootrom, reset to the U-Boot prompt and run `sf erase 0 10000` then `reset`; the
SPL/U-Boot is erased, so the boot ROM enumerates as `a108:c309` and
`thingino-cloner -l` reports stage `bootrom` (`t31x`). Then `make dfu`.
(The DFU boot does not stop at U-Boot, so it autoboots the freshly written
kernel unless you set `CONFIG_CMDLINE="... keep_bootcon"` or interrupt U-Boot.)

Fast kernel-iteration loop used this session (avoids a full `make fast`):
1. edit the kernel source in `output/.../build/linux-<hash>/`;
2. `PATH=$HAVE/host/bin:$PATH make -C <linuxdir> ARCH=mips CROSS_COMPILE=mipsel-linux- -j$(nproc) uImage`
   (incremental; detects the changed `.c` and relinks);
3. `cp <linuxdir>/arch/mips/boot/uImage output/.../images/uImage`;
4. `CAMERA=... IP=... make pack` (rebuilds `thingino-<camera>.bin` from `images/`);
5. `make dfu`.

The `images/uImage` is LZMA-compressed, so `strings images/uImage` finds nothing;
check `build/linux-*/vmlinux` for symbols/strings instead.

## Build/run notes learned this session

- Kernel 7 is only selectable with `BR2_THINGINO_DEV_EXPERIMENTAL`, which needs
  `BR2_THINGINO_DEV_PACKAGES` (see defconfig above).
- `KERNEL_VERSION_7` also gates the kernel-headers fragment choice; `defconfig`
  re-assembly is needed after defconfig edits.
- Changing the kernel config file / kernel patches does NOT re-prep the kernel on
  an incremental `make fast`; force it by removing `output/<...>/build/linux-*`
  (and `images/uImage`) so the kernel re-extracts + re-patches.
- The open-tx-isp override is rsynced into `build/open-tx-isp-custom`; after
  editing the override, remove that dir (or `make open-tx-isp-rebuild`) to force a
  re-rsync.
- **Debugging the post-handover console**: after the real `ttyS1` console is
  registered the boot console is disabled and, on this port, the real console
  emits nothing further (so panics and `pr_err` breadcrumbs are lost). Boot with
  `keep_bootcon` on the kernel command line (e.g. bake it into
  `CONFIG_CMDLINE`) to keep the boot console alive and see the whole boot.
- Build with `CAMERA=cinnado_d1_t31l_sc2336_atbm6031 IP=192.168.88.141`; output
  lands under `$THINGINO_OUTPUT_ROOT_DIR/<branch>/...-7.1-rc1-uclibc-<ip>/`.

