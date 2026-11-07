# T41 mainline ISP driver port

Date: 2026-11-06
Branch: `feature/kernel-7`
Target: `noorio_t120_t41nq_gc8613_aic8800d`, Linux 7.3.1, GC8613

## Why

The GC8613 now probes as a mainline V4L2 subdev, but there is no host driver
for the T41 CIM/VIC/ISP, so there is no `/dev/video*` and no frame path.
`package/open-tx-isp` supports T41 only on the vendor 4.4.94 tree
(`Config.in`), and the 7.3.1 patch series has no T41 ISP driver.

## What exists

- `open-tx-isp/driver/t41/` — recovered T41 TX-ISP driver for the OEM
  T41 4.4.94 target (171k-line `tx_isp_t41_recovered.c`, V4L2 frontend in
  `tx_isp_t41_v4l2.c`, T41 register map in `tx_isp_t41_adr.h`). It expects
  vendor sensor modules through the private I2C driver ABI.
- `open-tx-isp/driver/t31/` — the same architecture already ported to
  mainline 5.15/7.x, with `tx_isp_kernel_compat.h`, a V4L2 subdev bridge
  (`tx_isp_v4l2_sensor.c`), and CSI/VIC/ISP bring-up.
- `open-tx-isp/driver/common/` — shared day/night, exposure, scaler,
  sensor registry, callback and frame-layout code used by both.

## Strategy

Port `driver/t41` to 7.3.1, using `driver/t31` as the API and integration
reference. Keep the T41 register map and recovery code; replace the 4.4
kernel API surface and the vendor sensor attachment with the mainline
equivalents. Deliver as an `open-tx-isp` patch series plus the `Config.in`
enablement, not as a fork pin.

## Phases

### Phase 1 — compile the core (DONE 2026-11-06)

1. Built `driver/t41` against the 7.3.1 tree from a local override clone.
2. Added `tx_isp_t41_kernel_compat.h` and `tx_isp_t41_compat.c`.
3. Fixed the 4.4 API surface in the core and V4L2 frontend (see the patch
   `package/open-tx-isp/0036-t41-mainline-7x.patch`).
4. Success: `tx-isp-t41.ko` links with the V4L2 frontend enabled and no
   unresolved symbols, provided the kernel has `CONFIG_VIDEOBUF2_DMA_CONTIG`.

Build command used:

```
make -C $KDIR M=$SRC/driver/t41 DIR=. \
     CONFIG_TX_ISP_T41_V4L2=y CONFIG_VIDEOBUF2_DMA_CONTIG=y \
     KCFLAGS="-DCONFIG_VIDEOBUF2_DMA_CONTIG=1 -DCONFIG_DMA_SHARED_BUFFER=1" \
     modules
```

Known gaps for the next phase:

- The V4L2 bridge still uses the `set_fs(KERNEL_DS)` idiom (now a no-op) for
  internal ioctl calls. The called paths use `copy_from_user`, so they will
  reject kernel pointers on 7.x; the ioctl paths must be adapted before
  capture works.
- `dma_release_from_coherent` is a stub (`-ENOENT`); the recovered DMA free
  path needs the real coherent size/address bookkeeping.
- `jzgpio_set_func` is a no-op; the ISP/VIC GPIO pin functions must move to
  DT pinctrl states or the Ingenic pinctrl API.
- The recovered direct `__copy_user` calls are mapped to `memcpy`; the user
  copy paths must be audited and split into from-user/to-user before the
  driver is exposed to untrusted ioctls.
- The `THINGINO_ISP_OPEN` choice pulls in OpenIMP, which does not fit the
  T120 rootfs. The T41 kernel driver must be buildable standalone (V4L2 only)
  for this board.

### Phase 2 — load and probe the ISP

1. Add T41 7.x support to `package/open-tx-isp/Config.in` and the module
   subdir logic (build `driver/t41` only; no `sensor-src/t41`).
2. Bring up clocks/reset/IRQ and the register mapping on the T120.
3. Success: `insmod tx-isp-t41.ko` probes the ISP, logs the chip version and
   does not crash; `rmmod` is clean.

### Phase 3 — sensor bridge

1. Connect the mainline GC8613 subdev to the T41 ISP input: port the T31
   `tx_isp_v4l2_sensor.c` bridge to the T41 sensor ABI (i2c_driver vs
   `v4l2_subdev`, pad/link layout, stream-on/off, format negotiation).
2. Success: media graph includes the sensor and the ISP input; the ISP
   reports the sensor attached and the input format.

