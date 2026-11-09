# T120 open-stack session handoff - 2026-11-08

## What changed

- **Open-only policy is implemented (uncommitted).** The proprietary Ingenic
  ISP choice and the vendor `libimp.so` provider are removed. `THINGINO_ISP_OPEN`
  is the only camera-provider option; `NONE` is limited to non-camera builds
  and A1. `OPENIMP` is selected unconditionally by the open ISP. Unsupported
  camera SoC/kernel combinations fail the build instead of falling back.
- **T41 7.x OpenIMP is enabled.** `BR2_PACKAGE_OPENIMP` is now built for the
  T120 (T41 + `KERNEL_VERSION_7`).
- **timps v1.12.0 is committed and rebuilt with `USE_OPENIMP=1`.**
  `package/timps/0001-...patch` was refreshed for the new jpeg idle path and
  `package/timps/timps.hash` now carries the `-git4` tarball hash.
- **Clean open image flashed to the T120.** It contains the **proven open
  `57d16f1` T41 module** (not the new `0138d8c1` base), OpenIMP `libimp.so`,
  and the OpenIMP `timpsd`. No vendor `libimp.so` is present.
- **T41 mainline sensor bridge work advanced.** With the disabled `0038`
  bridge enabled, the mainline `gc8613` attaches and `IMP_ISP_AddSensor`
  succeeds. The remaining blocker is the ISP video-link graph/pad setup.

## Why

- The user directive is: open stack is the default and only provider for all
  profiles; either open, or fail. No proprietary fallback.
- The new Lu-Fi `next` + `0042`-`0044` T41 base compiles after `0045`-`0048`
  but **panics at tx-isp probe** (`dma_alloc_coherent(NULL)` at
  `proc_ivdc_writel`). `0048` did not fix it. The image therefore uses the
  device-proven open `57d16f1` module, seeded manually into the target and
  per-package target before packing.
- Without a bridge the mainline `gc8613` owns i2c `0x31`, so the vendor
  `AddSensor` path returns `-EBUSY (-16)` and timps has no video.
  With `0038` enabled, AddSensor succeeds; the video-link graph is empty.

## Current camera state

- Camera: `192.168.88.121`, user `root`, password `root`.
- Serial console: `/dev/ttyUSB1`, 115200 8N1. The user is at the console.
- Image build ID: `feature/kernel-7+d013d1d, 2026-11-08 13:45:11 UTC`.
- Autoload module: `/lib/modules/7.3.3/ingenic/tx-isp-t41.ko`, md5
  `19604b9f...` (proven `57d16f1`, `build: unknown`).
- `libimp.so`: md5 `6d44f83a...` (OpenIMP, stripped).
- `timpsd`: md5 `bd2a7584...` (OpenIMP, `USE_OPENIMP=1`).
- Current boot: tx-isp loads, `/dev/video0-2` register. timps retries
  `AddSensor` every 20/40/60 s with `-16` because the bridge is not in the
  image.
- MAC: U-Boot eFUSE `ethaddr=02:22:3f:01:c5:49`; `wlan0` is `...:4a`.
  Locally administered by design; stable.

## Build / image / flash

Output directory:

```
/home/paul/output/feature/kernel-7/noorio_t120_t41nq_gc8613_aic8800d-7.3.3-uclibc-192.168.88.114
```

Image:

```
.../images/thingino-noorio_t120_t41nq_gc8613_aic8800d.bin   (32 MiB)
```

Build / repack:

```sh
CAMERA=noorio_t120_t41nq_gc8613_aic8800d IP=192.168.88.114 make
CAMERA=noorio_t120_t41nq_gc8613_aic8800d IP=192.168.88.114 make pack
```

Flash full image to the camera (camera is `.121`; the output dir name `.114`
is only the build `IP=` value):

```sh
CAMERA=noorio_t120_t41nq_gc8613_aic8800d \
sshpass -p root scripts/fw_ota.sh \
  -a 192.168.88.121 \
  -p .../images/thingino-noorio_t120_t41nq_gc8613_aic8800d.bin \
  -m all
```

File-only deployment (preferred; the overlay is jffs2 with ~21 MB free):

```sh
sshpass -p root scp -O <file> root@192.168.88.121:/tmp/
sshpass -p root ssh root@192.168.88.121 \
  'cp /tmp/<file> <target-path>; sync'
```

Kernel module reload:

```sh
/etc/init.d/S95timps stop
rmmod tx_isp_t41
insmod /tmp/<module>.ko
/etc/init.d/S95timps start
```

Do not reflash for file-only changes. The camera has a serial console if a
module wedges; the image's proven module autoloads on reboot.

## Open-tx-isp pins and the new-base panic

- Tree pin: `Lu-Fi/open-tx-isp` `next` at
  `0138d8c1...`, with `0042`-`0044` (7.x delta) and the new `0045`-`0048`.
- `0045`: define `cpu_has_mxuv3` for the mainline kernel.
- `0046`: size the AE completion for the mainline layout (offset checks,
  not a fixed 16 bytes).
- `0047`: use `ioremap()` instead of removed `ioremap_nocache()`.
- `0048`: fall back to the IVDC platform device for the IVDC DMA buffer.
- **The `0138d8c1` base still panics at boot** in
  `proc_ivdc_writel`/`dma_alloc_attrs` with `dev == NULL` (`BadVA 0x9c`).
  The image's working module is the old `57d16f1` one. A clean rebuild will
  reintroduce the panic unless the old module is seeded again or the pin is
  reverted.

## Bridge work (the remaining sensor blocker)

Old source tree used for the working bridge experiments:

```
/tmp/kilo/otis-old/src/open-tx-isp-57d16f169e763422b66260c63c5efd65b08938e4
```

It is the cached `57d16f1` tarball plus the old package patches
(`git show c15944929:package/open-tx-isp/*.patch`; enabled 0006-0037/0041)
and the disabled `0038`-`0040` applied. The current temp tree also has manual
edits from the session:

- link descriptor name fallback (`isp-m0`/`isp-fs`) in
  `t41_setup_video_link_graph`;
- a graph-subdev name dump;
- several graph-pointer experiments (see below).

Rebuild command:

```sh
K=.../.114/build/linux-7.3.3
T=.../.114/host/bin/mipsel-thingino-linux-uclibc-
M=/tmp/kilo/otis-old/src/open-tx-isp-57d16f.../driver/t41
make -C "$K" M="$M" ARCH=mips CROSS_COMPILE="$T" \
  CONFIG_TX_ISP_T41_V4L2=y modules
```

Bridge results:

- `0038` + old `57d16f1` module + OpenIMP: sensor attaches:
  `tx-isp-v4l2: attached gc8613 ...`, `sensor_bind`, `sensor-register VIN
  returned 0`.
- Video-link records now resolve names but the resolver returns no pads:
  `video-link skip ... source=00000000 sink=00000000`.
- Graph-pointer experiments:
  - original `graph = miscdev - 12`: descriptor names fallback works, but the
    subdev array is empty and no pads resolve.
  - `graph = *(uint32_t *)(miscdev - 12)` (subdev->dev): pointer
    `0xffff0400`, oops at `graph + 0x124` (`BadVA ffff0524`).
  - `graph = miscdev` (private_data): reset; serial trace not yet captured.
  - `graph = irqdev->parent->platform_data`: `pdata = 0`; falls back to the
    subdev and still skips.
- The T41 subdev ABI (`driver/include/tx_isp/tx_isp_subdev_abi.h`) puts the
  embedded `struct device` (irqdev) at `+0x84`, ops at `+0xfc`, pad pointers
  at `+0x104`/`+0x108`. `tx_isp_create_graph_and_nodes` populates the
  **tx_isp_dev** subdev array at `ispdev + (source+14)*4 + 4` (offset `0x3c`
  for source 0).
- `MDNS profile apply failed: -22 (continuing)` is present but non-fatal.

## Next steps

