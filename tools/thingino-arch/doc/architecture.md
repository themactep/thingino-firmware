# Architecture and implementation

This document explains how `thingino-arch` works internally. The Thingino
project architecture itself is described separately in
[`../architecture/thingino.md`](../architecture/thingino.md).

## Goals

The tool exists to answer four questions before a change is merged:

1. What parts of the project does this change touch?
2. Which camera profiles, SoC families, packages, fragments, plugins, and init
   scripts are affected?
3. Which structural integration points are missing or inconsistent?
4. What context does an LLM need to review the change against the global
   architecture rather than against the diff alone?

The tool is deliberately split into deterministic and judgment layers.

- Deterministic: parsing, graph construction, impact closure, invariants,
  baseline fingerprints, packet assembly.
- Judgment: deciding whether a change respects the architecture, which is the
  job of a reviewer or an LLM using the packet.

## Module layout

```
bin/thingino-arch
  -> lib/thingino_arch/cli.rb
       -> repo.rb      filesystem and Git access
       -> index.rb     source-of-truth parsing and graph construction
       -> impact.rb    changed-file -> entity -> camera closure
       -> verification.rb QEMU profile and suite selection
       -> checks.rb    deterministic invariants and baseline
       -> packet.rb    Markdown review context
```

`lib/thingino_arch.rb` requires the modules and defines the version. The tool
uses only the Ruby standard library: `json`, `set`, `open3`, `pathname`,
`optparse`, `fileutils`, `digest`, `shellwords`, and `time`.

## Data flow

```
Git diff / file list
        |
        v
      Impact  <---- Index ----> Checks
        |             |           |
        |             |           v
        |             |        Baseline
        v             v
   Verification ---> QEMU
        |
        v
      Packet  <--------+
        |
        v
  Reviewer or OCR
```

`index` is the expensive parse. `impact` and `checks` consume the same
in-memory index. `verification` maps the impact to QEMU profiles and suites.
`packet` combines the index, impact, verification, checks, architecture brief,
review prompt, and diff.

## Repo

`Repo` wraps a firmware checkout:

- validates that `thingino.mk` and `package/` exist;
- resolves paths relative to the repository root;
- provides file and directory globs with dotfile handling;
- runs Git `diff --name-only`, `diff`, and `diff --stat`;
- exposes the current HEAD.

Globs normalize absolute paths and remove duplicates. This matters because
`Dir.glob("package/*/**/*.webui.json", FNM_DOTMATCH)` can return the same file
once with a `./` segment and once without it.

## Index

`Index#build` runs in this order:

1. `parse_packages`
2. `parse_config_symbols`
3. `parse_config_sources`
4. `compute_config_reachability`
5. `attach_package_symbols`
6. `parse_wifi`
7. `parse_soc`
8. `parse_kernels`
9. `parse_fragments`
10. `parse_qemu_profiles`
11. `parse_cameras`
12. `parse_init_scripts`
13. `parse_plugins`
14. `attach_reverse_maps`

The order matters: cameras need symbols, main symbols, WiFi drivers, SoC
models, and fragments before they can resolve their effective configuration.

### Packages

Package directories are read from `package/*`, excluding `all-patches`, which
is a shared patch store rather than a package.

For each package the index records:

- `.mk` files, `Config*.in` files, hash files, patches, plugin manifests, and
  init scripts;
- Make variables for the package prefix, including version, site, site
  method, license, and dependencies;
- local/remote status;
- defined Kconfig symbols;
- main symbols;
- WiFi module metadata when applicable.

The package prefix is normally the upper-cased directory name with non-
alphanumeric characters replaced by underscores. If that prefix is not present,
the parser falls back to the first prefix that defines `_VERSION`, `_SITE`,
`_SITE_METHOD`, `_DEPENDENCIES`, or `_LICENSE`.

### Main symbols

A package can define many Kconfig symbols. Only the first symbol of each
non-`.conf`/non-`.host` Kconfig file is treated as a package-level main symbol.

This distinction prevents a sub-option with `default y` from making its
package look selected. For example, a disabled streamer package can have
enabled audio sub-options; those must not add the streamer to every camera.

The main-symbol map is also used to recognize a WiFi driver package even when
its driver symbol is not yet registered in the matrix.

### Kconfig symbols and sources

The parser reads top-level `Config*` files and `package/**/Config*` files. It
records:

- `config` and `menuconfig` symbols;
- `select` edges;
- `depends on` expressions as text;
- boolean `default y`/`default n` values;
- choice blocks, their alternatives, and their default symbol.

`source` lines are normalized. Both forms appear in the tree:

```
source "$BR2_EXTERNAL_THINGINO_PATH/package/foo/Config.in"
source "$BR2_EXTERNAL/package/foo/Config.in"
source "package/foo/Config.in"
source "Config.ingenic.in"
```

