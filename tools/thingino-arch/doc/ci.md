# CI integration

Two workflows are provided:

- `ci/architecture-check.yml`: deterministic, no secrets, required candidate;
- `ci/ocr-review.yml`: optional, manual, LLM-backed.

`integrate.sh` installs them as:

- `.github/workflows/architecture-check.yml`
- `.github/workflows/ocr-architecture-review.yml` (with `--with-ocr`)

## Deterministic workflow

### Trigger and permissions

```yaml
on:
  pull_request:

permissions:
  contents: read
```

The workflow runs on every PR update. It does not need secrets and does not
write to the pull request. It posts a summary through `$GITHUB_STEP_SUMMARY`
and uploads artifacts.

This makes it safe for fork PRs: the token is read-only, and no LLM credential
is exposed.

### Concurrency

```yaml
concurrency:
  group: architecture-check-${{ github.event.pull_request.number }}
  cancel-in-progress: true
```

A new push cancels the previous run for the same PR.

### Steps

1. Check out the PR merge commit with full history.
2. Fetch the base branch.
3. Prepare the baseline:
   - if the base branch contains `tools/thingino-arch/baseline.json`, use that
     file;
   - otherwise, bootstrap from the PR's own baseline.
4. Set up Ruby 3.3.
5. Run `thingino-arch check --changed` into `arch-check.json`.
6. Run `thingino-arch impact` into `arch-impact.txt`.
7. Build `arch-packet.md`.
8. Publish the impact and check summary.
9. Upload the JSON, exit status, impact, and packet.
10. Fail the job if the structural check exited 1.

### Baseline extraction

The base-branch baseline is used deliberately. If the workflow used the PR's
`baseline.json`, a contributor could add fingerprints to suppress findings in
their own change.

The bootstrap case is the PR that first adds the tool. The base branch has no
baseline yet, so the workflow falls back to the PR's baseline. Review that
first integration PR carefully; after it merges, the base baseline becomes the
authority.

### Artifacts

| Artifact | Content |
| --- | --- |
| `arch-check.json` | Findings and summary in JSON |
| `arch-check.exit` | Exit status from `thingino-arch check` |
| `arch-impact.txt` | Human-readable impact report |
| `arch-packet.md` | Full architecture review packet |

The packet can be downloaded from the workflow run and given to an agent. It
is not posted as a PR comment. It includes the QEMU verification plan, but the
deterministic job does not build or boot the image; use the native
`qemu-test.yaml` workflow for execution.

### Failure semantics

The job fails only when `check` exits 1. That means a new `error` finding.
Warnings and informational findings do not fail the job.

`--strict` is not enabled in the template. Enable it only after the warning
set is clean enough to be trustworthy.

### Full history

`fetch-depth: 0` is required for merge-base diffing and base-branch baseline
access. Thingino's repository is large; the checkout cost is real. If checkout
time becomes a problem, replace the full checkout with a targeted fetch of the
base and PR SHAs, while keeping the base baseline extraction.

## Optional OCR workflow

### Trigger

The OCR workflow is manual:

```yaml
on:
  workflow_dispatch:
    inputs:
      pr_number:
      base_ref:
      head_sha:
```

It is not triggered by `pull_request_target` or `issue_comment` in this
template. That avoids exposing secrets automatically and keeps LLM cost under
maintainer control.

### Permissions

```yaml
permissions:
  contents: read
  pull-requests: write
```

The write permission is needed to post inline review comments and the sticky
summary.

### Secrets and variables

| Name | Kind | Required |
| --- | --- | --- |
| `OCR_LLM_URL` | secret | yes |
| `OCR_LLM_AUTH_TOKEN` | secret | yes |
| `OCR_LLM_MODEL` | variable | yes |
| `OCR_LLM_USE_ANTHROPIC` | variable | no |

Use a dedicated token for the review bot, not a personal token. Rotate it when
the integration changes or when a maintainer leaves the project.

### Action pinning

The workflow uses:

```yaml
uses: alibaba/open-code-review@375f64cd6f67a48a135da83cfcf59c52669a09cb
```

and sets `ocr_version: "1.13.3"`. Pin both. Do not use `@main` for a workflow
that has access to LLM credentials.

### Cost controls

The template sets:

- `effort: medium`;
- `max_tokens_budget: "300000"`;
- `route_severity_below: low`;
- `incremental: true`;
- `checkpoint_range: true`.

Lower the budget or effort for a cheaper pilot. Use a cheaper model for the
first evaluation, then compare precision before increasing cost.

### Output

OCR posts inline comments and a sticky summary. `upload_artifacts: true`
preserves its own artifacts for debugging.

See [ocr.md](ocr.md) for the rule pack and evaluation method.

## Native QEMU workflow

Thingino's firmware repository already has
`.github/workflows/qemu-test.yaml`. It builds selected QEMU profiles and runs
the QEMU suite on GitHub-hosted runners.

### Dispatch

`thingino-arch verify` generates the profile plan and can dispatch the native
workflow directly:

```sh
bin/thingino-arch verify \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --ref <branch> \
  --dispatch
```

This runs:

```sh
gh workflow run qemu-test.yaml \
  -R themactep/thingino-firmware \
  --ref <branch> \
  -f "profiles=<selected profiles>" \
  -f runner_arch=x86_64
```

Requirements:

- `gh` is installed and authenticated;
- the repository remote named `origin` points at GitHub;
- `--ref` names a branch or tag in the base repository.

Use `--github-repo OWNER/REPO` if `origin` is not the target, and `--workflow`
if the workflow file has a different name.

### Runner

The native workflow uses GitHub-hosted `ubuntu-26.04` runners. It installs the
build dependencies in a container, downloads the pinned Ingenic QEMU binary,
installs `dnsmasq`, `tcpdump`, and Playwright Chromium, and runs the suite.

This means no self-hosted runner registration is required. The tradeoff is cost
and runtime: a full profile build takes tens of minutes.

### Inputs

| Input | Meaning |
| --- | --- |
| `profiles` | Space-separated QEMU profiles |
| `runner_arch` | `x86_64` or `arm64` build worker |

The native workflow always runs the full suite for each profile. `verify
--dispatch` therefore rejects `--only`; use the local plan if you need suite
selection.

### Coverage

The plan covers the affected SoC families, not every camera profile. Broad
changes use T31 and T41 by default. `--full` selects every affected family.

The QEMU suite boots the real image and covers boot/services, network,
WiFi portal, WebUI, ONVIF, USB, GPIO, and emulated sensors. It does not cover
real hardware, RF, power, thermal, or unmodeled peripherals.

### Artifacts

The workflow uploads:

- `qemu-test-image-<profile>`;
- `qemu-test-report-<profile>`, including `report.html`, `serial-results.json`,
  screenshots, serial logs, and Playwright results.

### Limitations

- `workflow_dispatch` runs a branch in the base repository. It cannot target a
  fork branch directly. For a fork PR, create a temporary branch in the base
  repository at the PR head and dispatch on that branch.
- The native workflow must contain the non-`master` output path fix
  (`output/${{ github.ref_name }}`). Without it, artifact staging uses
  `output/master` and fails on any other branch.
- The native workflow runs the full suite; per-suite selection is not exposed.

## Setup

### 1. Install the tool

```sh
./integrate.sh --repo ../firmware/master
```

This installs the deterministic workflow and generates the baseline.

### 2. Review the first PR

The first integration PR adds `tools/thingino-arch/` and the workflow. It also
adds the initial baseline. Review it as a tooling change, not as an ordinary
firmware change.

### 3. Protect the tooling paths

Recommended `CODEOWNERS` entries in the firmware repository:

```
/tools/thingino-arch/   @maintainers
/.github/workflows/      @maintainers
```

The deterministic job executes Ruby from the PR checkout. A PR that modifies
`tools/thingino-arch/bin/thingino-arch` can change the job's behavior. Branch
protection and code owner review are the practical controls.

If your threat model requires stronger isolation, run the tool from the base
branch and use the PR checkout only as data. The current template keeps the
simpler vendored model and relies on review controls.

### 4. Enable the OCR workflow

```sh
./integrate.sh --repo ../firmware/master --with-ocr
```

Then configure the secrets and variables, and trigger it manually for a test
PR.

### 5. Use the native QEMU workflow

No extra workflow is installed. The firmware tree already has
`.github/workflows/qemu-test.yaml`. Dispatch it with:

```sh
tools/thingino-arch/bin/thingino-arch verify \
  --repo . \
  --from origin/master --to HEAD \
  --ref <branch> --dispatch
```

Confirm the target branch contains the non-`master` output path fix in the
QEMU workflow.

### 6. Decide on automatic review

Do not enable automatic OCR review until the evaluation in [ocr.md](ocr.md)
shows acceptable precision and noise. The deterministic workflow can be
required independently.

## Baseline policy in CI

- The base branch owns the baseline.
- A PR cannot silently change the baseline used for its own findings.
- A PR that intentionally fixes findings may update the baseline; that update
  takes effect after merge, and the PR itself may still show the old
  suppression set.
- Regenerate the baseline with `--refresh-baseline` or the direct
  `--write-baseline` command, review the diff, and commit it with the fix.

## Troubleshooting

### `origin/<base>` not found

The checkout did not fetch the base branch or history. Ensure
`fetch-depth: 0` and the `git fetch origin "$BASE_REF"` step ran.

### Empty or missing baseline

On the first integration PR, the base branch has no baseline. The workflow
falls back to the PR baseline. If both are missing, the check reports all
current findings, including pre-existing ones.

### The job fails on a known finding

The finding is not in the baseline. Either fix it or intentionally update the
baseline, then review the baseline diff.

### The job passes but the packet is huge

Use `--max-cameras` and `--max-diff-bytes` in the packet command, or run the
packet locally for the affected subset.

### Checkout is slow

Full history is the main cost. Keep it for correctness unless you implement a
targeted fetch.