1. **Reproduce `graph = file->private_data`** and capture the serial trace
   from the reset. The private data is the tx-isp device (the graph); the
   previous reset trace is the missing piece for the pad/link fault.
2. Fix the T41 video-link graph/pad registration in the bridge:
   - use the `tx_isp_dev` graph for the subdev array/resolver;
   - keep the recovered subdev's `+0x124` configured field or find its
     `tx_isp_dev` equivalent;
   - validate `tx_isp_subdev_validate_link` and the pad state/links with the
     T41 ABI offsets.
3. Address `MDNS profile apply -22` (non-fatal, but likely needed for a clean
   stream).
4. Once the bridge streams, integrate the bridge into the image (or the
   old-source pin) and validate `preview.html`/RTSP. Do not leave the bridge
   only in `/tmp`.
5. Decide whether to revert `OPEN_TX_ISP_VERSION` to `57d16f1` until the
   `0138d8c1` IVDC panic is fixed; the current image is a manual hybrid
   (new userspace, old kernel module).
6. Commit the open-only policy and pending fixes when the user asks.

## Uncommitted working tree

Modified:

```
configs/cameras/cinnado_d1_t31l_sc2336_atbm6031/..._defconfig
docs/media/ingenic-media-stack.md
docs/media/open-isp-stack.md
package/ingenic-lib/Config.in
package/ingenic-lib/ingenic-lib.mk
package/open-tx-isp/open-tx-isp.mk
package/openimp/Config.in
package/openimp/openimp.mk
package/prudynt-t/Config.in
package/thingino-isp/Config.in
package/thingino-raptor-hal/Config.in
package/timps/0001-t31-nonblocking-pollingstream.patch
package/timps/Config.in
package/timps/README.md
package/timps/timps.hash
package/wifi/files/S36wireless.in
```

Untracked: `package/open-tx-isp/0045`-`0048`.

## Risks / assumptions

- The image's kernel module was seeded manually from the old proven build; a
  clean rebuild uses the new `0138d8c1` module and panics.
- The bridge modules and the test source are in `/tmp`; they are not in the
  repo or the image.
- The camera can be bricked by a bad module; the serial console and the
  image's proven module are the recovery path.
- The current boot is the clean open image with the proven module (no
  bridge); AddSensor `-16` is expected there, not a regression.
- `OPENIMP_OVERRIDE_SRCDIR` points at `overrides/openimp-lufi` in `local.mk`.
- The camera's DHCP address can change; `.121` is current.

## Progress 2026-11-08 (cont.)

Two root causes found and one fixed; the bridge now attaches the mainline
sensor and reaches ISP core init.

1. **Empty graph was a bring-up gate, not a bad graph pointer.**
   `tx_isp_create_graph_and_nodes()` only runs at
   `tx_isp_bringup_level >= 1`; the default is 0, so `ispdev+0x3c` never got
   populated and the video-link resolver skipped every record. Load the
   module with `tx_isp_bringup_level=1` (graph) or `3` (full core/channels).
   `miscdev - 12` already recovers `ispdev` (private_data is `ispdev+0xc`),
   so `graph = file->private_data` is wrong; keep `miscdev - 12`.

2. **`subdev_sensor_ops_release_all_sensor` crashed with the bridge sensor.**
   The recovered function walks an OEM sensor object whose list is at +0x14
   and treats `node-0x14` as an i2c client. The bridge (and the typed
   register path) keeps `list_head` at `T41_SENSOR_LIST_OFF` (288) and leaves
   the +0x10c client slot NULL, so `node-0x14` dereferences NULL (`BadVA
   0x18`). Fixed in
   `/tmp/kilo/otis-old/src/open-tx-isp-57d16f169e763422b66260c63c5efd65b08938e4`
   by adding `t41_release_all_sensors()` (list at +288, release via
   `t41_unregister_i2c_sensor`) and wiring it into `vin_subdev_sensor_ops`
   and `tx_isp_vin_slake_subdev`. Rebuild with the command above.

Result at `tx_isp_bringup_level=3`:

```
tx-isp-v4l2: attached gc8613 at i2c-0/0x31 (3840x2160, 2 lanes, 553.5 MHz)
Create framechan0/1/2 OK
t41: sensor-register VIN returned 0
t41: ispcore-init state ready=2          # CPM reset now succeeds
t41: tisp-core config copied 3840x2160
t41: tisp-load opened size=254032 / payload ready
```

3. **Current blocker: hang in tisp-core init, then watchdog reset.**
   After `tisp-load payload ready` the init stalls; the hardware watchdog
   (`/usr/sbin/watchdog -T 60 /dev/watchdog`) resets the board. No panic
   message is printed (confirmed with `/proc/kmsg` captured to
   `/overlay/kmsg.log`), so it is a hang, not a fault. `t41_runtime_trace=1`
   moves the last message earlier (before `params-copy`), i.e. timing
   sensitive. The ISP gate does toggle: manually clearing CLKGR1 bit 23
   (`0x10000020`, isp gate) changes `0x133000xx` reads from 0 to a constant
   `0x20220304`; the driver reaches the same value, so clock enable works but
   the core may still be held in reset or need the divider/PLL setup.

Next test: load `tx_isp_bringup_level=3 t41_runtime_trace=1` with the
hardware watchdog stopped (`/etc/init.d/K99watchdog stop`, then
`killall watchdog`), and capture `/proc/kmsg` to `/overlay/kmsg.log`. If the
CPU still responds, read the last `tisp-init enter <fn>` to name the hanging
stage; if it hard-hangs, the watchdog is the only recovery, so keep the
serial console at hand. Also compare the ISP core reset path
(`private_reset_tx_isp_module`, CPM `0xb00000c4` bits 21/20) against the
mainline `0x13300000` register behaviour — `0x20220304` on every core
register after gate-on suggests the block is not fully out of reset/clocked.

Camera state after this session: rebooted, proven `19604b9f...` module
autoloaded, timps retrying AddSensor `-16` as expected. `/overlay/kmsg.log`
and `/tmp/tx-isp-t41-bridge.ko` remain but are harmless.

## Hang localization (same day, after adding debug)

Instrumentation added to the `/tmp` bridge source (module params, default off):

- `t41_dbg=1`: `T41DBG` KERN_EMERG checkpoints (with `mdelay(4)` so the
  115200 UART cannot swallow the last mark before a reset), a heartbeat
  kthread printing `stage=`/`seq=` every second, and clk/reset diagnostics.
- Checkpoints cover `tisp_init`, the firmware load, `sensor_init`, every
  `T41_INIT2` stage, the stock profile applies, `tisp_msca_init`,
  `tisp_msca_ir_init`, `tisp_event_init`, and `ispcore` open/activate.

Results (module loaded with `tx_isp_bringup_level=3 t41_dbg=1`):

- Sensor attaches, `sensor-register VIN returned 0`, graph works.
- `tisp_init` runs through every `T41_INIT2` stage and all stock profile
  applies with `ret=0`.
- Clocks: `ispcore_activate` state=1, 4 clocks, `clk_prepare_enable` ret=0;
  rates 276/276/368/552 MHz (set_rate targets 285/550/600 return 0 but the
  rate does not change; mainline PLL/divider limits).
- **The hard hang is `system_reg_write(0x0f0084, (w<<16)|h)` inside
  `tisp_msca_init`.** The mark before it prints; the mark after never does
  and the heartbeat stops (IRQs off / bus stall), watchdog reset ~60 s.
  The preceding `system_reg_write(0x0f0080, 0)` completes.
- ISP core registers (0x40/0x48/0x60/0x6c/0x80/0x88) read a constant
  `0x20220304` even with the ISP gate on, i.e. the block does not respond
  like the OEM map; the stall is a bus wait, not a fault.
- The T41 core resource was `0x13300000-0x1330ffff` (64 KiB), but the DT
  `isp@0x13300000` and the recovered offsets (MSCA 0xf0084, AWB 0x1803c)
  need 1 MiB like T31 (`0x13300000-0x133fffff`). The window was enlarged,
  rebuilt and retested: the `0x0f0084` write still stalls, so the mapping
  size is necessary but not sufficient.

