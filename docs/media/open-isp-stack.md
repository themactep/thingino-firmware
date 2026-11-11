# Open ISP stack

Thingino exposes the Ingenic media implementation through the same kind of
virtual-package choice used for streamers. The proprietary stack remains the
default. Select the experimental implementation in `menuconfig` under
`Thingino Firmware → System Packages → ISP stack`, or put this in a scoped
`local.fragment`:

```text
BR2_PACKAGE_THINGINO_ISP_OPEN=y
```

SoCs with a public DMA-BUF capture adapter can opt into the V4L2 path and
Raptor's OpenIMP AVC bridge with:

```text
BR2_PACKAGE_THINGINO_ISP_OPEN=y
BR2_PACKAGE_OPENIMP_USE_V4L2=y
BR2_PACKAGE_THINGINO_STREAMER_RAPTOR=y
```

This enables the SoC's open-tx-isp adapter and kernel DMA-BUF support used to
share capture buffers with OpenIMP. The adapter exposes NV12 capture on
`/dev/video0`. Set Raptor's `system.video_backend` to `v4l2` at runtime to use
the V4L2-to-OpenIMP encoder path. The option is available on T20, T21, T30,
T31, T40, and T41.

The open provider selects:

| Component | T10 | T20 | T21 | T23 | T30 | T31 | T40 | T41 |
| --- | --- | --- | --- | --- | --- | --- | --- | --- |
| open-tx-isp kernel driver | yes | yes | yes | yes | yes | yes | yes | yes |
| OpenIMP `libimp.so` | no | yes | yes | yes | yes | yes | yes | yes |
| V4L2/OpenIMP bridge | no | yes | yes | no | yes | yes | yes | yes |
| ingenic-system-libs-neo | yes | yes | yes | yes | yes | yes | yes | yes |
| libaudioProcess-neo | yes | yes | yes | yes | yes | yes | yes | yes |

T10, T20, T21, T23, T30, and T31 are limited to the vendor Linux 3.10.14
trees. T40/T41 are limited to the vendor Linux 4.4.94 trees. C100 is not
included in the T31 support claim.

OpenIMP has device builds for T20, T21, T23, T30, T31, T40, and T41. The T23
encoder keeps its proprietary Helix worker isolated with a private OEM
`libimp.so`; the public `/usr/lib/libimp.so` remains OpenIMP. T10 uses
open-tx-isp with the Ingenic userspace ABI because OpenIMP has no T10 target.

Several OpenIMP targets remain video-focused and intentionally omit some IMP
audio, OSD, or IVS entry points. Select
`BR2_PACKAGE_THINGINO_ISP_PROPRIETARY=y` to return the entire camera profile to
the Ingenic ISP driver and libimp provider.

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
