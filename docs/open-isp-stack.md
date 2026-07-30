# Open ISP stack

Thingino provides an opt-in open ISP profile for camera definitions and user
configuration layers that want to exercise the open Ingenic media stack.
Add `open-isp` to a camera defconfig's `# FRAG:` line, or put this in a scoped
`local.fragment`:

```text
BR2_PACKAGE_THINGINO_OPEN_ISP=y
```

The profile selects:

| Component | T23 | T31 | T40 | T41 |
| --- | --- | --- | --- | --- |
| open-tx-isp kernel driver | yes | yes | yes | yes |
| OpenIMP `libimp.so` | no | yes | yes | no |
| ingenic-system-libs-neo | yes | yes | yes | yes |
| libaudioProcess-neo | yes | yes | yes | yes |

T23/T31 are limited to the vendor Linux 3.10.14 trees. T40/T41 are limited to
the vendor Linux 4.4.94 trees. C100 is not included in the T31 support claim.

OpenIMP currently has device builds for T31 and T40 only. T23 and T41 profiles
therefore keep the proprietary `libimp.so` while replacing the ISP kernel
driver and the system/audio support libraries.

The T31 OpenIMP build is currently video-focused and intentionally omits IMP
audio entry points; some optional OSD/IVS calls used by feature-rich streamers
are also incomplete. Use the individual package options instead of the complete
profile if a T31 deployment must retain the vendor IMP userspace library.

The direct package options remain available for narrower experiments:

```text
BR2_PACKAGE_OPEN_TX_ISP=y
BR2_PACKAGE_OPENIMP=y
BR2_PACKAGE_INGENIC_SYSTEM_LIBS_NEO=y
BR2_PACKAGE_INGENIC_SYSTEM_LIBS_NEO_LIBALOG=y
BR2_PACKAGE_INGENIC_SYSTEM_LIBS_NEO_LIBSYSUTILS=y
BR2_PACKAGE_LIBAUDIOPROCESS_NEO=y
```

The open driver is installed as `tx-isp-<soc>.ko`, preserving the module name
expected by the SDK sensor drivers and `/etc/modules.d/20-isp`. OpenIMP and the
neo libraries are installed to staging before consumers link, and target
finalization preserves the selected replacements in the root filesystem.

This profile is experimental. Upstream reports working streams on supported
targets, but image tuning, sensor coverage, WDR, flip, exposure range, and
OEM-equivalent image quality remain incomplete.