Current state: the instrumented module is in `/tmp` only; the camera is back
on the proven module. Next: determine why the ISP/MSCA block does not
acknowledge register accesses (reset/clock-domain/parent-mux). Compare the
CPM SRBC bits and the ISP clock parent muxes against a known-running OEM boot;
the current mainline `isps`/`ispa` rates (368/552 MHz) miss the OEM
550/600 MHz targets.

## Stock dump resolution (same day)

The stock flash dump is at
`~/extractions/noorio_t120-t41nq-unk-aic8800d-virgin.bin.extracted/`; the
vendor rootfs carries an **unstripped**
`3C0000/squashfs-root/system/lib/modules/tx-isp-t41.ko` (vermagic 4.4.94).
Disassembling it resolved the hang definitively:

1. **The OEM `tisp_msca_init()` never writes `0xf0080`/`0xf0084`.** It calls
   `tisp_irsca_para_calc(channel)` then `tisp_irsca_write_reg(channel)`.
   `tisp_irsca_write_reg` writes `0x1f00c`, `0x1f010`, `0x1f014`, `0x1f018`,
   `0x1f008` (IRSCA block), then `tisp_msca_init` writes `0x033c`. The typed
   REGTRACE reconstruction substituted `0x0f0080`/`0x0f0084`; `0x0f0084` is
   not in the ISP block and stalls the AHB bus (no oops, watchdog reset).
   Fixed by replaying the OEM IRSCA sequence in the typed path.
2. **The stock core resource is 64 KiB** (`0x13300000-0x1330ffff`), not
   1 MiB. On MIPS `ioremap()` returns a KSEG1 alias, so offsets past
   `0xffff` (IRSCA `0x1f018`, AWB `0x1803c`) remain reachable. Enlarging the
   reservation to 1 MiB made the VIC's `0x13380000` `request_mem_region`
   fail (`-EBUSY`, graph slot 1 missing). Reverted to the 64 KiB OEM size.
3. Clocks are fine: `ispcore_activate` state=1, four clocks enabled
   (`ret=0`); rates 276/276/368/552 MHz (mainline PLL limits).

With both fixes the whole pipeline now passes:

```
msca:irsca-done / msca:done
tisp:done / ispcore_init:tisp-return value=0
process-done / streamon-done
tisp-stream-on safe channel=0 3840x2160 ret=0
get mdns-buf paddr=0x0 size=0xe38000      (by design; libimp reserves rmem)
set mdns-buf paddr=0x69c8000 ... program-return 0
mdns_profile: refresh/func-en/start/trig/bypass all return 0
```

**Next hang: after `bufinfo:apply-profile-return`, when live capture starts.**
The host becomes unreachable with no oops/panic (hard freeze), so it is in the
first frame / ISP ISR / VIC path, not the init or MDNS programming. The MDNS
GET returns `paddr=0` intentionally (the driver reports the required size;
libimp reserves the rmem slice and calls SET with `0x69c8000`). Next step:
instrument `ispcore_interrupt_service_routine` and the VIC frame-done path, or
exercise the open userspace in QEMU (unmodelled ISP will not hang) to confirm
the ioctl flow before chasing the live-ISR stall.

## Continue 2026-11-08 (evening): live-capture start now works

### timps updated to v1.12.1

- Pulled `package/timps` from `origin/master` (v1.12.1, rotation always built,
  `BR2_PACKAGE_TIMPS_ROTATE` gone). The local `0001`-`0003` T31 patches were
  dropped: master no longer carries them (upstreamed) and Buildroot would
  otherwise re-apply them to v1.12.1.
- Re-applied the open-only hunk to the new `Config.in`: removed the
  `select BR2_PACKAGE_INGENIC_LIB_LIBIMP` / `INGENIC_LIB_LIBSYSUTILS` selects
  (the vendor symbols no longer exist) and made the `INGENIC_SYSTEM_LIBS_NEO*`
  selects unconditional.
- `USE_OPENIMP=$(if $(BR2_PACKAGE_OPENIMP),1,0)` is still in timps.mk, so the
  rebuilt `timpsd` links against OpenIMP (verified: `OpenIMP_Cap_*` strings,
  `NEEDED libimp.so`). Rebuilt with
  `CAMERA=noorio_t120_t41nq_gc8613_aic8800d IP=192.168.88.114 make rebuild-timps`
  and deployed to `/usr/bin/timpsd` (md5 `c39d38eda08902ffbf8227d337d14046`).

### Live-capture hard freeze root-caused and removed

The hard freeze was **not** the ISR or VIC start. It was a diagnostic
`system_reg_read()` of the MSCA bank:

- `ispcore_video_s_stream` reaches the post-loop ISP start:
  `system_reg_write(0x80, ...)` then `isp_interrupts_enable()` (the
  `0x40020/0x40060/0x400a0/0x400b0` writes all acknowledge) then
  `tisp_ipc_triger()` (`0x1004`/`0x1000` write, both ret 0).
- After the trigger, the diagnostics read `0x0f0008` to report MSCA state.
  That read stalls the AHB bus (no oops, heartbeat stops, watchdog reset) even
  though the stock module uses the same `system_reg_read` base and does access
  `0xf0008` later in `tisp_msca_chx_cfg_load`. The MSCA bank does not
  acknowledge host reads in this bring-up phase.
- Removing all pre/post-IPC `0x0f0008` / `0x0f0030` / `0x0f00e0` diagnostic
  reads lets the whole sequence complete:
  `ispcore:isp-start-done` -> `vstream:ret 0` -> slot walk ->
  `video_link_setup` (`0x80085409`) -> `video_link_stream`
  (`0xc008540b`, all subdevs have no `video_ops->stream`).

Lesson: on this console only `KERN_EMERG` survives (all `KERN_WARNING` /
`KERN_ERR` from the driver are filtered). Every checkpoint must be
`KERN_EMERG` + `mdelay()` to drain the 115200 UART.

### Next blocker: frame-channel release frees an uninitialized private queue

After `video_link_stream` returns, `tx_isp_t41_frame_channel_release()`
(`tx_isp_t41_v4l2.c` acquire-fail / `release_channel` path) calls the
module-local recovered `__vb2_queue_free(channel + 0x2c, count)`:

- `count = *(u32 *)(channel + 0x218)` is a stray kernel pointer, not a count
  (`-2134801600`, `140000000`); `bufs[0] = *(u32 *)(channel + 0x118)` is
  garbage. `__vb2_queue_free` then walks a huge range and panics
  (unaligned access `lw a0,60(s5)`, `BadVA 0x3d`, "Not a kmalloc allocation"
  page dumps).
- `t41_frame_channel_reqbufs_clean()` was **never entered** (no
  `reqbufs:enter` mark), so the private queue at `channel + 0x2c` was never
  populated. `video->owned_channel` is set by the v4l2 acquire path. The
  release must not free a queue that reqbufs never built.
- A guard was added to `__vb2_queue_free` (clamp `count > 64` to 0, skip
  non-kernel buffer pointers) so the release no longer panics on the garbage
  count. That made both releases in the run complete
  (`fcrel:free-done`), but a later panic remains in kernel context in
  process `dn` (`EPC 0x80601508`, `BadVA 0x28`, `ExcCode 02` TLB), with no
  module frame in the trace. That is a separate fault, likely in the
  V4L2/vb2 teardown or the day/night thread, not the ISP start.
- The release call is **not** from `acquire_channel`'s `fail:` label in the
  observed run (the `v4l2:acquire-fail` mark did not print); it comes from
  `tx_isp_t41_v4l2_release_channel` (REQBUFS(0) or file release).

### Next concrete steps

