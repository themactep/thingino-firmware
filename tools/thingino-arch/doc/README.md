# Thingino Architect documentation

Thingino Architect (`thingino-arch`) is a structural review layer for the
Thingino firmware tree. It builds an index of the project's build graph, maps a
change to the parts of the project it touches, runs deterministic structural
checks, and prepares the context for an LLM or `open-code-review` pass.

See the [project README](../README.md) for the quick start.

The tool does not call an LLM. It separates two concerns:

- deterministic work: parsing the tree, resolving Kconfig relationships,
  computing impact, checking invariants, and building review context;
- judgment work: deciding whether a change respects the architecture, which is
  done by a reviewer using the packet and the architecture brief.

## Documentation map

| Document | Purpose |
| --- | --- |
| [cli.md](cli.md) | Command reference, options, defaults, exit codes |
| [architecture.md](architecture.md) | Internal design, index model, impact mapping, packet structure |
| [checks.md](checks.md) | Every structural check, severity, baseline behavior |
| [ocr.md](ocr.md) | Open Code Review integration, rule pack, delegation, evaluation |
| [ci.md](ci.md) | Deterministic PR workflow and optional OCR workflow |
| [integration.md](integration.md) | Installer, vendoring, updates, baseline lifecycle |
| [development.md](development.md) | Repository layout, tests, linting, extension points |
| [security.md](security.md) | Trust boundaries, baseline integrity, OCR data flow |
| [troubleshooting.md](troubleshooting.md) | Common failures and limitations |

The project-specific architecture brief is separate from this documentation:

- [`../architecture/thingino.md`](../architecture/thingino.md) describes the
  Thingino build graph, layers, integration recipes, and invariants.
- [`../prompts/architecture-review.md`](../prompts/architecture-review.md)
  defines the required behavior and output format for an architecture review.

## Core concepts

### Index

The index is a JSON representation of the tree. It contains packages, Kconfig
symbols and source edges, the WiFi driver matrix, SoC models and families,
kernel mappings, camera profiles, fragments, init scripts, WebUI plugins, and
reverse maps from each entity to the camera profiles that use it.

The index is built from the source of truth, not from a hand-maintained list.

### Impact

Impact analysis maps changed files to entities and then through the reverse
maps to affected camera profiles. A change to a package, fragment, SoC family,
WiFi driver, init script, or plugin produces a different affected set.

Impact is intentionally conservative. A broad change can list many profiles;
that is better than missing a profile that builds the changed component.

### Verification

Verification maps the affected families to QEMU test profiles and selects the
optional suites that match the changed layers. The `verify` command emits a
build and run plan or dispatches the firmware repository's native
`qemu-test.yaml` workflow.

QEMU boots the real firmware image and exercises boot, services, networking,
WebUI, ONVIF, USB, GPIO, and emulated sensors. It does not replace real-hardware
validation.

### Structural checks

The checks cover invariants that a script can decide exactly: unreachable
Kconfig, missing hashes, unregistered WiFi drivers, incomplete camera
profiles, conflicting init scripts or WebUI plugins, undefined symbols, and
SoC model conflicts.

Check findings have stable fingerprints. A baseline records existing findings
so a CI job can report only new ones.

### Baseline

The baseline is not a whitelist of acceptable code. It is a snapshot of known
findings in the reference tree. A new finding is reported; an existing finding
is suppressed until the baseline is regenerated after an intentional fix.

Do not regenerate the baseline to hide a new issue.

### Packet

The packet is the handoff to the reviewer. It contains the diff, impact
report, relevant index slices, new deterministic findings, the architecture
brief, the review prompt, and the diff capped by a byte limit.

The packet is usable by any agent. It does not depend on `open-code-review`.

### OCR rule pack

`open-code-review` remains the inline-comment harness. The rule pack tells it
which files to review and which checklist to apply. It includes file types OCR
excludes by default, such as `.mk`, `.in`, `.cgi`, `.patch`, `.dts`, `.config`,
and `.hash`.

The architecture brief supplies the project-level context that generic OCR
rules lack.

## Data flow

```
Thingino checkout
      |
      v
   Index  ---> Impact ---> Verification ---> QEMU
      |            |              |
      |            +----> Packet --+
      |                       ^
      +-----> Checks ---------+
                 |
                 v
             Baseline
```

The CLI exposes each stage separately. The CI workflow combines them into one
PR job.

## Scope

In scope:

- package and Kconfig wiring;
- camera profile completeness and consistency;
- WiFi driver registration;
- SoC family and kernel impact;
- init script and WebUI plugin integration;
- fragments and shared configuration;
- cross-file and cross-layer structural review context.

Out of scope:

- formatting and style;
- shellcheck, shfmt, Prettier, or defconfig sorting;
- building or booting the image from inside `thingino-arch` itself; the verify
  plan and native QEMU workflow execute those steps;
- real-hardware validation;
- replacing human review;
- automatically rewriting the change.

## Quick start

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

bin/thingino-arch packet \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --title "PR title" \
  --baseline baseline.json \
  --output out/packet.md
```

For a local commit, the default range is `HEAD~1..HEAD`. For an explicit file
list, use `--files path/a,path/b` with `impact` or `check --changed`.

## Requirements

- Ruby 3.3 or newer for the tool and tests;
- Git 2.41 or newer for range-based review;
- `open-code-review` 1.13.3 or newer only for the OCR path;
- Python 3, QEMU, `dnsmasq`, `tcpdump`, and Node/Playwright only for the QEMU
  verification workflow;
- no external Ruby gems.

The deterministic workflow uses a standard GitHub-hosted runner with Ruby
installed by `ruby/setup-ruby`.

## Installation

To install into a firmware checkout:

```sh
./integrate.sh --repo ../firmware/master
```

See [integration.md](integration.md) for the full install, update, and
baseline lifecycle.