### Phase 4 — V4L2 capture

1. Replace `VFL_TYPE_GRABBER` and the 4.4 videobuf2 calls with the 7.x API.
2. Success: `/dev/video0` registers, `VIDIOC_*` work, and a single NV12 frame
   can be captured (or the ISP frame-start/end IRQs advance with buffers
   queued) on the T120.

### Phase 5 — stabilization (not in this milestone)

- rmmod/insmod repeatability, error paths, size in the rootfs, and only then
  AE/AWB/IQ tuning parity.

## Phase 2 bring-up log (2026-11-06)

The module now loads and the recovered probe runs. Fixes found so far:

- `platform_data` was read at the 4.4 offset `+0x5c`; use
  `pdev->dev.platform_data`.
- The raw 4.4 `struct resource` blobs have `start, end, name`; 7.x has
  `name, start, end`. Replaced with real `struct resource` arrays.
- Vendor IRQ numbers are hwirq + 8 (VIC 30 -> 38, ISP 31 -> 39, IVDC 13 ->
  21, LDC 35 -> 43). Added `tx_isp_t41_map_irq()`: find the
  `ingenic,core-intc` domain and `irq_create_mapping(hwirq)`.
- `v4l2_device_register()` panics when the platform device has no driver
  bound (`dev->driver NULL`); the V4L2 init now refuses that case.
- `CONFIG_VIDEOBUF2_DMA_CONTIG` has no prompt, so add
  `CONFIG_VIDEOBUF2_DMA_CONTIG_THINGINO` (kernel patch 0139) as a selector.
- The V4L2 frontend needs the 7.x `queue_setup` signature and
  `alloc_devs[]`, not the old `alloc_ctx` API.

Current state (last insmod):

```
@@@@ tx-isp-probe ok (version H20250310a) @@@@
tx-isp-sinfo: initialized max_sensors=4
t41: V4L2 MMAP node registered as /dev/video0 (channel 0)
t41: V4L2 MMAP node registered as /dev/video1 (channel 1)
t41: V4L2 MMAP node registered as /dev/video2 (channel 2)
```

The vendor clock names now get clkdev lookups, so
`devm_clk_get()`/`devm_clk_put()` are symmetric and the
`clk-devres.c:335` warning is gone. The V4L2 frontend sets
`device_caps`, so `video_register_device()` succeeds. There is no
`/dev/media*`; the driver exposes the capture nodes directly.

The main tx-isp probe now succeeds. The subdevs get their IRQs and the
vendor clock names resolve through `of_clk_get_from_provider()` against
the T41 CGU. The clock cleanup then warns in `clk-devres.c:335` because
the clocks came from `of_clk_get_from_provider()` but are released with
`devm_clk_put()`. The module init still returns `-EINVAL`, now from the
`tx_isp_sinfo_init()` `/proc/jz/sensor` failure (or the V4L2 init after
it).

Procfs, after comparing with the T31 driver on the cinnado d1 and wyze
cam 2 builds (`driver/t31/tx_isp_proc.c`):

- The T31 driver creates `/proc/jz` once in `tx_isp_create_proc_entries`,
  returns that entry from `tx_isp_get_jz_proc_root()`, and removes the
  whole `/proc/jz` tree in `tx_isp_remove_proc_entries()`.
- The T41 compat created `/proc/jz` lazily and never removed it, so a
  failed load left it behind and the next load's `proc_mkdir("jz")`
  returned NULL (the "cannot create /proc/jz/sensor" warning).
- Fixed: `tx_isp_t41_proc_exit()` removes the root, and it is called from
  both `init_module()` failure paths and `cleanup_module()`.

Remaining, in order:

1. The last insmod still returns `-EINVAL` and the current dmesg (after
   clearing) only shows the `clk-devres.c:335` warnings; no V4L2 error
   line. Trace the module init with a clean log buffer and confirm which
   step returns the error (`tx_isp_init`, the main probe, or the V4L2
   init).
2. Register clkdev lookups for the vendor names and use plain
   `devm_clk_get()`; this removes the `devm_clk_put` warnings and makes
   the clock lifecycle correct.
3. Then the sensor bridge (Phase 3) and capture (Phase 4).

## tx-isp open crash (2026-11-06)