1. Determine why `t41_frame_channel_reqbufs_clean` is not reached and why
   `owned_channel` is non-NULL without it. Add `T41_VD` marks to
   `tx_isp_t41_v4l2_request_buffers` / `release_channel` / `set_fmt` and to
   `t41_frame_channel_qbuf_clean` (the `qbuf:enter` mark never fired either),
   then re-run.
2. Fix the private-queue lifecycle: initialize `channel+0x2c` (count/list
   heads) when the channel is claimed, and only call `__vb2_queue_free` when
   reqbufs populated it. Do not rely on the count-garbage guard as the fix.
3. Chase the `dn` kernel panic once teardown is clean (`EPC 0x80601508` maps
   outside the module; use `System.map` from the built kernel).
4. Only then look at the frame path: `tx_isp_t41_vic_start` (deferred until
   frame-channel streamon) still has not run. `t41_defer_vic_start` /
   `t41_defer_vic_irq` are 1 by default, so VIC start is expected to happen
   from the qbuf late-link replay.

### Instrumented source state

- Tree: `/tmp/kilo/otis-old/src/open-tx-isp-57d16f169e763422b66260c63c5efd65b08938e4`
  (not in the repo). Built module: `driver/t41/tx-isp-t41.ko` (vicdbg14).
- Latest deployed test module: `/tmp/kilo/tx-isp-t41-vicdbg14.ko` on the
  camera as `/tmp/tx-isp-t41-vicdbg14.ko`.
- Camera after this session: rebooted, proven `19604b9f...` module
  autoloaded, timps v1.12.1 (`c39d38ed...`) retrying AddSensor `-16` as
  expected. Image is unchanged (kernel module still not in the image).
- Serial console: the T120 is on `/dev/ttyUSB0`, logged to
  `/home/paul/screen-sessions/screenlog-1793954143-3638111.txt`.
  `/dev/ttyUSB1` is a different (Wyze) camera.

## Freshness check of openimp / open-tx-isp (2026-11-08 late)

Compared the pinned sources with `origin/master` by ancestry, not just by version
string:

- `open-tx-isp`: master pins `v2026.11.07-rc3.1` = `46e7acb5`. Our tree pins
  `Lu-Fi next` `0138d8c1`. Merge-base is `728ee0d8`; our pin is **29 commits
  ahead**, rc3.1 has exactly 1 commit we lack (`46e7acb5` "T31: export
  tx_isp_sinfo_sensor_bind/unbind for older sensor modules", T31-vendor only).
  `next` head is now `d221132f`.
- `openimp`: master pins `v2026.11.07-rc3` = `b1d17615`; our pin `ba36fccd`
  has `b1d17615` as an ancestor and is **13 commits ahead**.

So both packages are newer than master. Do **not** replace them with master's
files: that would be a downgrade, and master's `open-tx-isp.mk` / `Config.in`
predate the branch's 7.x wiring (`KERNEL_VERSION_7` support, unconditional
`CONFIG_TX_ISP_T41_V4L2=y`, no `BR2_PACKAGE_OPENIMP_USE_V4L2` gate). The only
missing master commit is T31-only.

## Frame-channel teardown findings (run 13/14)

- `tx_isp_frame_chan_init` (recovered.c ~29911) does `memset(chan_base,0,count*820)`
  and per channel `memset(q+44, 0, 552)` then inits `frame_chan_mlock`
  (`q+0x30`) and `frame_chan_vb2_mlock` (`q+0x2e4`). So a freshly built channel
  has `count = *(u32*)(channel+0x218) = 0` and `bufs = 0`.
- Run 14 (guard in `__vb2_queue_free`): first release `count=0` (correct),
  second release ~0.75 s later `count=140000000` (0x08588b40, a DMA-like
  value) — something writes the private-queue count slot after the first
  release. The guard clamps it and the frees complete, but a new oops follows.
- Remaining oops: process `dn` (timps day/night), `mutex_lock` with a NULL
  mutex (`EPC 0x80601508` = `mutex_lock`, `BadVA 0x28`, `ExcCode 02`). This is
  the separate tuning ioctl path (`aisp_core_tunning_unlocked_ioctl`), not
  `tx_isp_unlocked_ioctl` (no `txisp:ioctl` mark before it). It locks a mutex
  whose object was never initialized on this path.
- `t41_frame_channel_reqbufs_clean` still never runs (`reqbufs:enter` absent),
  and the v4l2 `acquire_channel` marks (`v4l2:acquired`, `setfmt-ret`,
  `acquire-fail`) never print. The two releases come from file-close /
  `tx_isp_frame_chan_deinit` paths, not from `acquire_channel`'s `fail:`.

## Continue 2026-11-08 (late): frame-channel/proc ABI fixes unblock capture setup

Root causes found for the previous "uninitialized queue" and `dn` panic findings.
All three are kernel-ABI mismatches in the recovered T41 code, and all three are
fixed in the `/tmp` bridge tree only:

1. **`fs_channel_ops` used 4.4-era `file_operations` offsets.** The raw array
   was written at `0x20` (`unlocked_ioctl`), `0x2c` (`open`), `0x34`
   (`release`). This kernel has `fop_flags` in `struct file_operations`, so the
   real offsets are `0x28`, `0x34`, `0x3c`. Every `/dev/framechanN` open was
   dispatched to `frame_channel_release` and `.release` was NULL: the real
   `frame_channel_open`/claim never ran, the private queue was never
   initialized, and "release frees an uninitialized queue" was an
   open-to-release misdispatch. Fix: under `REGTRACE_KERNEL_TREE_BUILD` use a
   real `static struct file_operations fs_channel_ops` and assign the named
   fields (`owner`, `unlocked_ioctl`, `open`, `release`).

2. **`proc_create_data()` takes `struct proc_ops` since 5.6, not
   `file_operations`.** Passing the recovered `file_operations` made
   `/proc/jz/isp/isp-m0`'s `proc_read` resolve to `seq_lseek` and
   `proc_read_iter` to `seq_read`. A `dn` `fopen()`+read then reached
   `seq_read_iter` with a bogus seq_file (`mutex_lock(NULL)`, `BadVA 0x28`).
   Fix: `private_proc_create_data()` transcodes `file_operations` to a
   `kzalloc`'d `proc_ops` (open/read/read_iter/write/lseek/release/poll/
   ioctl/mmap), stores it in a small table, and `private_proc_remove()` frees
   it. `/proc/jz/isp/isp-m0` now returns the real ISP status.

3. **Claim freed an empty private queue.** `tx_isp_t41_frame_channel_claim()`
   called `__vb2_queue_free()` on a fresh channel (`count == 0`). That sends
   IVDC event `0x3000008`, which reprograms the IVDC for a NULL buffer and
   stalls the AHB bus (hard hang, no oops, watchdog reset). Fix: only call
   `__vb2_queue_free()` when `channel + 0x218` (the queue count) is non-zero.

With these three fixes and `tx_isp_bringup_level=3 t41_dbg=1` (module loaded
before timpsd), the pipeline now:

- attaches gc8613 through the bridge (`sensor-register VIN returned 0`),
- completes ispcore init, MDNS profile apply, and the video-link graph
  (`isp-m0`/`isp-ivdc`/`isp-fs` all connected),
- no longer hangs at `vlink` or at claim, and no `dn` panic,
- `/proc/jz/isp/isp-m0` succeeds (day/night reads work),
- runs `frame_channel_open` -> claim -> REQBUFS.

### Remaining blocker: corrupted frame-channel queue fields

REQBUFS now reaches `t41_frame_channel_reqbufs_clean` but returns `-EINVAL`
(`OpenIMP`: `ioctl fd=7 cmd=0xc0145453 failed: 22`). Marks show:

```
fopen:ch=0  claim:state=2  claim:count=0
reqbufs:ch=0  reqbufs:chan-mem=0x80b9....  reqbufs:user-mem=2
```

