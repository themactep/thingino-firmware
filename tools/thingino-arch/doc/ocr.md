# Open Code Review integration

Thingino uses [Open Code Review](https://github.com/alibaba/open-code-review)
(OCR) as the inline-comment harness. `thingino-arch` supplies the architecture
context and deterministic checks that OCR does not have.

The integration does not fork OCR. It uses four extension points:

1. a project rule pack;
2. an architecture background brief;
3. a review packet for the separate architecture pass;
4. OCR's delegation mode or its GitHub Action.

## Files

| File | Purpose |
| --- | --- |
| `rules/thingino-review.json` | File selection, scope, and per-path review rules |
| `architecture/thingino.md` | Project architecture brief passed as background |
| `prompts/architecture-review.md` | Structured prompt for the architecture pass |
| `ci/ocr-review.yml` | Optional manual-dispatch OCR workflow |
| `bin/thingino-arch packet` | Builds the review packet consumed by an agent |

## Why not rely on OCR defaults

OCR's default rules are generic. On Thingino they have two concrete problems:

- several important file types are excluded by default: `.mk`, `.in`, `.cgi`,
  `.patch`, `.dts`, `.config`, `.hash`, `.fragment`, and `Config.in.conf`;
- `.sh` is allowlisted but falls back to the generic `default.md` rule, so the
  review misses shell/CGI lifecycle and security concerns.

The Thingino rule pack fixes both. It also routes each path to a focused
checklist instead of relying on one generic prompt.

## Rule pack scope

The pack is at [`../rules/thingino-review.json`](../rules/thingino-review.json).

### Include

The include list brings previously excluded types into the review:

- shell and CGI: `.sh`, `.cgi`;
- templates and Kconfig: `.in`, `.conf`;
- Buildroot: `.mk`, `.hash`, `.config`;
- patches: `.patch`;
- device trees: `.dts`, `.dtsi`;
- camera profiles: `*_defconfig`;
- fragments: `.fragment`;
- C/C++: `.c`, `.h`, `.cpp`, `.cc`, `.cxx`, `.hpp`, `.hxx`;
- JavaScript/TypeScript/Python/Ruby;
- JSON, including `thingino.json`.

`include` is a bypass, not a whitelist. Files that already pass OCR's default
gate remain eligible. Use `exclude` to narrow the review.

### Exclude

The pack excludes:

- `docs/**`, Markdown, text;
- assets and binaries: audio, fonts, images, archives, PDFs;
- `buildroot/**`;
- `output/**`, `dl/**`;
- `package/all-patches/**`;
- Python caches.

`package/all-patches/**` is excluded from inline review because the patched
upstream source is not present in the firmware checkout. The architecture
impact pass still treats a change there as broad.

### Rule order

OCR uses the first matching rule. The current order is:

| Order | Pattern | Rule |
| --- | --- | --- |
| 0 | `**/Config*.in*` | Buildroot Kconfig structure |
| 1 | `**/*_defconfig` | Camera profile consistency |
| 2 | `**/configs/fragments/**/*.fragment` | Shared fragment impact |
| 3 | `**/*.config` | Buildroot/BusyBox config contract |
| 4 | `**/thingino.json` | Camera runtime metadata |
| 5 | `**/*.{dts,dtsi}` | Device tree |
| 6 | `**/package/ingenic-sdk/*.patch` | SDK cross-tree patch coverage |
| 7 | `**/*.patch` | Patch provenance and applicability |
| 8 | `**/*.mk` | Buildroot package contract |
| 9 | `**/*.{sh,cgi}` | Shell/CGI security and lifecycle |
| 10 | `**/files/**/*.in` | Shell templates |
| 11 | `**/init.d/**` | Init contract |
| 12 | `**/files/**/{S,K}[0-9]*` | Package service scripts |
| 13 | `**/*.{c,h,cpp,cc,cxx,hpp,hxx}` | Embedded C/C++ |
| 14 | `**/*.{js,jsx,ts,tsx,mjs,cjs,py,pyi,rb}` | WebUI/tooling boundary |
| 15 | `**/*.hash` | Package integrity |
| 16 | `**/files/**` | Payload catch-all; content-aware |
| 17 | `**/{S,K}[0-9]*` | Other service scripts |

The order is deliberate. Language-specific rules must come before the
`**/files/**` catch-all, and `.in` template rules must come before the broad
payload rule. The test suite checks this ordering.

The `package/ingenic-sdk/*.patch` rule is specific because the SDK ships more
than one kernel tree and alternate drivers. A patch that fixes one copy is not
complete until the other copies are checked.

### Overloaded paths

Two Thingino traps are encoded in the rules:

- `package/<name>/files/*.in` is usually a POSIX shell template, while
  `Config*.in` is Kconfig. They must not receive the same checklist.
- Many scripts have no extension (`S59motor`, `tell`, `wlan`). The
  `**/files/**` catch-all tells the model to determine the file type from its
  content and shebang before applying shell-specific guidance.

## Architecture brief

[`../architecture/thingino.md`](../architecture/thingino.md) describes:

- the build chain and merge order;
- source-of-truth files;
- layers and boundaries;
- integration recipes for packages, WiFi drivers, camera profiles, services,
  WebUI plugins, patches, and component bumps;
- structural invariants;
- known traps;
- runtime verification expectations and QEMU coverage;
- review behavior and output contract.

Pass it as background to OCR:

```sh
ocr review \
  --rule rules/thingino-review.json \
  --background-file architecture/thingino.md \
  --from origin/master --to HEAD
```

The GitHub Action does not expose `--background-file`. It takes a `background`
string; the template instructs the model to read
`tools/thingino-arch/architecture/thingino.md` from the workspace.

## Review packet

The packet is the preferred route for a structural architecture review. It
contains the diff, impact report, QEMU verification plan, index slices,
deterministic findings, the architecture brief, and the review prompt.

```sh
bin/thingino-arch packet \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --title "PR title" \
  --baseline baseline.json \
  --output out/packet.md
```

Use it with any agent:

```sh
# Example: open the packet in an interactive agent
kilo "Review out/packet.md as the Thingino architecture reviewer. Follow the
review instructions in the packet. Report only structural findings with
evidence. Separate confirmed findings from verification needed."
```

The packet is self-contained. The reviewer does not need OCR to use it.

## Local delegation mode

Delegation mode is the lowest-cost way to evaluate the rule pack. OCR performs
file selection and rule resolution; the host agent performs the review with
its own model and tools.

Install OCR locally:

```sh
npm install -g @alibaba-group/open-code-review@1.13.3
```

Preview the review set:

```sh
ocr delegate preview \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --rule rules/thingino-review.json
```

Resolve the rule for each path:

```sh
ocr delegate rule \
  --rule rules/thingino-review.json \
  configs/cameras/foo/foo_defconfig \
  package/wifi/wifi.mk
```

Then read the diffs and perform the review with Kilo, using the architecture
brief and the output contract. This path needs no OCR LLM endpoint or API key.

## OCR-managed review

Direct OCR review with a model endpoint:

```sh
ocr review \
  --rule rules/thingino-review.json \
  --background-file architecture/thingino.md \
  --from origin/master --to HEAD \
  --format json \
  --audience agent
```

This is the mode used by the optional GitHub Action. It produces inline
comments and a summary. Use `--max-tokens-budget`, `--effort`, and
`--concurrency` to control cost.

## GitHub Action workflow

[`../ci/ocr-review.yml`](../ci/ocr-review.yml) is an optional manual-dispatch
workflow.

Inputs:

- `pr_number`;
- `base_ref`;
- `head_sha`.

Required secrets and variables:

| Name | Kind | Purpose |
| --- | --- | --- |
| `OCR_LLM_URL` | secret | OpenAI-compatible or Anthropic endpoint |
| `OCR_LLM_AUTH_TOKEN` | secret | API token |
| `OCR_LLM_MODEL` | variable | Model name |
| `OCR_LLM_USE_ANTHROPIC` | variable | Set to `true` for Anthropic protocol |

The workflow pins the OCR action to commit
`375f64cd6f67a48a135da83cfcf59c52669a09cb` and the npm package to `1.13.3`.

Settings:

- `rule`: `tools/thingino-arch/rules/thingino-review.json`;
- `background`: instructs the model to read the architecture brief;
- `effort: medium`;
- `max_tokens_budget: 300000`;
- `sticky_summary: true`;
- `incremental: true`;
- `checkpoint_range: true`;
- `route_severity_below: low`;
- `upload_artifacts: true`.

The workflow is manual because automatic LLM review on every PR is a cost and
noise decision, not a technical default. Turn it on after evaluating precision
on historical PRs.

## What OCR can and cannot do

OCR is good at:

- reviewing a file-level diff with a project checklist;
- reading related files and searching the repository;
- producing inline comments and a summary;
- incremental re-review after new pushes;
- respecting a token budget.

OCR does not:

- compute the project graph; that is `thingino-arch`;
- build firmware, run QEMU, or test hardware;
- read a patched upstream source that is not checked out;
- automatically know another repository's state;
- replace deterministic checks.

Its review is split into groups. For small Thingino PRs the change set is
usually one group, and cross-file observations are encouraged. For large PRs
the review fragments. The architecture packet is the separate global pass.

## Evaluation before enabling automation

Use historical PRs, not synthetic examples. A practical evaluation:

1. Pick 10-20 merged PRs across package, WiFi driver, camera profile, WebUI
   plugin, init script, and patch changes.
2. Run the architecture packet and OCR review on each.
3. Triage every finding: confirmed, false positive, or unverifiable.
4. Compare against the PR discussion and any follow-up fix commit.
5. Measure:
   - true structural findings per PR;
   - false positives per PR;
   - noise from existing baselined findings;
   - coverage of missing integration points;
   - token cost and runtime.
6. Tune the rule pack and architecture brief. Prefer removing noisy rules over
   adding more prose.

A useful test set is the class of change that caused a follow-up fix. For
example, a T32-only patch that broke a T41 build should be caught by the
cross-family checklist. If the reviewer misses those, the brief or rules need
work.

## Limitations

- OCR comments must target files in the reviewed group. A missing file that is
  not in the diff must be handled through the packet or a summary.
- Patch review is textual. The patched source is not available unless the
  component repository is checked out.
- The model can be misled by PR text. Treat its output as review input, not as
  an authority.
- The model must not be asked to validate hardware behavior. It should mark
  those checks as verification needed.
- The rule pack and brief can drift from the tree. Regenerate or review them
  when the architecture changes.