The normalizer removes the external-tree variable, strips quotes and leading
slashes, and resolves relative paths against the including file.

### Reachability

A package `Config.in` is not considered wired just because some file references
it. The parser builds a Kconfig source graph and traverses it from the
top-level entry points (files not under `package/`).

This catches an orphan chain: a Config.in sourced only by another unreachable
Config.in is still unreachable from the build.

`package.unreachable_config` is an error when a camera selects the package and
an informational finding otherwise. A dead optional package is not a build
break, but it is still useful to know that its Kconfig is invisible.

### Defaults and choices

The index does not run Kconfig. It approximates the effective configuration:

- top-level symbols with `default y` are treated as enabled;
- choice defaults are applied when the camera has not selected an alternative;
- `select` edges are followed transitively from the enabled symbols.

This resolves common cases such as:

- system packages and the WebUI being enabled by default;
- a camera that does not name a streamer getting the default streamer;
- one of several mosquitto versions being selected.

The approximation can over- or under-select when a `depends on` expression is
false or when a default is conditional. Impact analysis is therefore
conservative: a broad result is intentional.

### WiFi matrix

`package/wifi/wifi.mk` is parsed for `WIFI_ADD_DRIVER` calls. The parser
handles nested `$(...)` arguments and resolves simple variable references for
the interface.

For each driver the index records:

- the Kconfig symbol;
- the package directory;
- the module name;
- the interface value;
- the package's `*_MODULE_NAME` and `*_MODULE_OPTS`.

A camera's WiFi symbols are restricted to registered driver symbols and main
symbols of `wifi-*` packages. This excludes bus sub-options such as
`BR2_PACKAGE_WIFI_AIC8800_USB` from being mistaken for separate drivers.

### SoC, kernels, fragments

SoC files under `soc/<vendor>/*.mk` provide:

- a family;
- an architecture;
- the model list from `$(filter $(SOC_MODEL),...)`.

The index maps model to family and detects a model claimed by two families.

Kernel files under `kernels/*.mk` are indexed by vendor and the families named
in their conditions. They matter for impact: a kernel change affects the
cameras of that vendor.

Fragments under `configs/fragments/**/*.fragment` are indexed by basename.
Camera defconfigs list fragments in `# FRAG:`. Fragments are applied before the
camera defconfig, so the defconfig wins on a conflicting symbol. The index
merges fragment symbols first and the defconfig symbols second.

### Camera profiles

A camera profile is discovered from `configs/cameras*/*/*_defconfig`. The
index records:

- id as `<group>/<profile>`;
- defconfig path and name;
- declared fragments;
- effective symbols (fragments + defconfig + choice defaults);
- flash size;
- SoC model, family, vendor;
- sensors;
- WiFi driver symbols;
- selected packages via main-symbol closure;
- `thingino.json` presence and content;
- `.dts` presence;
- whether the defconfig name matches the directory name.

Camera names can collide across groups, so the key includes the group.

### Init scripts and plugins

Init scripts are read from `overlay/etc/init.d/*` and
`package/*/files/**/{S,K}[0-9]*`. The `.in` suffix is removed for the runtime
basename. START/STOP/PROVIDES/REQUIRES/USE are parsed when present.

WebUI plugins are read from `package/*/**/*.webui.json`. The parser records
name, label, API version, pages, CGI endpoints, feature flags, and parse
errors.

### QEMU profiles

QEMU test profiles are read from
`configs/cameras-testing/*/qemu-test.json`. Each profile records:

- `soc` and the resolved SoC family and vendor;
- `caps`, such as `wired`, `wifi`, `usb_direct`, or `usb_direct_client`;
- the default network backend, such as `tap`, `slirp`, or `slip`;
- the manifest path and parse error, if any.

The reverse map `qemu_profiles_by_family` connects affected SoC families to
available verification targets. Families with a QEMU machine but no test
profile are reported as skipped by `verify`.

### Reverse maps

After camera parsing, the index builds:

- package -> cameras;
- family -> cameras;
- vendor -> cameras;
- fragment -> cameras;
- WiFi symbol -> cameras.

These maps are the basis for impact and for co-selection checks (for example,
whether two plugins can be installed on the same camera).

## Impact

`Impact` classifies each changed path and adds reasons per camera.