`channel + 0x48` (the cached V4L2 memory type, should be `2` = USERPTR,
written at init as `*(u32*)(q+72)=2`) reads kernel-pointer garbage, so the
OEM memory check fails. A repair (adopt the request's memory type when the
cached value is not a valid enum) let the run continue, but timpsd then died
with an unaligned access reading `0x230(ptr)` from a corrupted pointer
(`EPC 0xc0306c3c`, `BadVA 0xc1c14336`, `Comm timpsd`). Something still writes
non-enum/kernel-pointer values into the frame-channel queue (`+0x48`, and a
spinlock/mutex pointer used at `+0x230`). The recovered T41 frame-channel
struct offsets need reconciliation against the stock module (the stock
`frame_channel_unlocked_ioctl` at `0xdc30` compares `lw v1,72(s0)` with the
request memory word; the stock init writes `q+72=2`).

### Test procedure that works (important)

`rmmod` of a live tx_isp module is unreliable (module refcount, workqueue
disable overflow, `clks:disable` hang). To test a bridge module:

1. Comment out `tx_isp_t41` in `/etc/modules.d/20-isp` (overlay) and reboot.
2. Confirm `lsmod` has no `tx_isp`.
3. `insmod /tmp/tx-isp-t41-vicdbgN.ko tx_isp_bringup_level=3 t41_dbg=1`.
4. `/etc/init.d/S95timps restart`.
5. Restore the `20-isp` line afterwards.

Capture via `ssh 'cat /proc/kmsg' > file` (all levels, incl. `t41_note`), and
the serial screen log (`/home/paul/screen-sessions/screenlog-1793954143-3638111.txt`,
`/dev/ttyUSB0`). `t41_dbg` mark drain delay was raised to `mdelay(8)`; kmsg
still drops some marks, serial is authoritative for the last mark.

### Source / artifacts

- Tree: `/tmp/kilo/otis-old/src/open-tx-isp-57d16f169e763422b66260c63c5efd65b08938e4`
  (not in the repo).
- Modules: `/tmp/kilo/tx-isp-t41-vicdbg{15..25}.ko`; the ABI fixes are in
  `vicdbg15`+ (fops, proc_ops) and `vicdbg23`+ (claim skip).
- Camera restored: `/etc/modules.d/20-isp` re-enabled, rebooted, proven
  `19604b9f...` module autoloaded, timpsd retrying AddSensor `-16` as expected.

### Next steps

1. Reconcile the frame-channel queue field offsets with the stock module:
   disassemble the stock `frame_channel_unlocked_ioctl` (`0xdc30`) and the
   framesource init, and find what writes `channel+0x48`/`+0x230` after init
   (sound suspect: the recovered `frame_chan_event`/ISP set-format path writing
   with 4.4 offsets). Compare every field the recovered claim/reqbufs/qbuf code
   touches against the stock instructions.
2. Only then restore the memory-type check in `reqbufs_clean` (remove the
   repair) and continue to QBUF/STREAMON, VIC start, and the frame path.
3. Port the three ABI fixes (fops, proc_ops, claim skip) into the repo
   `package/open-tx-isp` patches; they are independent of the offset work.
4. Revisit the `0138d8c1` IVDC panic and decide the final pin.

## Continue 2026-11-08 (night): `file->private_data` offset fixed

### Root cause of the "corrupted queue fields" and the tuning crash

The recovered T41 code was reconstructed from the OEM **4.4.94** module, where
`struct file::private_data` is at `+136`. On the mainline **7.3.3** kernel it is
at **+12**, and `sizeof(struct file)` is only **120**. Every recovered raw
`*(u32 *)(file + 136)` read therefore lands *past the end of the object* in the
`filp` slab and returns an unrelated pointer. This is not a queue-field
corruption in the frame-channel struct: the frame-channel ioctl handler was
operating on a bogus channel pointer.

It explains:

- `channel + 0x48` / `channel + 0x230` reading kernel-pointer garbage at
  REQBUFS (the "channel" was a slab neighbour);
- the timpsd unaligned access at `EPC 0xc0306c3c`: that is
  `t41_tuning_core_state()`, `lw v0,0x230(a0)` with `a0` = `*(file+136)+256`;
- why `frame_channel_open` worked: it uses the compiled
  `file->private_data` accessor (offset 12), while the ioctl/release/tuning
  handlers used the stale raw 136.

### Measured 7.3.3 MIPS layout

Probe module: `/tmp/kilo/offprobe/` (built against the `.114` kernel tree with
the real headers; run or disassemble it, do not guess these).

```
struct file:  f_mode=0 f_op=4 f_mapping=8 private_data=12 f_inode=16
              f_flags=20 f_iocb_flags=24 f_cred=28 f_owner=32 f_path=36
              f_pos_lock=48 f_pos=56 f_wb_err=64   sizeof=120
file_operations: unlocked_ioctl=0x28 open=0x34 release=0x3c
miscdevice: sizeof=0x28 (list=0xc this_device=0x18)
```

### Fixes applied in the `/tmp` bridge tree (vicdbg26)

- `t41_tuning_core_state()` and `isp_core_tunning_open()`: read
  `((struct file *)file)->private_data`.
- `frame_channel_unlocked_ioctl()`: `s0 = ((struct file *)a0)->private_data`.
- `frame_channel_release()`: both `a1+136` reads use `private_data`.
- `tx_isp_unlocked_ioctl()`: `s2 = ((struct file *)a0)->private_data`.
- `tx_isp_fs_probe()`: queue buffer size `136` -> `132` (stock writes 132 at
  `d974`).
- REQBUFS: removed the memory-type "repair"; the stock equality check is
  restored (it now passes naturally).

Module: `/tmp/kilo/tx-isp-t41-vicdbg26.ko`
(md5 `c89ca64ff2bf2c93c073d8a27967b1dc`).

### Test results

- Module load at `tx_isp_bringup_level=3 t41_dbg=1` with timps stopped: stable
  (heartbeat alive).
- Starting timps: full T41 init, MDNS program, `ispcore:s_stream`, CSI/VIC and
  the video-link graph all complete; **no tuning crash and no frame-channel
  corruption**. The board then **hard-hangs immediately after `enable:done`**
  (the `0xc008540b` video-link-stream ioctl returns 0). The debug heartbeat
  stops, no oops/panic, watchdog resets ~60 s later.
- The hang is unchanged with `t41_defer_vic_start=0` and with
  `t41_defer_isp_start=1` (sensor/ISP start deferred), so it is not the deferred
  producer work. No `fchan:ioctl` mark is printed after `enable:done`, so it is
  also not the frame-channel ioctl path.
- Camera restored: `/etc/modules.d/20-isp` re-enabled, proven `19604b9f...`
  module autoloaded, timpsd retrying AddSensor `-16` as expected.

### Next concrete steps

1. Localize the post-`enable:done` hang. It is after `tx_isp_unlocked_ioctl`
   returns the `0xc008540b` result and before the next frame-channel ioctl.
   Add a `KERN_EMERG` mark immediately before the `return regtrace_ret;` of
   each command in `tx_isp_unlocked_ioctl` and check (with the interactive
   serial console) whether the last mark is the ioctl exit or whether the hang
   is already in the deferred/async tail of `tx_isp_video_s_stream`.
2. If the ioctl return completes, the hang is in the first post-enable userspace
   syscall or in an async tail; instrument `tx_isp_t41_vic_start`, the CSI/sensor
   `s_stream` tail, and the ISP ISR frame-done path with EMERG marks.
3. Port the `file->private_data` fix together with the fops/proc_ops/claim fixes
   into `package/open-tx-isp` patches. This is independent of the offset/bridge
   work and removes a whole class of 4.4-vs-7.x ABI bugs.
4. Revisit the `0138d8c1` IVDC panic and decide the final pin; the `/tmp` bridge
   is still the `57d16f1` tree.

Artifacts: `/tmp/kilo/kmsg-run{26..30}.log`,
`/tmp/kilo/tx-isp-t41-vicdbg26.ko`, `/tmp/kilo/offprobe/`, serial log
`/home/paul/screen-sessions/screenlog-1793954143-3638111.txt` (`/dev/ttyUSB0`).

