# Ingenic SDK versions

The Ingenic media SDK is split across three git trees, and the "SDK version"
string selects a prebuilt-library directory inside the `ingenic-lib` blob
repository. This document records the mapping.

## Source trees

| Tree | Repo | Purpose |
| --- | --- | --- |
| kernel | `github.com/gtxaspec/thingino-linux` | vendor Linux, branch per SoC/kernel |
| SDK (drivers + IQ) | `github.com/themactep/ingenic-sdk` | `overrides/ingenic-sdk/` |
| libimp blobs | `github.com/gtxaspec/ingenic-lib` | `overrides/`-linked `libimp.so` etc. |

Kernel branch selection lives in `thingino.mk`:

| SoC family | Kernel 3.10.14 | Kernel 4.4.94 |
| --- | --- | --- |
| t10/t20/t21/t30 | `ingenic-t31` (shared) | — |
| t23 | `ingenic-t31` | `ingenic-t23-4.4.94` |
| t31 | `ingenic-t31` | `ingenic-t31-4.4.94` |
| t32 | `ingenic-t32` | `ingenic-t32-4.4.94` |
| t33 | `ingenic-t31` (shared) | — |
| c100 | `ingenic-t31` | `ingenic-t31-4.4.94` |
| t40 | — | `ingenic-t40` |
| t41 | `ingenic-t41-3.10.14` | `ingenic-t41-4.4.94` |
| a1 | — | `ingenic-a1` |

The `7.1-rc1` line maps to `ingenic-7.1-rc1`.

## SoC family / arch

From `soc/ingenic/*.mk`:

| Family | Arch | Models |
| --- | --- | --- |
| t10 | xburst1 | t10l t10n t10a |
| t20 | xburst1 | t20l t20n t20x t20z |
| t21 | xburst1 | t21l t21n t21x t21zn t21zl |
| t23 | xburst1 | t23n t23dl t23zn |
| t30 | xburst1 | t30l t30n t30x t30a |
| t31 | xburst1 | t31l t31lc t31n t31x t31a t31al t31zl t31zx |
| t32 | xburst1 | t32lq t32nq t32vn |
| t33 | xburst1 | t33dl t33l t33lq t33n t33vl t33vn t33zl t33zn |
| c100 | xburst1 | c100 |
| t40 | xburst2 | t40n t40nn t40xp t40a |
| t41 | xburst2 | t41lq t41nq t41zl t41zn t41zx t41a |
| a1 | xburst2 | a1n a1nt a1x a1l a1a |

Platform codenames (from `docs/dev/glossary.md`): Immortal = T20, Archon = T31.

## SDK version matrix

`package/ingenic-lib/ingenic-lib.mk` maps `SOC_FAMILY` + `KERNEL_VERSION` to
the blob directory `SDK_LIB_DIR`:

```make
SDK_LIB_DIR = $(@D)/<FAMILY>/lib/<SDK_VERSION>/<libc>/<gcc>
```

| Family | SDK_VERSION | GCC | Notes |
| --- | --- | --- | --- |
| a1 | 1.7.0 | 7.2.0 | no libsysutils |
| c100 | 1.1.6 (3.10) / 2.1.0 (4.4) | 5.4.0 | |
| t10 | 3.12.0 | 4.7.2 | |
| t20 | 3.12.0 | 4.7.2 | |
| t21 | 1.0.33 | 4.7.2 | |
| t23 | 1.3.0 | 5.4.0 | |
| t30 | 1.0.5 | 4.7.2 | only libimp linking libstdc++ |
| t31 | 1.1.6 (3.10) / 1.1.5.2 (4.4) | 5.4.0 | |
| t32 | 1.0.6 | 5.4.0 | |
| t40 | 1.3.1 | 7.2.0 | |
| t41 | 1.2.6 | 7.2.0 | |

libc is `uclibc` by default, `glibc` when `BR2_TOOLCHAIN_USES_GLIBC=y`.
`libalog` is pulled from the T31/1.1.6 uclibc tree when a family's own
`libalog` is absent.

## SDK driver tree layout

`overrides/ingenic-sdk/` is organized by subsystem, not by kernel version;
per-kernel differences are handled in the sources (`CONFIG_KERNEL_3_10` /
`CONFIG_KERNEL_4_4_94` guards) and in the top-level `Kbuild`:

```text
common/isp/<soc>/         tx-isp driver (open source only for t10/t20/t30)
common/sensor/<soc>/      sensor drivers, one .c per model
common/audio/ avpu/ fb/ ipu/ video/ aip/ misc/
sdk/<soc>/                prebuilt firmware blobs, identity in the filename
sensor-iq/<soc>/          per-sensor tuning binaries (.bin)
config/ docs/ include/ sinfo/
```

Full open ISP driver source exists only for t10/t20/t30 (29, 29, and 33 `.c`
files). The other SoCs (t21/t23/t31/t40/t41/c100) ship a thin wrapper
(`tx-isp-module.c` calling `tx_isp_init()` from a prebuilt object in
`sdk/<soc>/`) plus headers and Kbuild.

## Sensor drivers and IQ tuning

- **Drivers**: `common/sensor/<soc>/<model>.c` builds
  `sensor_<model>_<soc>.ko`, loaded from `/etc/modules.d/30-sensor`.
- **IQ tuning**: `sensor-iq/<soc>/<sensor>.bin` installs to
  `/usr/share/sensor/`. Naming differs by generation:
  - old t10/t20/t30: `<sensor>.bin`
  - newer families: `<sensor>-<soc>.bin`
- `BR2_SENSOR_ISP_FW` selects IQ from `sensor-iq/<soc>/<version>/` when such
  a directory exists (it defaults to `2.20` for t23); the current tree ships
  no versioned sets, so the flat per-soc file is used.
- Per-camera overrides: `BR2_SENSOR_1_IQ_FILE` / `BR2_SENSOR_2_IQ_FILE`.
- Multi-sensor builds flip `CONFIG_MULTI_SENSOR=1` and strip the `s0`/`s1`
  suffix from the model name.

## Related

- [Ingenic media stack](ingenic-media-stack.md) — stack overview
- [TX-ISP pipeline](tx-isp-pipeline.md) — the driver built from these sources
- [libimp userspace](libimp-userspace.md) — the blobs selected by the
  SDK_VERSION above