The classifier is intentionally simple and path-based. It does not inspect
file content. The mapping table is documented in [cli.md](cli.md#impact).

Two behaviors are worth calling out:

- `package/all-patches/...` is treated as broad impact. A shared patch can
  affect every package built from that upstream tree.
- A fragment that no camera references through `# FRAG:` is treated as global.
  This covers toolchain and U-Boot fragments, which are applied implicitly.

Impact is conservative. If a change is broad, the affected camera list can
contain all 251 profiles. The packet lists the first 40 by default and reports
the remaining count.

## Checks

Checks consume the index and produce `Finding` values:

- id;
- severity (`error`, `warning`, `info`);
- message;
- path;
- entity;
- details.

Findings are sorted by severity, path, id, and message.

Co-selection checks use the camera reverse maps. A duplicate init script or
plugin name is an error only when the packages can be selected by the same
camera. If the packages are mutually exclusive in practice, the finding is
informational. This avoids flagging alternative streamers or alternative
mosquitto versions as conflicts.

See [checks.md](checks.md) for the catalog.

## Baseline

A baseline stores finding fingerprints. A fingerprint is a SHA-256 of:

```
id + "\0" + path + "\0" + entity + "\0" + message
```

The path and entity make the fingerprint stable across unrelated tree changes.
Changing the message changes the fingerprint; that is intentional when a
check's semantics change.

Baseline handling:

- `Baseline.load` returns an empty set if the file is missing or invalid.
- `Baseline.write` writes a versioned JSON object with sorted fingerprints.
- `check` filters baselined findings before applying `--changed`.
- `packet` does the same unless `--all-findings` is used.

The baseline is a snapshot, not a policy. Regenerate it only after reviewing
the findings and intentionally fixing or accepting them.

## Verification

`Verification` consumes the index and impact report and produces a QEMU plan:

- affected families come from affected camera profiles and direct SoC changes;
- broad changes use T31 and T41 as representative families unless `--full` is
  set;
- one profile is chosen per selected family, preferring capabilities required
  by the change and then the richer profile/backend;
- optional suites are selected from changed paths and packages;
- the plan records build and run commands, required privileges, skipped
  families, and notes.

The class does not build or boot anything. `verify --format shell` writes local
commands; `verify --dispatch` runs the native `qemu-test.yaml` workflow through
`gh`.

## Packet

`Packet` renders Markdown. It includes:

- repository root, head, title, changed-file count, affected-camera count;
- diff stat;
- impact summary and camera table;
- affected entities;
- QEMU verification plan with build and run commands;
- deterministic findings, capped at 80 rows in the packet;
- index slices for affected packages, cameras, plugins, init scripts, WiFi
  drivers, SoC families, and fragments;
- the full architecture brief;
- the review prompt;
- the diff, capped at `--max-diff-bytes` (default 200000).

Index slices are JSON blocks. They are deliberately limited to affected
entities so the packet remains usable in a context window. A global change
still produces a large impact table; the camera index slice is capped by
`--max-cameras`.

## Design decisions

### Static parsing, not Kconfig evaluation

Running Kconfig for every camera profile would be accurate but expensive and
would require a Buildroot toolchain. A static parse is fast enough for a PR
job and good enough for structural impact, with documented approximation.

### Conservative impact

A missed affected profile is worse than a noisy impact list. When the graph is
ambiguous, the tool prefers to include more cameras and let the reviewer
narrow it with evidence.

### QEMU is the runtime oracle

QEMU boots the same image that would be flashed and exercises boot, services,
networking, WebUI, ONVIF, USB, GPIO, and emulated sensors. It is the verification
executor; the static index selects what to test. A green QEMU run narrows the
remaining risk to real hardware, RF, power, thermal, and unmodeled peripherals.

### Deterministic checks in scripts

The LLM is not asked to decide whether a package is sourced, whether a WiFi
driver is registered, or whether two init scripts share a name. Those are exact
checks. The LLM is reserved for cross-file and cross-layer judgment.

### No model fine-tuning

The project architecture changes frequently. A fine-tuned model cannot cite
the current files, drifts after every restructuring, and is not auditable.
A generated index plus a maintained brief is current, reviewable, and
diffable.

### No fork of open-code-review

OCR provides file selection, rules, repository tools, delegation, and a GitHub
Action. Forcing a fork to add Thingino knowledge would create a maintenance
burden. The rule pack and architecture brief supply the project context
instead.

## Limitations

- Conditional Kconfig defaults and dependencies are approximated.
- Camera selection is computed from main symbols, not a full Kconfig run.
- Impact is path-based and conservative.
- The tool itself does not build or boot the image; `verify` emits a plan or
dispatches the native QEMU workflow.
- QEMU covers emulated Ingenic behavior, not real hardware, RF, power, thermal,
  or unmodeled peripherals.
- Patch content is reviewed as text; the patched source is not present.
- Cross-repo impact requires the component checkouts.
- The OCR review is per-group and constrained to the files in the group.

See [troubleshooting.md](troubleshooting.md) for symptoms and workarounds.
