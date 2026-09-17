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
| OpenIMP `libimp.so` | T20, T21, T30, T31, T40, T41 |

The Thingino Kconfig gates mirror that, minus the two odd cases:

- `OPEN_TX_ISP_SUPPORTED` (T10/T20/T21/T23/T30/T31 on 3.10.14, T40/T41 on
  4.4.94).
- `OPENIMP_SUPPORTED` (T20/T21/T30/T31 on 3.10.14, T40/T41 on 4.4.94).

Two upstream targets are intentionally left out of the OpenIMP gate:

- **T23** is a hybrid build: a partial `libimp.so` with no audio entry points
  plus an `openimp-t23-helixd` worker that links the OEM `libimp.so` for the
  proprietary Helix encoder, while RAD keeps using OEM `libimp.so` for audio.
  Thingino's `openimp.mk` does not install the helixd worker or preserve the
  OEM `libimp.so`, so T23 keeps the proprietary userspace.
- **T10** has an open-tx-isp driver but no OpenIMP build target.

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

## Status

Per the upstream `open-tx-isp` README, the driver is device-tested on T20,
T23, T30, T31, T40, and T41 (T10/T21 hardware validation pending), with
near-OEM daylight parity demonstrated on T31/SC301IOT. OpenIMP streams on
device on T20 and T31. H/V flip control now reaches the real MSCA output
register.

Still experimental: night/IR, WDR, extreme exposure, additional sensors, and
long-duration stability lack OEM-comparable validation, and some tuning tables
remain synthetic or partially reconstructed.

Select `BR2_PACKAGE_THINGINO_ISP_PROPRIETARY=y` to return to the Ingenic
driver and libimp provider.
