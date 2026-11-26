# Structural checks

`thingino-arch check` runs deterministic checks against the index. This
document lists every check, its severity, its trigger, and what it means.

Severities:

- `error`: a structural defect likely to break a build or a profile contract.
  A new error fails `check` and the CI job.
- `warning`: a likely defect or an incomplete integration that should be
  reviewed. Warnings do not fail unless `--strict` is used.
- `info`: a latent issue, a dead path, or a mutually exclusive alternative.
  Informational findings do not fail.

A finding has a stable fingerprint. See [architecture.md](architecture.md#baseline)
for the fingerprint and baseline design.

## Check catalog

### package.unreachable_config

| Field | Value |
| --- | --- |
| Severity | `error` if a camera selects the package, otherwise `info` |
| Path | The package's `Config.in` |
| Entity | Package name |

The package's Kconfig file is not reachable from the top-level Kconfig entry
points. The source graph is traversed from top-level `Config*` files; a file
sourced only by another unreachable file is still unreachable.

A selected package with an unreachable Config.in is a build break: its symbols
are not defined when a defconfig selects them. An unselected package with an
unreachable Config.in is dead code.

### package.missing_hash

| Field | Value |
| --- | --- |
| Severity | `warning` |
| Path | The package's primary `.mk` file |
| Entity | Package name |

The package has a remote site (`https`, `git`, `wget`, `svn`, or `hg`) but no
`*.hash` file in its directory. Local packages and Buildroot override
directories are excluded by the remote check.

Some Thingino packages intentionally have no hash. Review the exception; do
not add a hash for a generated or moving source without understanding the
package.

### camera.defconfig_name_mismatch

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id (`group/profile`) |

The defconfig basename does not match the profile directory name. Thingino
expects `configs/cameras*/<profile>/<profile>_defconfig`.

### camera.missing_soc

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id |

The camera declares neither `BR2_INGENIC_SOC_MODEL` nor
`BR2_SIGMASTAR_SOC_MODEL` after fragment and defconfig merging.

### camera.unknown_soc

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id |

The declared SoC model is not claimed by any file under `soc/<vendor>/*.mk`.
The camera cannot resolve a family, architecture, RAM size, or U-Boot board.

### camera.missing_json

| Field | Value |
| --- | --- |
| Severity | `warning` |
| Path | Camera defconfig |
| Entity | Camera id |

A production profile in `configs/cameras` or `configs/cameras-exp` has no
`thingino.json`. Test and QEMU profiles are excluded because they often omit
runtime metadata intentionally.

### camera.multiple_wifi

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id |

The camera selects more than one registered WiFi driver. `package/wifi/wifi.mk`
rejects multiple drivers at build time; this check reports it earlier, with the
symbol list.

Bus sub-options such as `BR2_PACKAGE_WIFI_AIC8800_USB` are not counted as
separate drivers.

### camera.unknown_wifi_symbol

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id |

The camera selects a WiFi symbol that is not defined in the external Kconfig
tree.

### camera.unregistered_wifi_driver

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Camera defconfig |
| Entity | Camera id |

The camera selects a main symbol of a `wifi-*` package, but the symbol has no
`WIFI_ADD_DRIVER` entry in `package/wifi/wifi.mk`. The driver is invisible to
the WiFi framework.

### wifi.undefined_symbol

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | `package/wifi/wifi.mk` |
| Entity | Driver symbol |

`WIFI_ADD_DRIVER` registers a symbol that is not defined in the external
Kconfig tree.

### wifi.missing_package

| Field | Value |
| --- | --- |
| Severity | `warning` |
| Path | `package/wifi/wifi.mk` |
| Entity | Driver symbol |

The driver symbol does not map to a package directory. The parser infers a
`wifi-<suffix>` package when possible; this finding means the inference also
failed.

### wifi.missing_module_name

| Field | Value |
| --- | --- |
| Severity | `warning` |
| Path | Driver package Config.in or `.mk` |
| Entity | Driver package |

The driver package does not define a `*_MODULE_NAME`. The WiFi framework uses
this value to load and document the module. Some legacy drivers may rely on an
external mechanism; verify before changing.

### wifi.unresolved_interface

| Field | Value |
| --- | --- |
| Severity | `info` |
| Path | `package/wifi/wifi.mk` |
| Entity | Driver symbol |

The driver's interface is empty or is a dynamic `$(if ...)` expression that the
static parser cannot resolve. This is not necessarily a defect; it means the
index cannot use the interface for further analysis.

### plugin.invalid_json

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Plugin manifest |
| Entity | Package |

The `.webui.json` manifest cannot be parsed.

### plugin.missing_name

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Plugin manifest |
| Entity | Package |

The manifest has no `name` field.

### plugin.duplicate_name

| Field | Value |
| --- | --- |
| Severity | `error` if the packages can be co-selected, otherwise `info` |
| Path | Plugin manifest |
| Entity | Plugin name |

Two plugin manifests declare the same name. If no camera can select both
packages, the conflict is latent and informational.

Co-selection is determined by intersecting the camera sets of the two package
directories.

### plugin.duplicate_page

| Field | Value |
| --- | --- |
| Severity | `error` if the packages can be co-selected, otherwise `info` |
| Path | Plugin manifest |
| Entity | Plugin name |

Two plugins claim the same page. Plugins with different streamer feature flags
are treated as mutually exclusive; this mirrors the WebUI assembly script.

### plugin.duplicate_cgi

| Field | Value |
| --- | --- |
| Severity | `warning` if the packages can be co-selected, otherwise `info` |
| Path | Plugin manifest |
| Entity | Plugin name |

Two plugins claim the same CGI endpoint. The WebUI assembly script warns about
CGI conflicts rather than failing, so this check follows that severity.

### init.duplicate_basename

| Field | Value |
| --- | --- |
| Severity | `warning` if the packages can be co-selected, otherwise `info` |
| Path | First init script with that basename |
| Entity | Init script basename |

Two packages install an init script with the same runtime basename. Known
mutually exclusive alternatives (streamers, mosquitto versions, go2rtc
variants) are informational; a genuine co-selection conflict is a warning.

### config.unknown_symbol

| Field | Value |
| --- | --- |
| Severity | `warning` |
| Path | Camera defconfig or fragment |
| Entity | Camera id or fragment name |

A defconfig or fragment references a Thingino-prefixed symbol that is not
defined in the external tree. The checked prefixes are:

- `BR2_THINGINO_`
- `BR2_PACKAGE_THINGINO_`
- `BR2_PACKAGE_WIFI_`
- `BR2_INGENIC_`
- `BR2_SIGMASTAR_`
- `BR2_SENSOR_`

The check intentionally ignores Buildroot-owned symbols it cannot validate
without the Buildroot Kconfig tree.

### soc.model_conflict

| Field | Value |
| --- | --- |
| Severity | `error` |
| Path | Second SoC file that claims the model |
| Entity | SoC model |

The same `SOC_MODEL` value appears in two `soc/<vendor>/*.mk` files with
different families. The family lookup is ambiguous.

## What is not checked

The following are handled elsewhere and should not be duplicated:

- shellcheck, shfmt, and POSIX shell style;
- Prettier and JavaScript/CSS/HTML formatting;
- defconfig sorting (`scripts/sort_defconfig.py`);
- WebUI manifest syntax and assembly conflicts (`scripts/check-plugins.sh`);
- TZ string validity, do-not-edit paths, plugin contract;
- Buildroot `check-package`;
- compilation, kernel build, image assembly;
- QEMU or hardware behavior; use `thingino-arch verify` and the native QEMU workflow.

The checks are intentionally conservative. A new check should be exact enough
that a false positive is rare, or it should be informational.

## Baseline behavior

With a baseline:

```sh
bin/thingino-arch check \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --changed --baseline baseline.json
```

- existing findings are suppressed;
- `--changed` keeps findings on changed paths or entities;
- new errors exit 1;
- new warnings exit 0 unless `--strict` is used.

The current reference baseline was generated from `thingino-firmware` at
`c3cd414ff`. It contains 105 findings: 1 error, 87 warnings, and 17
informational findings. The error is
`package/ingenic-tflite-micro/Config.in` being unreachable while other
packages select `BR2_PACKAGE_INGENIC_TFLITE_MICRO`. It is a real latent wiring
issue; the baseline keeps the first CI run actionable until it is fixed.

Do not regenerate the baseline just to silence a new finding. Fix the finding,
or record a deliberate exception with a comment in the review.

## Adding a check

1. Add the logic to `lib/thingino_arch/checks.rb`.
2. Use a stable id and a stable message.
3. Pick the correct severity and path/entity.
4. Add a fixture test in `test/thingino_arch_test.rb`.
5. Run the check against the real firmware tree.
6. If the finding is intentional in the current tree, regenerate the baseline
   only after review.

Changing a check's message changes its fingerprint and causes previously
baselined findings to reappear. That is expected when the check semantics
change.
