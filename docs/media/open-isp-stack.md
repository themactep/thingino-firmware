# Open ISP stack

Thingino exposes the Ingenic media implementation through the same kind of
virtual-package choice used for streamers. The proprietary stack remains the
default. Select the experimental implementation in `menuconfig` under
`Thingino Firmware → System Packages → ISP stack`, or put this in a scoped
`local.fragment`:

```text
BR2_PACKAGE_THINGINO_ISP_OPEN=y
```

The open provider selects `open-tx-isp` (the kernel driver) plus OpenIMP
(`libimp.so`) where available, with `ingenic-system-libs-neo` and
`libaudioProcess-neo` replacing the support libraries.

## SoC coverage

Upstream (as cloned into `overrides/open-tx-isp/` and `overrides/openimp/`)
has moved past the original four-SoC scope.

| Component | Upstream driver/build scope |
| --- | --- |
| open-tx-isp driver | T10, T20, T21, T23, T30, T31, T40, T41 |
| OpenIMP `libimp.so` | T20, T21, T23, T30, T31, T40, T41 |

The Thingino Kconfig gates mirror that, minus the T10 odd case:

- `OPEN_TX_ISP_SUPPORTED` (T10/T20/T21/T23/T30/T31 on 3.10.14, T40/T41 on
  4.4.94).
- `OPENIMP_SUPPORTED` (T20/T21/T23/T30/T31 on 3.10.14, T40/T41 on 4.4.94).

**T10** has an open-tx-isp driver but no OpenIMP build target, so it stays
out of the OpenIMP gate and keeps the Ingenic libimp provider.

**T23** is a hybrid build: a partial `libimp.so` with no audio entry points
plus an `openimp-t23-helixd` worker that links the OEM `libimp.so` for the
proprietary Helix encoder, while RAD keeps using OEM `libimp.so` for audio.
`openimp.mk` selects `BR2_PACKAGE_INGENIC_LIB_LIBIMP`, copies that OEM
`libimp.so` to `/opt/openimp-t23/libimp.so` next to the helixd worker, and
installs OpenIMP's `libimp.so` as `/usr/lib/libimp.so` for RAD.

C100 is not covered by either component.

Kernel focus:

- Linux 3.10.14 vendor trees: T10, T20, T21, T23, T30, T31
- Linux 4.4.94 vendor trees: T40, T41
- T31 also builds on the mainline Linux 7.1 compatibility path upstream
  (Thingino's Kconfig exposes the open stack only on the vendor trees)

## Module completeness

- **Audio**: `IMP_AI_*` implemented for T31 and T40; T20/T21 reuse the T31
  audio implementation. T30 is video-only — its build deliberately refuses to
  export the IMP audio entry points.
- **OSD**: implemented for T31; T40 marks the `IMP_OSD_*` entry points
  `P3_UNSUPPORTED` (returns `ENOTSUP`).
- **ISP**: `isp_tseries.c` provides the `IMP_ISP_*` tuning surface
  (brightness/contrast/sharpness and friends).
- **IVS**: still incomplete — no `IMP_IVS_MoveDetect`, and T40 stubs the IVS
  entry points.
- **Encoder**: per-SoC encode paths exist — Helix for T21/T30, the shared
  AVPU backend for T31/T40/T41, and for T23 the AVPU backend plus the
  separate `openimp-t23-helixd` worker that links the OEM Helix encoder. The
  upstream README reports decoder-clean H.264 on T30/T31/T40; T41 is still
  in correctness bring-up.

## Installation

The open driver is installed as `tx-isp-<soc>.ko`, preserving the module name
expected by the SDK sensor drivers and `/etc/modules.d/20-isp`. OpenIMP and
the neo libraries are installed to staging before consumers link, and target
finalization preserves the selected replacements in the root filesystem.

OpenIMP also installs `openimp-tuningd`; its init script (`S30openimp-tuning`)
starts it only when Raptor reports the V4L2 video backend
(`raptorctl config get system video_backend`).

## Sensor info registry (/proc/jz/sensor)

`/proc/jz/sensor` is owned by the ISP, not by the sensor modules. The ISP
publishes an indexed registry - `count`, `events`, and one `sensorN/`
directory per registered sensor with `name`, `i2c_addr`, `status`, geometry,
fps and the wiring fields - which is what Raptor's multi-sensor model reads
(`rvd` scans `sensorN/status` to find the active sensor).

The vendor ISP implements this in `tx-isp-sinfo.c`; the open driver ports it
as `tx_isp_sinfo` (`driver/common/tx_isp_sinfo.c`, with a per-SoC ABI config
in `driver/<soc>/tx_isp_<soc>_sinfo.c`). The SDK sensor modules must not
create the same node: procfs resolves a duplicated name to the last
registrant, so their flat tree shadowed the ISP's `sensorN/` and Raptor could
not find the active sensor. ciao passes `-DSENSOR_PROC_OWNED_BY_ISP` to the
sensor module build (`package/ingenic-sdk/ingenic-sdk.mk`) when the open
stack is selected; `common/sensor/common/sensor-info.c` then only registers
attributes and leaves the node to the ISP. Proprietary builds keep the sensor
module's tree because their ISP has no such registry.

Known gap closed: the bind path works (`sensor_bind` populates the slot once
the sensor is active), and the pre-bind values come from
`tx_isp_sinfo_driver_add()`. The one missing piece was the I2C address -
`rvd` reads `i2c_addr` *before* it binds the sensor, so the sensor module has
to publish the driver with the real address at load time. Every family's
`common/isp/<arch>/include/sensor-common.h` now wraps
`private_i2c_add_driver()` to call `tx_isp_sinfo_driver_add()` with the
driver's own `SENSOR_I2C_ADDRESS` when `SENSOR_PROC_OWNED_BY_ISP` is set (the
registry merges the repeat call, so t31's legacy-zero wrapper is fine too).
The pre-bind registry then reports the address and Raptor autodetects
without a per-camera pin. Verified on T31: `sensor0/{name,i2c_addr,status,
width,height,fps}` populate and `rvd` brings the full stack up with
`[sensor]` unset.

The bind - the second half of the slot, which fills `width/height/fps/
chip_id` and moves `status` to active - is wired per family, because the
vendor wrappers differ:

- **T31** - the ISP calls `tx_isp_sinfo_sensor_bind()` itself when it
  registers the subdev, so the SDK needs nothing.
- **T23** - the recovered ISP never calls it, so
  `common/isp/t23/include/sensor-common.h` wraps the sensor's
  `tx_isp_subdev_init()`/`deinit()` and binds there (the probe is where the
  subdev and its attributes become valid).
- **T20** - the sensor drivers use the apical `v4l2_i2c_subdev_init()`, not
  the tx-isp subdev, so the call is added to `subdev_core_ops_register_sensor()`
  in the driver (`package/open-tx-isp/0001-t20-publish-sensors-to-the-sinfo-registry.patch`).

The remaining families' `sensor-common.h` share the T23 shape and would take
the same hook, but only T31/T20/T23 have been built and run.

## Video rings and refmode

`rvd` publishes H.264 into `rss_ring_main` in zero-copy refmode by default,
which assumes the encoder's output buffers live inside the ISP `rmem`
reservation. OpenIMP's AVPU encoder allocates them elsewhere, so every frame
falls back to an inline copy that the refmode-sized ring cannot hold - the
H.264 ring stays empty and RTSP and the WebRTC preview stay black (the JPEG
path is unaffected, which is why snapshots and MJPEG work). `thingino-raptor`'s
`[ring] refmode` now defaults to false when `BR2_PACKAGE_OPENIMP` is selected;
the proprietary libimp allocates from rmem and keeps zero-copy.

## Status

Per the upstream `open-tx-isp` README, the driver is device-tested on T20,
T23, T30, T31, T40, and T41 (T10/T21 hardware validation pending), with
near-OEM daylight parity demonstrated on T31/SC301IOT. OpenIMP streams on
device on T20 and T31. H/V flip control now reaches the real MSCA output
register.

Known issue - T23 + Raptor: the open ISP plus Raptor hangs the device a
minute or so into boot on T23 (userspace starves, SSH stops completing the
banner exchange, ping still answers) and the watchdog resets it in a loop.
The registry is populated and `tx-isp-t23`/`sensor_gc2083_t23` load, so the
runaway appears once `rvd` brings the encoder up; the OpenIMP T23 encoder
goes through the `openimp-t23-helixd` bridge, whose session code is a
suspect. T31 (`wyze_cam3_t31x`) and T20 (`wyze_cam2_t20x`) stream fine. The
classic build (proprietary ISP + prudynt) is unaffected and is the T23
fallback until this is isolated.

Still experimental: night/IR, WDR, extreme exposure, additional sensors, and
long-duration stability lack OEM-comparable validation, and some tuning tables
remain synthetic or partially reconstructed.

Select `BR2_PACKAGE_THINGINO_ISP_PROPRIETARY=y` to return to the Ingenic
driver and libimp provider.
