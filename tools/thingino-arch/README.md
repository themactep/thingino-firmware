# Thingino Architect

Architecture-aware structural review tooling for the
[Thingino](https://thingino.com/) firmware tree.

The repository is `thingino-architect`; the CLI is `thingino-arch`.

`thingino-arch` reads a Thingino checkout, builds an index of the project's
build graph, maps a change to the packages, camera profiles, SoC families,
fragments, plugins, and init scripts it affects, runs deterministic structural
checks, and emits a review packet for an LLM or `open-code-review`.

It does not call an LLM itself. `open-code-review` remains the inline-comment
harness; this tool supplies the architecture context and the checks it lacks.

> This README is also installed as `tools/thingino-arch/README.md` in a
> firmware checkout. The installer (`integrate.sh`) stays in the source
> repository; rerun it from the source to update an installed copy.

## What it does

- **Index** the source of truth: packages, Kconfig, WiFi driver matrix, SoC
  and kernel maps, camera profiles, fragments, init scripts, WebUI plugins.
- **Impact** a change: map changed files to entities and camera profiles.
- **Verify** a change: choose QEMU test profiles and suites, or dispatch the
  native `qemu-test` workflow.
- **Check** structural invariants: unreachable Kconfig, missing hashes,
  unregistered WiFi drivers, incomplete camera profiles, conflicting plugins
  or init scripts, undefined symbols, SoC model conflicts.
- **Packet** the review: diff, impact, relevant index slices, findings, the
  architecture brief, and the review prompt.
- **Integrate** into the firmware repository with a baseline and CI workflows.

## Quick start

Point the tool at a Thingino firmware checkout:

```sh
bin/thingino-arch index --repo ../firmware/master --output out/index.json

bin/thingino-arch impact \
  --repo ../firmware/master \
  --from origin/master --to HEAD

bin/thingino-arch check \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --changed --baseline baseline.json

bin/thingino-arch verify \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --max-profiles 2

bin/thingino-arch verify \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --ref <branch> --dispatch

bin/thingino-arch packet \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --title "PR title" \
  --baseline baseline.json \
  --output out/packet.md
```

Feed `out/packet.md` to Kilo, another agent, or an OCR review. The packet is
self-contained and includes the architecture brief and review instructions.

## Install into the firmware repository

```sh
./integrate.sh --repo ../firmware/master
```

The installer copies the tool to `tools/thingino-arch/`, generates the initial
baseline, installs the deterministic PR workflow, and runs a smoke check. It
does not commit.

Optional flags:

```sh
./integrate.sh --repo ../firmware/master --with-ocr
./integrate.sh --repo ../firmware/master --refresh-baseline
./integrate.sh --repo ../firmware/master --dry-run
./integrate.sh --repo ../firmware/master --force
```

QEMU execution uses the native `qemu-test.yaml` workflow in the firmware
repository. See [doc/ci.md](doc/ci.md) for the workflow and dispatch details.

See [doc/integration.md](doc/integration.md) for the full lifecycle.

## Documentation

| Document | Purpose |
| --- | --- |
| [doc/README.md](doc/README.md) | Documentation index and core concepts |
| [doc/cli.md](doc/cli.md) | Command reference, options, exit codes |
| [doc/architecture.md](doc/architecture.md) | Internal design, index model, impact, packet |
| [doc/checks.md](doc/checks.md) | Structural check catalog and baseline behavior |
| [doc/ocr.md](doc/ocr.md) | OCR rule pack, delegation, evaluation |
| [doc/ci.md](doc/ci.md) | Deterministic and OCR workflows |
| [doc/integration.md](doc/integration.md) | Installer, vendoring, updates |
| [doc/development.md](doc/development.md) | Tests, linting, extension points |
| [doc/security.md](doc/security.md) | Trust boundaries and credential handling |
| [doc/troubleshooting.md](doc/troubleshooting.md) | Common failures and workarounds |

Project-specific context:

- [architecture/thingino.md](architecture/thingino.md) — Thingino build graph,
  layers, integration recipes, invariants, and traps.
- [prompts/architecture-review.md](prompts/architecture-review.md) — the
  architecture review prompt and output contract.
- [rules/thingino-review.json](rules/thingino-review.json) — OCR path rules and
  scope.

## Layout

```
bin/thingino-arch              CLI
integrate.sh                   installer for a firmware checkout
lib/thingino_arch/             index, impact, checks, packet, CLI
architecture/thingino.md       Thingino architecture brief
rules/thingino-review.json     OCR rule pack
prompts/architecture-review.md architecture review prompt
ci/architecture-check.yml      deterministic PR workflow
ci/ocr-review.yml              optional OCR workflow
baseline.json                  reference baseline
test/                          Minitest fixture suite
doc/                           documentation
```

## Current baseline

`baseline.json` was generated from `thingino-firmware` at `c3cd414ff`. It
contains 105 existing findings: 1 error, 87 warnings, and 17 informational
findings. The error is an unreachable
`package/ingenic-tflite-micro/Config.in` while other packages select
`BR2_PACKAGE_INGENIC_TFLITE_MICRO`. It is a real latent wiring issue and is
baselined only to keep the first CI run actionable.

Regenerate the baseline only after intentional fixes. Do not grow it to hide
new findings.

## Tests

```sh
ruby -Ilib -Itest test/thingino_arch_test.rb
```

The suite builds a minimal Thingino fixture in a temporary directory and covers
indexing, reachability, WiFi registration, camera validation, plugin conflicts,
impact mapping, baseline suppression, changed-scope filtering, and OCR rule
ordering.

Linting:

```sh
for file in lib/thingino_arch.rb lib/thingino_arch/*.rb bin/thingino-arch; do
  ruby -c "$file"
done
shfmt -d -i 0 -ci integrate.sh
shellcheck -x integrate.sh
ruby -ryaml -e 'ARGV.each { |f| YAML.parse_file(f) }' ci/*.yml
```

## Design rules

- Deterministic checks belong in scripts, not the LLM.
- The LLM is for judgment across files, layers, and repositories.
- Every finding needs evidence.
- Impact is conservative; a missed profile is worse than a broad list.
- QEMU is the runtime oracle; the static index decides what to test.
- Do not fork `open-code-review`; use its rules, background, tools, delegation
  mode, and GitHub Action.
- The model does not need to be fine-tuned; it needs the current index,
  architecture brief, and repository tools.

## License

MIT. See [LICENSE](LICENSE).

## Limitations

- Static Kconfig approximation, not a full Kconfig evaluation.
- QEMU covers emulated Ingenic behavior; it does not replace real-hardware validation.
- No cross-repo source verification; QEMU verifies the integrated image.
- Patch review is textual; the patched source is not present.
- OCR review is per-group and does not replace human review.
- The LLM is not authoritative on hardware behavior.

See [doc/troubleshooting.md](doc/troubleshooting.md) and
[doc/architecture.md](doc/architecture.md#limitations) for details.