The RAPTOR image booted but `rvd` opening `/dev/tx-isp` panicked with
`BadVA 000000c8` in `tx_isp_open`. The recovered open/ioctl/release/helpers
read `file->private_data` at the 4.4 offset `+0x88`; the 7.x `struct file`
layout differs, so the pointer was garbage (`misc=27ea0bf8`,
`refs=3467476487`). They now use the `struct file` member. Same fix applied
to `frame_channel_open`, `tx_isp_release` and the video-link ioctls.

The camera config selects RAPTOR (`BR2_PACKAGE_THINGINO_STREAMER_RAPTOR`).
Both timpsd and RAPTOR's rvd open the vendor `/dev/tx-isp` ABI, so the
streamer choice does not avoid the open; the open fix is the real one.

The full OTA left a bad U-Boot env CRC. The built-in default env already
carries the new layout (`6464k(rootfs),23552k(data)`), matching the RAPTOR
image; `saveenv` restored it. Recovery used failsafe mode plus stubs for
`S30raptor-sensor-wait`, `S31raptor`, `S32raptor-motion` and `S95timps`.

## Preview 502 and sensor registration (2026-11-06)

The WebUI preview fails with `POST /x/webrtc-whip.cgi?stream=0 502`.
`webrtc-whip.cgi` proxies to `https://127.0.0.1:8554/whip`; the 502
means `rvd` is not listening. `rvd` exits during pipeline init:

```
rvd: sensor0: gc8613 i2c=0x31 bus=0 id=0 mclk=1 vin=0 boot=0
rvd: IMP_ISP_AddSensor((IMPVI_NUM)0, ...) failed: -4095
rvd: HAL init failed: -4095
```

The T41 `tx_isp_sensor_register_sensor` forwards
`T41_EVENT_SENSOR_REGISTER` to the VIN subdev; no GC8613 vendor sensor
is registered there. The mainline GC8613 subdev probes on I2C but is not
part of the T41 vendor VIN, so `AddSensor` fails. This is Phase 3: port
the T31 `tx_isp_v4l2_sensor.c` bridge or add a T41 vendor sensor module.
`open-tx-isp` has no `sensor-src/t41` (only t21/t31); the T31
`sensor-src/t31/gc2053.c` (2240 lines) is the vendor sensor template.

The firmware itself is healthy: S31raptor loads the tx-isp module,
`/dev/tx-isp` and `/dev/video0..2` exist, and the vendor open now
returns `refs=0` / `VIN fallback ret=0` without a panic.

### ERR_PTR panic on the same path (2026-11-06)

Once the mainline GC8613 subdev binds at `0x31`, the vendor bridge can no
longer create its own client for that address. `isp_i2c_new_subdev_board()`
checked the `i2c_new_client_device()` result only for NULL and then read
`client->dev.driver`, so the `-EBUSY` ERR_PTR produced:

```
gc8613 0-0031: Failed to register i2c client gc8613 at 0x31 (-16)
BadVA: 00000048
<8c420058>  lw v0,0x58(v0)
```

`0037-t41-handle-i2c-client-errors.patch` treats `IS_ERR_OR_NULL()` as a
failed registration and clears the pointer before the cleanup path, so
`AddSensor` returns `-EINVAL` instead of panicking the kernel. This is the
same defect the T31 driver fixed in `0015`, and it is still the Phase 3
gap: the mainline subdev cannot stand in for a vendor sensor module.

## Phase 3 sensor bridge (2026-11-06)

`0038-t41-attach-the-mainline-v4l2-sensor.patch` adds
`driver/t41/tx_isp_t41_v4l2_sensor.c`, the T41 counterpart of the T31
bridge.  It finds the already probed mainline GC8613 subdev on i2c-0,
keeps its V4L2 controls, and implements the vendor sensor ABI on top of
them:

- the sensor object is laid out with the OEM offsets from the recovered
  binary: `dev` 276, `index` 280, `info` 296, `attr` 396, `video` 724,
  `video.attr` 776, `video.info` 780;
- `tx_isp_subdev_init()` is called with a pdev whose `platform_data` is
  NULL, so only the module header and the ops pointer are initialised;
- the attribute carries the GC8613 gain table as log2 gain in Q16,
  `max_again = 393216` (64x), 3840x2160 MIPI RAW10, and the timing read
  back from the mainline controls (`hblank`, `vblank`, `pixel_rate`,
  `link_freq`);
- `s_stream` goes through the mainline subdev `s_stream` helper, and the
  EXPO/FPS/VFLIP/RESIZE events map to the V4L2 exposure, analogue-gain,
  vblank and flip controls;
