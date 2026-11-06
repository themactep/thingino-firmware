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
tx-isp-sinfo: cannot create /proc/jz/sensor
tx-isp-sinfo: exited
insmod: can't insert ...: Invalid argument
```

The main tx-isp probe now succeeds. The subdevs get their IRQs and the
vendor clock names resolve through `of_clk_get_from_provider()` against
the T41 CGU. The clock cleanup then warns in `clk-devres.c:335` because
the clocks came from `of_clk_get_from_provider()` but are released with
`devm_clk_put()`. The module init still returns `-EINVAL`, now from the
`tx_isp_sinfo_init()` `/proc/jz/sensor` failure (or the V4L2 init after
it).

Next steps:

1. Register clkdev lookups for the vendor names (`gate_isp`, `gate_csi`,
   `div_ispm`, `div_isps`, `div_ispa`, `gate_ivdc`, `div_ldc`,
   `gate_ldc`) with `clkdev_create()`, then use plain `devm_clk_get()`.
   This removes the `devm_clk_put` warnings and makes the lifecycle
   correct.
2. Find why `tx_isp_sinfo_init()` cannot create `/proc/jz/sensor`. The
   compat `tx_isp_get_jz_proc_root()` and `jz_proc_mkdir()` are the
   first suspects.
3. Then the V4L2 init error (guard on `parent->driver` or a real failure)
   and the sensor bridge (Phase 3).

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
