# CLI reference

`bin/thingino-arch` is a Ruby command-line tool with no external gem
dependencies.

```sh
bin/thingino-arch <command> [options]
```

Commands:

- `index`
- `impact`
- `verify`
- `check`
- `packet`
- `version`
- `help`

## Common behavior

### Repository selection

Every command accepts `--repo PATH`. If it is omitted, the tool uses
`$THINGINO_REPO`; if that is unset, it uses the current directory.

The path must be a Thingino firmware tree: it must contain `thingino.mk` and a
`package/` directory. Otherwise the command exits with an error.

### Git ranges

`impact`, `check`, and `packet` accept `--from REF` and `--to REF`. The default
is `HEAD~1` to `HEAD`.

For a PR, the usual range is the base branch to the PR head:

```sh
--from origin/master --to origin/pr-branch
```

or, in CI, the base branch to the PR SHA.

If `--files path/a,path/b` is supplied, the tool uses that exact changed-file
list instead of asking Git for a diff. The packet still uses `--from` and
`--to` for the displayed diff, so provide both when generating a packet.

### Formats

`impact` and `check` accept `--format json` or `--format text`. The default is
`text`. `index` always emits JSON. `packet` always emits Markdown.

### Exit codes

| Code | Meaning |
| --- | --- |
| 0 | Success; for `check`, no new errors |
| 1 | `check` found new errors, or new warnings with `--strict` |
| 2 | Usage error or invalid option |

`check` warnings and info findings do not fail a run unless `--strict` is set.

## index

Builds the architecture index and writes it as JSON.

```sh
bin/thingino-arch index --repo PATH [--output FILE]
```

Options:

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout |
| `--output FILE` | Write JSON to a file instead of stdout |

Without `--output`, the JSON is written to stdout. Progress and summary
messages go to stderr.

The index contains:

- `packages`: package directory, `.mk` files, Kconfig files, hashes, patches,
  plugin files, init files, variable prefix, version, site, site method,
  license, dependencies, remote/local state, symbols, main symbols, module
  metadata;
- `config.symbols`: every Thingino Kconfig symbol, defining file, package,
  selects, depends, defaults;
- `config.sources`: Kconfig `source` edges and their normalized targets;
- `config.choices`: choice blocks, alternatives, and defaults;
- `config.reachable_files`: Kconfig files reachable from top-level entry
  points;
- `wifi.drivers`: registered driver symbols, package, module, interface,
  module name, module options;
- `qemu_profiles`: test profiles from `configs/cameras-testing/*/qemu-test.json`
  with SoC, family, capabilities, network backend, and manifest path;
- `soc.models` and `soc.families`: model-to-family mapping, family file,
  architecture, models;
- `kernels`: vendor kernel maps;
- `fragments`: fragment name, path, symbols;
- `cameras`: profile id, group, directory, defconfig, effective symbols,
  fragments, flash size, SoC model/family/vendor, sensors, WiFi symbols,
  selected packages, `thingino.json` presence and content, `.dts` presence;
- `init_scripts`: path, package, basename, START/STOP/PROVIDES/REQUIRES/USE;
- `plugins`: manifest path, package, name, label, API version, pages, CGI
  endpoints, feature flags, parse errors;
- `reverse`: cameras by package, family, vendor, fragment, and WiFi symbol,
  plus QEMU profiles by family;
- `profiles_without_defconfig`, `stats`, `head`, `generated_at`.

Examples:

```sh
bin/thingino-arch index --repo ../firmware/master --output out/index.json
bin/thingino-arch index --repo ../firmware/master | ruby -rjson -e 'puts JSON.parse(STDIN.read)["stats"]'
```

## impact

Maps a change to packages, camera profiles, SoC families, fragments, plugins,
init scripts, and tooling.

```sh
bin/thingino-arch impact \
  --repo PATH \
  [--from REF] [--to REF] \
  [--files LIST] \
  [--format json|text] \
  [--output FILE]
```

Options:

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout |
| `--from REF` | Base ref; default `HEAD~1` |
| `--to REF` | Head ref; default `HEAD` |
| `--files LIST` | Comma-separated changed files, instead of a Git range |
| `--format json\|text` | Output format; default `text` |
| `--output FILE` | Write output to a file |

Text output is a summary with the affected profile list, capped at 60 rows.
JSON output contains:

- `changed_files`;
- `entities`: packages, cameras, fragments, SoC families, kernels, plugins,
  init scripts, tooling, other;
- `affected_cameras`: id, group, name, SoC family, sensors, WiFi symbols,
  reasons;
- `counts`;
- `global`: whether the change was treated as broad/global.

Mapping rules:

| Changed path | Impact |
| --- | --- |
| `package/<name>/...` | That package; cameras selecting it; its plugins and init scripts |
| `package/all-patches/...` | Shared patch store; treated as broad |
| `configs/cameras*/<profile>/...` | That camera profile |
| `configs/fragments/<name>.fragment` | Cameras using that fragment |
| `configs/fragments/toolchain/...` | All cameras |
| `configs/fragments/uboot/...` | All cameras |
| `soc/<vendor>/<family>.mk` | Cameras in that SoC family |
| `kernels/<vendor>.mk` | Cameras using that vendor |
| `overlay/...` | All cameras |
| `Config.in`, `Config.soc.in`, `Config.sensor.in`, `thingino.mk`, `Makefile*` | All cameras |
| `scripts/`, `docs/`, `.github/` | Tooling, not camera impact |
| Other `configs/...` | All cameras |

The index resolves Kconfig `select` edges, top-level default-`y` symbols, and
choice defaults. A camera that does not explicitly select a streamer still
resolves to the default streamer, and a camera that does not list `thingino-webui`
still gets it through the system-package selection.

Example:

```sh
bin/thingino-arch impact \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --format json
```

## verify

Builds a QEMU verification plan from the change impact.

```sh
bin/thingino-arch verify \
  --repo PATH \
  [--from REF] [--to REF] \
  [--files LIST] \
  [--format json|text|shell] \
  [--only SUITES] \
  [--max-profiles N] \
  [--full] \
  [--dispatch] [--ref REF] [--runner-arch ARCH] \
  [--github-repo OWNER/REPO] [--workflow FILE] \
  [--output FILE]
```

Options:

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout |
| `--from REF` | Base ref; default `HEAD~1` |
| `--to REF` | Head ref; default `HEAD` |
| `--files LIST` | Comma-separated changed files, instead of a Git range |
| `--format json\|text\|shell` | Output format; default `text` |
| `--only SUITES` | Override the optional QEMU suite list |
| `--max-profiles N` | Maximum profiles across families; default 4 |
| `--full` | Use all affected families and run full suites |
| `--dispatch` | Dispatch the native `qemu-test.yaml` workflow |
| `--ref REF` | Branch or tag to dispatch on; defaults to the current branch |
| `--runner-arch ARCH` | Build architecture for the native workflow; default `x86_64` |
| `--github-repo OWNER/REPO` | Override the repository derived from `origin` |
| `--workflow FILE` | Workflow file to dispatch; default `qemu-test.yaml` |
| `--output FILE` | Write the plan to a file |

The plan selects QEMU profiles from `configs/cameras-testing/*/qemu-test.json`
by affected SoC family, then chooses capabilities for the change:

- WebUI/plugin changes prefer wired profiles and `webui`, `playwright`,
  `services`, and `health`;
- WiFi changes prefer WiFi-capable profiles and `linkflap`, `health`;
- ONVIF/streamer changes prefer wired profiles and `onvif`, `webui`,
  `services`, `health`;
- USB changes prefer `usb_direct` or `usb_direct_client` profiles;
- network/init changes prefer wired profiles and `dns`, `ipv6`, `services`,
  `linkflap`, `health`;
- overlay/sysupgrade/persistence changes add `persist` and `--reboot-test`.

Broad changes, including `impact.global` and changes affecting at least half
of the camera profiles, use T31 and T41 as representative families. Use
`--full` to plan every affected family instead.

The plan contains, per profile:

- the `make` build command;
- the `scripts/qemu-test/run.sh` command;
- the selected optional suites and any flags;
- whether the backend requires `sudo` and `/dev/net/tun`.

`--format shell` emits local build and run commands. `verify` does not build or
boot anything itself.

`--dispatch` runs the native firmware workflow instead:

```sh
gh workflow run qemu-test.yaml \
  -R themactep/thingino-firmware \
  --ref <branch> \
  -f "profiles=qemu_t31x_ethwifi qemu_t41nq" \
  -f runner_arch=x86_64
```

The native workflow runs the full QEMU suite. It does not accept `--only`
suite selection, so `--dispatch` and `--only` are mutually exclusive.

Dispatching requires `gh`, a GitHub remote named `origin`, and a branch ref.
For a fork PR, dispatch on a branch in the base repository; `workflow_dispatch`
cannot target a fork branch directly.

Example:

```sh
bin/thingino-arch verify \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --max-profiles 2

bin/thingino-arch verify \
  --repo ../firmware/master \
  --files package/thingino-webui/files/www/x/reboot.cgi \
  --format shell
```

## check

Runs deterministic structural checks.