- `t41_register_sensor()` tries the bridge before creating a vendor I2C
  client, and `t41_unregister_i2c_sensor()` releases the bridge instead
  of unregistering a client it does not own.

The module builds and links; the image rootfs is 6,836,224 bytes in a
6,881,280-byte partition (44 KiB free).

### QEMU validation (2026-11-06)

The T41 flash image cannot be booted by the pinned QEMU (`ingenic-0.6.11`)
or the current release (`ingenic-0.7.10`): U-Boot reads the flash, then the
kernel's DMA-only T41 SFC transfer times out and the rootfs never mounts.

```
ingenic-sfc 13440000.sfc0: SFC DMA timeout: SR=0x00010004 GLB=0x0000104d
spi-nor spi0.0: probe with driver spi-nor failed with error -145
Kernel panic - not syncing: VFS: Unable to mount root fs
```

The same happens with the stock `qemu_t41nq` profile, so it is not caused by
the sensor work.  Direct `-kernel` boot works around it: build a raw
(uncompressed) uImage, point QEMU at `vmlinux.bin` plus an initramfs, and
use the image's `mem=` line.

The bridge was then exercised with the QEMU image-sensor model:

```
-device image-sensor,bus=i2c0,address=0x29,model=gc4023
```

`gc4023` probes as a mainline subdev and `AddSensor` takes the bridge:

```
gc4023 0-0029: gc4023: chip id 4023
tx-isp-v4l2: attached gc4023 at i2c-0/0x29 (2560x1440, 2 lanes, link 432000000 Hz)
t41: sensor-register VIN returned 0
REGISTER ret=0
RELEASE ret=0
t41: sensor-release VIN returned 0
```

The only dmesg noise is pre-existing: the recovered driver's
`Unexpected gfp: 0x2000000` kmalloc warning and the `IRQ index N not found`
messages from probing for optional IRQs.

Two gc4023 fixes came out of this and are kept: the same VPLL CIM parent and
PA15 pinctrl that `gc8613.dtsi` already has, and a 1% xclk window
(`0138-media-gc4023-accept-the-t41-cim-xclk.patch`).

## Current state (2026-11-07)

The bridge reached the point where the mainline GC8613 subdev was found,
`AddSensor` returned 0 and `/proc/jz/sensor/sensor0` reported the real
3820x2160 sensor.  The next stage then panicked: the recovered driver walks
the ISP video-link graph, the bridge sensor is not in that graph, and it
jumped through an uninitialised ops pointer.  The bridge therefore needs
pad/internal ops and graph registration before it can be enabled.

The bridge patches are kept as `.disabled` for that work:

- `0038-t41-attach-the-mainline-v4l2-sensor.patch.disabled`
- `0039-t41-mdns-accept-paddr-zero.patch.disabled`
- `0040-t41-mdns-profile-error-nonfatal.patch.disabled`

The shipped T120 image uses `0037` only, so `AddSensor` fails gracefully
instead of panicking.  It also carries the bring-up fixes found during this
round:

- `S36wireless` power-cycles the WLAN pin on every boot and drives it
  inactive in `stop()`; the T120 uses the verified GPIO 57 REGON, not the
  T110's GPIO 60;
- the MAC and hostname come from U-Boot's eFUSE-derived `ethaddr`, not the
  unreliable post-boot `devmem` read, so they survive full reflashes;
- BusyBox `CONFIG_FEATURE_IPV6` follows `BR2_PACKAGE_THINGINO_KOPT_IPV6`,
  so a kernel without IPv6 does not build the `/proc/net/*6` readers.

Verified on the T120 after an OTA: `wlan0` at `02:22:3f:01:c5:4a`,
camera at 192.168.88.121, same MAC/IP/hostname after a full reflash, and
`netstat -ln` with no IPv6 warnings.

## Validation

- Phases 1: object/module build with the 7.3.1 cross toolchain.
- Phase 2: serial console `dmesg`, `lsmod`, clean `rmmod`.
- Phase 3: `media-ctl -p` graph and the ISP attach log.
- Phase 4: `v4l2-ctl --stream-mmap --stream-count=1` and a frame checksum.

## Risks

- The T41 core is recovered decompiler output, not a clean driver; API fixes
  may expose latent control-flow bugs.
- The T41 sensor interface is the vendor private-I2C ABI, not `v4l2_subdev`;
  the bridge is new code, not a mechanical port.
- T41 ISP programming is only known from the recovered source; there is no
  mainline documentation.
- The rootfs is already tight; the driver must stay modular for bring-up.