## Continue 2026-11-08 (night, second pass): post-enable stall localised

The post-`enable:done` freeze is **not** the ISP IRQ, the ISP IPC trigger, or
the VIC start. Isolation runs with new module params proved it, and the freeze
was moved from a bus stall to two concrete bugs and then to the STREAM_ON
event chain.

### What was ruled out

- `irq:top` in `isp_irq_handle` and `irq:thread` in
  `isp_irq_thread_handle`: never printed after `enable:done`.
- `t41_skip_irq_mask=1` (skip `isp_interrupts_enable()`), still with the IPC
  trigger: board still froze at `enable:done`.
- `t41_skip_irq_mask=1 t41_skip_ipc=1` (also skip `tisp_ipc_triger()`): board
  **still froze at `enable:done`**. The ISP IRQ mask, the IPC trigger, and the
  firmware are not the cause.

### Root cause 1: the first control after ENABLE_SENSOR reads MSCA

After `enable:done` the next userspace call is `IMP_ISP_EnableTuning()`
(`timps` `hal_ingenic.c:2628`), then the tuning controls on `/dev/isp-m0`.
Marks `tm0:open`, `tm0:ioctl`, `tm0:body`, `tm0:id` showed the block reaching
control `0x08000073` (HVFLIP), then stalling in `t41_tuning_hvflip()` ->
`tisp_s_hv_flip()` -> `tisp_msca_set_mirr_flip()`, whose first statement is
`system_reg_read(0x0f002c)`. Host reads of the T41 MSCA bank stall the AHB bus
on this bring-up (same class as the earlier `0xf0008` diagnostic read).

Fix (isolation param, default off): `t41_msca_noread=1` seeds the
`0x0f002c` read-modify-write from the software shadow
(`t41_msca_algo_staged`) instead of reading hardware. With it the whole Raptor
tuning startup completes (`hvflip:msca-done`, `hvflip:lsc-done`,
`hvflip:sensor-done`, then more controls, `fopen`/`claim`/`REQBUFS`/`QBUF`).

### Root cause 2: NULL device in `dma_sync_single_for_device()`

`t41_frame_channel_qbuf_clean()` called
`private_dma_sync_single_for_device(NULL, ...)`. On 7.3.3 the DMA sync path
dereferences `dev->dma_ops` at `dev+0xf0`; the 4.4 vendor kernel tolerated
NULL. The first QBUF oopsed (`lw v0,0xf0(a0)`, `BadVA 0xf0`, `epc` in the
dma-sync thunk). Fixed by passing
`&tx_isp_core_platform_device.dev`. QBUF now completes
(`qbuf:dmasync` then the next ioctl).

### Current blocker: STREAM_ON event chain

With both fixes, the sequence reaches `streamon:enter` ->
`remote:resolve-begin 0x03000005` -> `remote:resolved` and freezes inside the
STREAM_ON event handler (before or at the `remote:handle` mark; the exact
point is timing sensitive). This is the framesource/core pad event handler
chain that performs the deferred producer start (IVDC IRQ enable, then VIC/
CSI/sensor). `ivdcirq:*` and `ivdcev:*` marks were added but did not print in
the run that stalled before `remote:handle`, so the handler is not yet
identified; `ispcore_pad_event_handle()` forwards `STREAM_ON` to the per
channel `ops[4]` callback and is the prime suspect.

### Instrumentation added to the `/tmp` tree (all gated on `t41_dbg`)

- `irq:top`, `irq:thread`, `fchan:any`, `v4l2:start-streaming`
- `tm0:open`, `tm0:ioctl`, `tm0:body`, `tm0:id`, `tm0:id-get`, `tm0:id-ch`
- `hvflip:*`, `msca:flip-value`, `msca:flip-write`, `msca:flip-upd`
- `qbuf:copied`, `qbuf:dmasync`
- `ivdcev:enter`, `ivdcev:streamon`, `ivdcev:streamon-irq-done`
- `ivdcirq:*`

New params: `t41_skip_irq_mask`, `t41_skip_ipc`, `t41_msca_noread`.

### Artifacts / test recipe

- Modules: `/tmp/kilo/tx-isp-t41-vicdbg{27..35}.ko`; the two fixes are in
  `vicdbg33`+ (`dma` dev) and `vicdbg32`+ (`t41_msca_noread`).
- Working run command (after booting with `/etc/modules.d/20-isp` commented):

```sh
killall timpsd
insmod /tmp/tx-isp-t41-vicdbg35.ko tx_isp_bringup_level=3 \
       t41_dbg=1 t41_msca_noread=1
/etc/init.d/S95timps restart
```

- Serial log: `/home/paul/screen-sessions/screenlog-1793954143-3638111.txt`
  (`/dev/ttyUSB0`). `t41_dbg` marks are KERN_EMERG + `mdelay(8)` and are the
  only reliable console output; KERN_WARNING is filtered.
- Camera restored after the session: `/etc/modules.d/20-isp` re-enabled,
  rebooted, proven `19604b9f...` module autoloads, timpsd retries AddSensor
  `-16` as expected.

### Next

1. Identify the `remote:handle` target for `0x03000005` (framesource/core
   pad event). Add a `KERN_EMERG` mark at the top of `ispcore_pad_event_handle`
   and around its `ops[4]` callback, and at the core channel STREAM_ON
   callback; re-run. The marks in `ivdc_pad_event_handle` did not fire, so do
   not assume that handler.
2. Expect the same class of 4.4-vs-7.x bugs in the producer start (NULL
   device, MSCA reads, stale struct offsets). Check every `dma_sync_*` call
   with a NULL device (two more sites remain at the old line numbers 11415 and
   31977) and every `system_reg_read(0x0f00xx)` in the STREAM_ON path.
3. Once STREAMON completes, watch `tx_isp_t41_vic_start`, CSI/sensor start,
   and the ISP frame-done ISR; the `t41_msca_noread` workaround must be made
   the default or replaced by a proper MSCA bring-up.
4. Port the proven 7.x ABI fixes (fops offsets, `proc_ops`, claim skip,
   `file->private_data`) plus these two fixes into the repo
   `package/open-tx-isp` patches.

## Continue 2026-11-09: QBUF MSCA write localised (module text mapped)

Environment restored before the session: camera `.121` up, proven
`19604b9f...` module autoloaded, `/etc/modules.d/20-isp` re-enabled after
tests.

### Event value correction

The frozen event is `0x03000005` = **`TX_ISP_FRAME_EVENT_QUEUE_BUFFER`**, not
STREAM_ON. The call chain is
`t41_frame_channel_streamon_clean()` -> `__enqueue_in_driver()` ->
`tx_isp_send_event_to_remote(QUEUE_BUFFER)` ->
`ispcore_pad_event_handle()` -> channel `ops[4]` =
`ispcore_frame_channel_qbuf()`.

Handler and callback pointers from the marks were mapped to symbols using the
module base from `/proc/modules` (e.g. base `0xc02b3000`) plus `nm` offsets:
`remote:handle` = `ispcore_pad_event_handle`, `cpad:callback` =
`ispcore_frame_channel_qbuf`. Do this instead of guessing from the pointer
value; module load addresses move every boot.

### Root cause: first MSCA FIFO register write stalls

`ispcore_frame_channel_qbuf()` takes the channel spinlock (value 0, free),
resolves the NV12 layout, then calls
`tisp_msca_addr_fifo_write(channel_index, y_dma, uv_dma)` for the non-direct
case. The hang is the **first `system_reg_write(0x0f016c, y_dma)`** inside it;
the `cchq:fifo` mark prints and `cchq:fifo-done` never does. The IRSCA block
(`0x1f00c..0x1f018`) accepts writes, but the MSCA sub-block at `0x0f0000` does
not acknowledge host MMIO on this bring-up. Same class as the earlier
`0x0f0084` / `0x0f002c` / `0x0f0008` stalls: a gated block stalls the bus
(no oops, watchdog reset), it is not a software bug.