```sh
bin/thingino-arch check \
  --repo PATH \
  [--from REF] [--to REF] \
  [--files LIST] \
  [--changed] \
  [--baseline FILE] \
  [--write-baseline [FILE]] \
  [--strict] \
  [--format json|text]
```

Options:

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout |
| `--from REF` | Base ref; default `HEAD~1` |
| `--to REF` | Head ref; default `HEAD` |
| `--files LIST` | Comma-separated changed files, instead of a Git range |
| `--changed` | Report only findings in the changed scope |
| `--baseline FILE` | Baseline findings; default `.thingino-arch/baseline.json` |
| `--write-baseline [FILE]` | Write current findings as the baseline and exit 0 |
| `--strict` | Fail on warnings as well as errors |
| `--format json\|text` | Output format; default `text` |

Baseline behavior:

- A finding fingerprint is a SHA-256 of the check id, path, entity, and
  message.
- `--baseline` suppresses findings whose fingerprints are in the file.
- If the default baseline path does not exist, the baseline is empty.
- `--write-baseline` writes all current findings and exits 0. It does not
  report them as new.
- `--changed` first applies the baseline, then keeps only findings whose path
  or entity is in the changed scope. A change to a package includes findings
  on files under that package; a camera change includes findings on that
  camera profile.
- `--strict` only changes the exit code; it does not change the findings.

Text output:

```
ERROR [camera.unknown_soc] configs/cameras/foo/foo_defconfig: camera profile references unknown SoC model t99x
WARNING [package.missing_hash] package/foo/foo.mk: remote package foo has no hash file
Summary: 1 errors, 1 warnings, 0 info, 3 baselined
```

JSON output:

```json
{
  "findings": [
    {
      "id": "camera.unknown_soc",
      "severity": "error",
      "message": "camera profile references unknown SoC model t99x",
      "path": "configs/cameras/foo/foo_defconfig",
      "entity": "cameras/foo",
      "details": { "soc_model": "t99x" }
    }
  ],
  "summary": {
    "errors": 1,
    "warnings": 0,
    "info": 0,
    "baselined": 3,
    "total": 1
  }
}
```

Examples:

```sh
bin/thingino-arch check --repo ../firmware/master --baseline baseline.json

bin/thingino-arch check \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --changed --baseline baseline.json

bin/thingino-arch check --repo ../firmware/master --format json \
  | ruby -rjson -e 'puts JSON.parse(STDIN.read)["summary"]'

bin/thingino-arch check --repo ../firmware/master --write-baseline baseline.json
```

See [checks.md](checks.md) for the full check catalog.

## packet

Builds the architecture review packet as Markdown.

```sh
bin/thingino-arch packet \
  --repo PATH \
  [--from REF] [--to REF] \
  [--files LIST] \
  [--title TITLE] \
  [--baseline FILE] \
  [--brief FILE] \
  [--prompt FILE] \
  [--max-cameras N] \
  [--max-diff-bytes N] \
  [--all-findings] \
  [--output FILE]
```

Options:

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout |
| `--from REF` | Base ref; default `HEAD~1` |
| `--to REF` | Head ref; default `HEAD` |
| `--files LIST` | Changed-file list for impact/check filtering |
| `--title TITLE` | Change title shown in the packet |
| `--baseline FILE` | Baseline for deterministic findings; default `.thingino-arch/baseline.json` |
| `--brief FILE` | Architecture brief; default `architecture/thingino.md` |
| `--prompt FILE` | Review instructions; default `prompts/architecture-review.md` |
| `--max-cameras N` | Camera rows and camera index entries; default 40 |
| `--max-qemu-profiles N` | QEMU profiles in the verification plan; default 4 |
| `--max-diff-bytes N` | Diff cap; default 200000 |
| `--all-findings` | Include baselined findings and ignore the changed scope |
| `--output FILE` | Write the packet to a file instead of stdout |

Packet contents:

1. change summary and diff stat;
2. impact summary;
3. affected camera table;
4. affected entities;
5. deterministic findings after baseline and changed-scope filtering;
6. QEMU verification plan with build and run commands;
7. relevant index slices: packages, camera profiles, WebUI plugins, init
   scripts, WiFi drivers, SoC families, fragments;
8. architecture brief;
9. review instructions;
10. unified diff, truncated at the byte cap.

`--all-findings` is for debugging the tool or the baseline. Normal reviews
should use the baseline-filtered packet.

Example:

```sh
bin/thingino-arch packet \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --title "wifi: add ATBM6441 support" \
  --baseline baseline.json \
  --output out/packet.md
```

## version

```sh
bin/thingino-arch version
```

Prints the tool version, currently `0.1.0`.

## help

```sh
bin/thingino-arch help
```

Prints the command overview.
