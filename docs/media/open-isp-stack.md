# Open ISP stack

Thingino exposes the Ingenic media implementation through the same kind of
virtual-package choice used for streamers. The proprietary stack remains the
default. Select the experimental implementation in `menuconfig` under
`Thingino Firmware → System Packages → ISP stack`, or put this in a scoped
`local.fragment`:

```text
BR2_PACKAGE_THINGINO_ISP_OPEN=y
```

T31 builds can opt into the public V4L2 capture path and Raptor's OpenIMP AVC
bridge with:

```text
BR2_PACKAGE_THINGINO_ISP_OPEN=y
BR2_PACKAGE_OPENIMP_USE_V4L2=y
BR2_PACKAGE_THINGINO_STREAMER_RAPTOR=y
```

This enables the T31 open-tx-isp adapter and the vendor kernel's ION/DMA-BUF
support used to share capture buffers with OpenIMP. The adapter exposes NV12
capture on `/dev/video0`; open-tx-isp routes sensor MCLK itself. Set Raptor's
`system.video_backend` to `v4l2` at runtime to use the V4L2-to-OpenIMP encoder
path. The option is currently limited to T31 on vendor Linux 3.10.14.

The open provider selects:

| Component | T23 | T31 | T40 | T41 |
| --- | --- | --- | --- | --- |
| open-tx-isp kernel driver | yes | yes | yes | yes |
| OpenIMP `libimp.so` | no | yes | yes | yes |
| ingenic-system-libs-neo | yes | yes | yes | yes |
| libaudioProcess-neo | yes | yes | yes | yes |

T23/T31 are limited to the vendor Linux 3.10.14 trees. T40/T41 are limited to
the vendor Linux 4.4.94 trees. C100 is not included in the T31 support claim.

OpenIMP currently has device builds for T31, T40, and T41. T23 therefore keeps
the proprietary `libimp.so` while replacing the ISP kernel driver and the
system/audio support libraries.

The T31 OpenIMP build is currently video-focused and intentionally omits IMP
audio entry points; some optional OSD/IVS calls used by feature-rich streamers
are also incomplete. Select `BR2_PACKAGE_THINGINO_ISP_PROPRIETARY=y` to return
the entire camera profile to the Ingenic ISP driver and libimp provider.

The open driver is installed as `tx-isp-<soc>.ko`, preserving the module name
expected by the SDK sensor drivers and `/etc/modules.d/20-isp`. OpenIMP and the
neo libraries are installed to staging before consumers link, and target
finalization preserves the selected replacements in the root filesystem.
OpenIMP also installs `openimp-tuningd`; its init script activates only when
Raptor is configured for the V4L2 backend. The bridge is compiled only when
`BR2_PACKAGE_OPENIMP_USE_V4L2=y`.

This profile is experimental. Upstream reports working streams on supported
targets, but image tuning, sensor coverage, WDR, flip, exposure range, and
OEM-equivalent image quality remain incomplete.