Marks after `raw_spin_lock_irqsave()` are buffered but not flushed while IRQs
are off, so an IRQ-off critical-section hang and a bus stall look identical
from the console. For future runs a debug parameter `qbuf_nolock=1` was added
to `ispcore_frame_channel_qbuf()`; with it, the marks inside the critical
section reach the console and the stall localises exactly.

Also removed the unconditional `system_reg_read(0x0f0008)` in
`tisp_msca_addr_fifo_write()` (it now runs only when
`t41_msca_fifo_ctrl_after_live_qbuf <= 0`). That read was an independent
bus-stall source; it is not the current blocker.

### direct_mode=1 is not the fix

Load `direct_mode=1` bypasses the FIFO write (the direct branch only stores
`y_dma | 0x01000000` in the payload), but it also re-routes the graph to the
IVDC pad handler. That path is not ported: event `0x03000007`
(`ivdc_pad_event_handle` `case 0x3000007`) oopses with an unaligned access
because `ivdc_mem_paddr` is still 0 at REQBUFS and the recovered
`dma_alloc_from_coherent()` tail dereferences
`*(s6_1 + 0x124) = 0xffffffff`. So the normal `direct_mode=0` path (MSCA FIFO)
must be made to work; direct mode is a separate, larger port.

### Clocks (unchanged, still suspect)

`ispcore_clks_ops` enables 4 clocks: `gate_isp` (parent `ispm`), `div_ispm`,
`div_isps`, `div_ispa`; all `clk_prepare_enable` return 0. Rates read
276/276/368/552 MHz; `clk_set_rate` for the targets (285/550/600) returns 0
but the rate does not change, so the mainline T41 CGU parent mux/divider is
already at its limit. `gate_isp` parent is `ispm`, so the ISP core bus (IRSCA
at `0x1f000`) works; the MSCA bank at `0x0f0000` may be clocked by
`isps`/`ispa` (or need a separate sub-block enable) and is the thing to
re-audit next. A gated AXI/scaler clock stalls the bus exactly like this.

### Next concrete steps

1. Determine the enable/reset for the MSCA sub-block at `0x133f0000`
   (compare the vendor CGU register state after boot, especially
   `ISPS`/`ISPA` mux+div and any ISP-internal enable, against the mainline
   `isps=368` / `ispa=552`). Fix the T41 CGU (or the clock parent selection)
   so `isps`/`ispa` reach the vendor 550/600 MHz targets if that is required.
2. If the block responds, continue QUEUE_BUFFER -> VIC start -> frame ISR and
   then re-evaluate the `t41_msca_noread` workaround.
3. Port the proven 7.x ABI fixes (fops offsets, `proc_ops`, claim skip,
   `file->private_data`) and the `0x0f0008` read gating into the repo
   `package/open-tx-isp` patches.
4. Do not leave the bridge only in `/tmp`.

### Artifacts (2026-11-09)

- Modules: `/tmp/kilo/tx-isp-t41-vicdbg{36..39}.ko`.
- kmsg: `/tmp/kilo/kmsg-run{36..40}.log`; serial log
  `/home/paul/screen-sessions/screenlog-1793954143-3638111.txt`
  (`/dev/ttyUSB0`, T41).
- Source tree: `/tmp/kilo/otis-old/src/open-tx-isp-57d16f169e763422b66260c63c5efd65b08938e4`
  (not in the repo).

### 2026-11-09 (cont.): first MSCA-bank access itself stalls

Two more isolation runs (`vicdbg40`, `vicdbg41`) settled the cause:

- Reading a known-written MSCA register (`system_reg_read(0x0f0704)`, written by
  `tisp_msca_chx_cfg_load`) immediately before the QBUF FIFO write hangs the
  board. The whole `0x0f0000` bank is unreadable at QBUF time, not just
  `0x0f016c`.
- Calling `tisp_channel_main_start()` (the OEM MSCA channel program, which
  calls `tisp_msca_chx_cfg_load` and writes `0x0f0704`/`0x0f0180`/`0x0f0198`)
  from the QBUF path also hangs on its first `0x0f0000` write. So the bank
  cannot be programmed at all at this point.
- `ispcore_frame_channel_streamon()` resets its channel state and caches
  `channel+0x74`/`channel+0x78`, so the `cchq:msca-start` test never reached
  the core STREAM_ON handler; the attempt from the QBUF path is what stalled.

The safe `tisp_stream_on()` is byte-for-byte the OEM sequence (`0x1010`,
`0x1014`, `0x1008`, `0x1060`, the seven `tisp_event_set_cb` registrations)
and does not touch `0x0f0000`; the OEM does not call
`tisp_channel_main_start()` for output 0 either (only for `channel+0x74 != 0`).
So the open stack's first `0x0f0000` access is the QBUF FIFO write, and it
stalls unconditionally. Conclusion: the MSCA/AXI sub-block behind
`0x133f0000` is not alive in this bring-up; this is a power/clock/reset or
register-window issue, not an ordering bug.

Decisive next experiment (planned, not yet run): a standalone probe module
that, with no tx-isp loaded, clears the ISP gate (`CLKGR` bit 23), waits, then
reads `0x1331f00c` (IRSCA, known good) and `0x133f0704` (MSCA). If the IRSCA
read works but the MSCA read stalls with only the gate enabled, the bank is
not implemented on T41 and the solution is the vendor's direct-mode/IVDC path
(port `direct_mode` handling and the `0x03000007` IVDC alloc path in OpenIMP).
If both work, a driver step after clock enable is powering the bank down and
that step must be found and stopped.

### 2026-11-09 (cont.): reads work, writes poison the block

Standalone probe (`/tmp/kilo/mscaprobe`, no tx-isp loaded, ISP gate enabled by
clearing `CLKGR` bit 23):

```
clkgr   0x3fdf7f65 -> 0x3f5f7f65
core-33c   0x20220304
irsca-1f00c 0x20220304
msca-704   0x0384012c
msca-16c   0x0384012c
msca-008   0x00000000
```

So with the ISP gate enabled the whole `0x0f0000` bank is **readable**. A
read does not stall.

Write behaviour depends on the driver state:

- No tx-isp, gate enabled: `devmem` write to `0x133f016c`/`0x133f0704`
  returns and the following read still works. Manual SRBC reset
  (`0xb00000c4`, bit 21/20/22 sequence) first does not change that.
- `tx_isp_bringup_level=0`: write still safe.
- `tx_isp_bringup_level>=1` (graph/nodes created): a write to `0x133f0704`
  returns, then the next access to the bank hangs (watchdog). At QBUF the
  FIFO write stalls outright.
- Deferring the ISP firmware thread (`t41_defer_isp_fw_thread=1`) does not
  help; the FIFO write still stalls.
- Normal locking (IRQs off) and `qbuf_nolock=1` both stall, so it is not an
  IRQ re-entrancy or spinlock problem.
- The newer AKoo7/open-tx-isp tree still writes the known-bad
  `0x0f0080`/`0x0f0084` in its typed `tisp_msca_init`, so it is not a drop-in
  fix either.

The remaining delta is `tx_isp_create_graph_and_nodes()` (the level-1 step):
after it runs, host writes to the MSCA bank poison the block. Next: bisect
what inside the graph setup does it (the per-subdev `misc_register` path is
the prime suspect, e.g. a device being opened by userspace and activating the
ISP on the same block). If nothing in userspace does it, use the newer tree's
MSCA staged/latch write protocol so host writes never race a live MSCA.

### 2026-11-09 (cont.): the first post-REQBUFS ISP write stalls

Further bisection (vicdbg42..48) of the QBUF wedge:

- Deferring the ISP start/IPC (`t41_defer_isp_start=1`) works: the log shows
  `ispcore:isp-start-deferred` and no `tisp_ipc_triger` before QBUF. The FIFO
  write still stalls, so the firmware thread and IPC are not the cause.
- Disabling every stock profile replay (`t41_stock_*_profile=0`) and
  `t41_safe_tuning_events=0` does not help.
