# Thingino firmware architecture brief

This brief is for structural review of a Thingino change. It describes the
layers, the source-of-truth files, the integration recipes, and the invariants
that a diff can break. It is not a style guide.

## 1. What the tree is

Thingino is a Buildroot external tree plus a camera-profile build layer. A
build selects a camera, resolves its SoC family and kernel, merges fragments
and the camera defconfig into `.config`, then lets Buildroot build the selected
packages into a firmware image.

The important consequence for review: a change is rarely local. A package
needs Kconfig wiring, a camera needs a complete profile, a WiFi driver needs a
matrix entry, and a component bump may require a matching change in another
repository.

## 2. Build chain

1. `Makefile` selects the camera group and profile.
2. `thingino.mk` resolves:
   - `SOC_VENDOR`, `SOC_MODEL`, `SOC_FAMILY`, `SOC_ARCH`, `SOC_RAM_MB`;
   - `KERNEL_VERSION`, `KERNEL_BRANCH`, `KERNEL_SITE`, `KERNEL_HASH`;
   - up to four image sensors and their parameters;
   - the per-camera device tree destination.
3. `.config` is assembled in this order:
   - toolchain fragment;
   - `# FRAG:` fragments from the camera defconfig;
   - the camera defconfig itself;
   - SoC-derived values;
   - optional camera overlay;
   - user fragments;
   - the U-Boot version fragment last.
   The camera defconfig is appended after fragments, so it wins on conflicts.
4. `external.mk` includes `package/*/*.mk`, except `*-override.mk` fragments.
5. `Config.in` and the package `Config*.in` files define the Kconfig surface.
6. Buildroot installs packages, overlays, init scripts, webui files, and the
   image payload.

Review the resolved behavior, not just the line that changed.

## 3. Source-of-truth files

| Concern | Source |
| --- | --- |
| SoC model to family, arch, RAM, U-Boot board | `soc/<vendor>/*.mk` |
| Kernel version to branch | `kernels/<vendor>.mk` |
| Camera profile | `configs/cameras*/*/*_defconfig` |
| Shared camera defaults | `configs/fragments/**/*.fragment` |
| Camera runtime metadata | `configs/cameras*/<profile>/thingino.json` |
| Optional per-camera device tree | `configs/cameras*/<profile>/*.dts` |
| Package definition | `package/<name>/<name>.mk` |
| Package Kconfig | `package/<name>/Config*.in` |
| Package integrity | `package/<name>/*.hash` |
| Package payload | `package/<name>/files/` |
| Package patches | `package/<name>/*.patch` |
| Shared upstream patches | `package/all-patches/` |
| Package selection | `Config.in`, `configs/fragments`, defconfigs |
| WiFi driver matrix | `package/wifi/Config.in`, `package/wifi/wifi.mk` |
| WebUI plugins | `package/*/files/**/*.webui.json`, `assemble_plugins.py` |
| Root filesystem overlay | `overlay/` |
| Init order | `overlay/etc/init.d/`, `package/*/files/S*` |
| Component pins | `_SITE`, `_VERSION`, `_SITE_METHOD` in package `.mk` |
| Package inventory | `docs/dev/packages.md` (generated) |

## 4. Layers and boundaries

- SoC and kernel: `soc/`, `kernels/`, kernel patches, U-Boot.
- Vendor libraries and drivers: `package/ingenic-*`, `package/open-tx-isp`,
  `package/openimp`, `package/wifi-*`.
- Userspace services: `thingino-*` packages, streamers (`prudynt-t`,
  `thingino-raptor`, `strero`, `timps`), ONVIF, web server, MQTT.
- Web UI: core `thingino-webui` plus plugin manifests from optional packages.
- Image and update: `thingino-core`, `thingino-system`, `thingino-sysupgrade`,
  `thingino-pkg`, `Makefile.ota`, image assembly.