- Skipping the SET_FMT MSCA mirror/flip write (`skip_msca_flip=1`) does not
  help.
- An explicit probe right after `tisp_init()` (`probe_fifo_after_tisp=1`)
  shows `probe:after-tisp-write` and `probe:after-tisp-write-done` printing,
  then the following read of `0x0f0704` hangs. With IRSCA disabled
  (`0x1f008=0`) the write still returns and the read still hangs.
- `tisp_msca_addr_fifo_write()` against a driver that has run the full ISP
  init always stalls on the first write (0x0f016c), with or without the
  trailing `wmb()`. The typed `system_reg_write()` carried an extra `wmb()`
  that the stock T41 function does not; that is now opt-in
  (`reg_write_wmb=0`, default), but it did not fix the stall.
- At QBUF the first ISP register write stalls regardless of which register it
  is: `0x0f016c` normally, and `0x1f008` when the IRSCA-off experiment ran.
  SET_FMT's hvflip MSCA writes complete first, and REQBUFS performs no ISP
  register writes. So the bus becomes unresponsive between the SET_FMT write
  and the first QBUF ISP write.
- `fifo:w1-addr` now prints reliably; earlier missing marks were UART loss at
  the wedge, not a different code path.

This is the same AXI/ISP-bus-stall signature the T31 handoff describes: the
last completed operation is a normal MMIO access, the next ISP access never
returns, no oops, watchdog reset. It moves between operations run to run. The
remaining untested variable is the ISP clock state. Mainline reaches
ispm/isps/ispa = 276/368/552 MHz; the vendor requests 285/550/600
(`clk_set_parent("mpll")` + `clk_set_rate`). The mainline T41 CGU cannot reach
the requested rates (set_rate returns 0 without changing them), and a
too-slow/wrongly-parented ISP/MSCA AXI clock is the classic cause of this
exact stall. Next: replicate the vendor CGU parent/divider/rate state (or add
PLL set_rate) and re-test the QBUF write.

Debug parameters added in this pass: `t41_defer_isp_start`,
`qbuf_prestart`, `qbuf_nolock`, `streamon_event_first`, `skip_msca_flip`,
`fifo_irsca_off`, `reg_write_wmb`, `probe_fifo_after_tisp`.

### 2026-11-09 (cont.): driver-side hypotheses exhausted

Remaining tests, all negative (the first QBUF ISP write still stalled):

- ISP clock rates raised to the vendor target: with `isp_clks=552000000`,
  `clk_name/clks_name/clka_name=sclka`, `set_rate` actually moved ISPS
  368 -> 552 MHz (log `clk[2] after=552000000`). Still stalled.
- All CGU gates enabled (`CLKGR=0`, `CLKGR1=0`). Still stalled.
- Both stock profile replays off *and* `skip_msca_flip=1`. Still stalled.
- `reg_write_wmb=0` (match the stock plain-writel `system_reg_write`).
  Still stalled.

So the driver-side state is not the trigger. The vendor module runs the same
`tisp_init`, `tisp_msca_init`, `tisp_stream_on`, and the same QBUF FIFO write
on 4.4.94 and works. The open stack wedges the first ISP write after
`tisp_init` on 7.3.3. The remaining difference is the kernel/interconnect
(ISP AXI access attributes, interrupt/QoS, or the vendor kernel's ISP platform
glue), not the recovered driver.

Decisive next step needs the vendor register/clock state at the same point.
Options: (a) boot the stock image and dump the ISP/CGU/CPM state after
`IMP_FrameSource_EnableChn` (requires flashing the camera), or (b) build the
same open stack on the vendor 4.4.94 kernel where the driver is known to work.

### 2026-11-09 (cont.): the vendor runs T41 in direct mode

Decisive finding from the extracted vendor `/etc/init.d/rcS` (JFFS2 `mtd4`
at 0x1d00000 in the stock dump):

```
insmod tx-isp-t41.ko isp_clk=300000000 direct_mode=1
```

The vendor T41 stack **always runs `direct_mode=1`**. That means
`ispcore_frame_channel_qbuf()` takes the direct branch for output 0 and
never writes the MSCA address FIFO we have been stalling on. The whole
`direct_mode=0` FIFO path is dead code on this product.

The stock image was booted in the Ingenic QEMU `ingenic-t41` machine
(`ingenic-0.6.11`), which models the ISP at `0x13300000` as
`ingenic-t40-isp`. The vendor 4.4.94 kernel reaches a root shell; the
32 MiB flash is truncated to QEMU's 16 MiB W25Q128, so `mtd4`/`/etc` is
missing, but the rootfs still provides `tx-isp-t41.ko` and `libimp.so`.

Working toward the vendor path on the real camera (kernel 7.3.3):

1. `direct_mode=1` reroutes to `ivdc_pad_event_handle` case `0x03000007`;
   it oopsed because `ivdc_mem_paddr == 0` and the recovered
   `dma_alloc_from_coherent` tail dereferences `0xffffffff`.
2. The MDNS buffer *is* programmed by userspace (`set mdns-buf
   paddr=0x69c8000`, `bufinfo:program-return 0`). Falling back to
   `t41_mdns_buf_info[0].paddr` when `ivdc_mem_paddr == 0` removes the
   oops.
3. Matching the stock condition `if (channel+0x74 != 0)` (our recovery used
   `channel_index < 3`) stops `tisp_channel_main_start()` from being called
   for output 0, which the vendor never does.
4. With those two changes plus `skip_flip_write=1`,
   `skip_hvflip_reapply=1`, the direct-mode late start now reaches:
   IVDC streamon + IVDC IRQ, VIC start (`vicstart:return 0`), CSI/VIN
   sensor `s_stream` (`vsensor:call-ret=0`), and `ispcore:isp-start-already`.

The remaining stall is in the open-stack late-start tail (set-fmt/profiles/
fps reapply) after the input is live. It is the same intermittent ISP AXI
stall, and it moves between runs. The vendor performs none of those extra
live writes. Next: strip the late-start tuning/profile/hvflip/MSCA reapply
from the direct-mode path so the open stack matches the vendor's minimal
sequence, then re-enable them only if a feature needs them.

Debug params added this pass: `skip_flip_write`, `skip_hvflip_reapply`.
Earlier: `qbuf_prestart`, `qbuf_nolock`, `streamon_event_first`,
`skip_msca_flip`, `fifo_irsca_off`, `reg_write_wmb`,
`probe_fifo_after_tisp`, `t41_defer_isp_start`.

### 2026-11-09 (cont.): direct mode starts the input; sub-output QBUF is next

With `direct_mode=1`, `t41_defer_isp_start=1`, `minimal_ipc=1`,
`skip_flip_write=1`, `skip_hvflip_reapply=1` and every `t41_stock_*_profile`
plus `t41_safe_tuning_events` off, the late input start now completes:

- IVDC streamon and IVDC IRQ
- VIC start (`vicstart:return 0`)
- CSI/VIN sensor `s_stream` (`vsensor:call-ret=0`)
- defered ISP start + IPC trigger (`ispcore:isp-ipc-triggered`)

and the flow reaches the frame-channel STREAMON enqueue at ~56 s. The next
stall is the **second output** (pad index 1, `channel_index=1`): its QBUF
takes the `direct_mode && channel+0x74 == 0` branch only for channel 0. For
channel 1 the code falls through to `tisp_msca_addr_fifo_write(1, ...)`
(`0xf026c`) and stalls, because the sub-channel's
`tisp_channel_main_start()` runs in `ispcore_frame_channel_streamon()` only
after the pre-STREAM_ON enqueue loop has already pushed the addresses.

Next: make the sub-output match whatever the vendor does before its first
QBUF, or hold the sub-channel FIFO push until after its STREAM_ON has
programmed the MSCA channel. `minimal_ipc` also skips the pre/post-IPC
diagnostic reads and the late fps/tmo/snapshot replays.