- Development and build: `scripts/`, `docs/`, `.github/`, `buildroot/`.

A change that crosses a boundary must update both sides of the contract.

## 5. Integration recipes

### Add a package

- `package/<name>/<name>.mk` exists with `_VERSION`, `_SITE`,
  `_SITE_METHOD`, `_LICENSE`, dependencies, and install rules.
- `package/<name>/Config.in` exists and is sourced from a reachable Kconfig
  file.
- A `.hash` exists for remote sources, or the absence is intentional.
- The package is selected by a defconfig or fragment, not only by a hidden
  `select`.
- Init scripts, webui manifest, bundle definition, docs, and tests are updated
  when the package needs them.
- `package/all-patches` is not used as a substitute for package-local patches.

### Add a WiFi driver

- Driver package exists and defines its main `BR2_PACKAGE_WIFI_*` symbol.
- `package/wifi/Config.in` sources the driver Config.in.
- `package/wifi/wifi.mk` has a `WIFI_ADD_DRIVER` entry with the symbol, module
  name, and interface.
- The driver package sets `*_MODULE_NAME` and, when needed, `*_MODULE_OPTS`.
- The interface matches the package's bus (USB, SDIO, PCIe) and SoC family.
- Camera defconfigs select exactly one driver.
- Init templates (`S36wireless.in`, `S38wpa_supplicant.in`, `wlan.in`) and
  firmware files still work for the new interface.

### Add a camera profile

- Directory name, defconfig name, and documented model naming agree.
- Defconfig declares SoC model, sensor name(s), WiFi driver, flash size, and
  the correct `# FRAG:` set.
- `thingino.json` exists for production profiles and its GPIO/motor data
  agrees with the defconfig.
- Optional `.dts` is valid for the SoC family's kernel tree.
- SoC family, kernel version, sensor, WiFi interface, and flash type are a
  supported combination.
- Docs, images, and any per-camera overrides are updated.

### Add a service

- Init script is installed by the owning package, has a unique `S`/`K` name,
  and starts after its dependencies.
- `start`, `stop`, `restart`, and status behavior are idempotent.
- Configuration is read from `/etc/thingino.json` or the package's own config,
  not from an ad-hoc path.
- The package is selected by the profiles that need it, and the service does
  not start on profiles where the hardware is absent.

### Add a WebUI plugin

- The plugin package ships `*.webui.json` and all files it references.
- The manifest declares name, pages, CGI endpoints, nav contributions, and
  feature flags.
- Page and CGI paths do not collide with another plugin that can be selected
  by the same camera.
- Core WebUI files are not edited for a plugin; the assembly script does the
  integration.
- The feature flag is set by the runtime configuration only when the package
  is actually installed.

### Add or bump a patch/component

- The package version, site, hash, and patch set agree.
- A patch applies to the declared version without fuzz.
- A component bump updates the firmware pin, any local patches, API users, and
  docs in the same change.
- A T32-only or SoC-specific change is checked against T40/T41/A1 and the
  other families that build the same component.

## 6. Structural invariants

- Every package `Config.in` is sourced from a reachable Kconfig file.
- Every camera-selected `BR2_PACKAGE_*` symbol is defined.
- Every camera selects at most one WiFi driver, and that driver is registered
  in `package/wifi/wifi.mk`.
- Every registered WiFi driver maps to a package and has a module name.
- Every camera has a known SoC model and a complete profile.
- Every SoC model belongs to exactly one family.
- Init script basenames are unique for packages that can be co-selected.
- WebUI plugin names, pages, and CGI endpoints are unique for packages that
  can be co-selected.
- A package that is selected by a camera is not invisible to Kconfig.
- Cross-repo pins and local patches describe the same component state.

## 7. Known traps

- `.in` is overloaded. `package/<name>/files/*.in` is usually a shell
  template; `Config*.in` is Kconfig.
- Many init scripts and helpers have no extension (`S59motor`, `tell`,
  `wlan`). Do not assume a file is not code because it has no suffix.
- Fragments are applied before the camera defconfig. The defconfig wins on a
  conflicting symbol.
- Choice defaults matter. A camera that does not name a streamer still gets
  the default choice; review the effective selection, not only explicit lines.
- `$(BR2_EXTERNAL_THINGINO_PATH)` and `$BR2_EXTERNAL_THINGINO_PATH` both appear
  in source paths.
- Per-camera overrides can be split across the defconfig, `thingino.json`,
  `.dts`, an optional `overlay/` directory, and package-specific JSON such as
  `prudynt.json`.
- `package/all-patches` is a shared patch store; a change there can affect
  many packages and every camera built from them.
- The Ingenic SDK ships more than one kernel tree (for example 3.10.14 and
  4.4.94) and alternate motor drivers (`misc/motor`, `misc/ms419xx`). A patch
  that fixes one copy is incomplete unless every copy is checked and the
  unaffected ones are explained.
- `docs/dev/packages.md` is generated; do not treat it as the source of truth.
- `scripts/check-do-not-edit.sh` and the manifest in `scripts/do-not-edit.txt`
  protect generated or externally owned paths.
- Existing CI already checks formatting, shellcheck, shfmt, Prettier,
  defconfig sorting, webui manifests, and TZ strings. Do not repeat those
  findings.

## 8. Review behavior

A structural review should:

- classify the change (package, driver, camera, service, plugin, patch,
  component bump, build system, docs/tooling);
- follow the relevant integration recipe and report missing steps;
- use the generated architecture index for package, WiFi, camera, fragment,
  plugin, and init relationships;
- compute the affected camera profiles and, when useful, the affected SoC
  families or component repositories;
- report only issues that are structural, cross-file, cross-layer, or
  cross-repo, and that the author can act on;
- cite the file and line or index entry that proves the issue;
- separate confirmed findings from items that need a build, runtime test, or
  hardware check;
- ignore style, formatting, naming preferences, and issues already covered by
  the deterministic checks.

The reviewer must not invent hardware behavior. It may say "verify on T41
hardware" or "build this profile", but it must not claim a pin, sensor, or
boot behavior is correct without evidence in the tree.

## 9. Runtime verification

Thingino has a QEMU test suite that boots the same firmware image and exercises
boot, services, networking, WiFi portal, WebUI, ONVIF, USB, GPIO, and emulated
sensors on supported Ingenic SoCs. Use the review packet's verification plan
to identify the profiles and suites for the affected families.

QEMU is runtime evidence, not an architecture decision. A green run narrows the
remaining risk to real hardware, RF, power, thermal, and unmodeled peripherals.
If the plan says a family has no QEMU profile, or the change needs hardware
behavior that the suite does not model, report it as verification needed.

## 10. Cross-repo context

The firmware tree pins component sources rather than vendoring them. A
firmware change may require a matching change in `prudynt-t`, `open-tx-isp`,
`openimp`, `thingino-linux`, `thingino-uboot`, `thingino-webui`, or a sensor
repository.

If those repositories are not available in the review workspace, treat
cross-repo impact as unverified and list it under verification needed. Do not
assume the pinned component already has the new API, symbol, or configuration.

For `ingenic-sdk` changes, check the same code in every kernel tree and in
alternate drivers. For example, a `misc/motor` fix may also belong in
`misc/ms419xx` and in both 3.10.14 and 4.4.94.

## 11. Output contract

For each finding, report:

- severity: critical, high, medium, low;
- category: integration, layering, cross-repo, build-break, configuration,
  security, maintainability;
- the path and line that proves the issue;
- the affected package, camera profile, SoC family, or component;
- the missing or inconsistent integration point;
- a concrete verification step when the issue cannot be proven from the tree.

If a deterministic check already reports the issue, reference it and do not
duplicate it as a prose finding.
