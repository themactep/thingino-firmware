# Security and trust model

This document describes what the tool executes, what it trusts, and where the
remaining risks are.

## Trust boundaries

The system has three trust domains:

1. **The Thingino firmware tree.** Mostly public and untrusted in a PR. It
   contains code, configuration, scripts, and data.
2. **The review tooling.** Ruby code in `tools/thingino-arch/` and the
   workflows. It is trusted when it comes from a protected base branch; it is
   untrusted when it comes from a PR checkout.
3. **The LLM provider and credentials.** Only the optional OCR workflow uses
   an external model endpoint and a write token.

The deterministic checks and the packet builder do not call the network and do
not execute firmware code.

## Deterministic CI job

The `architecture-check` workflow:

- triggers on `pull_request`;
- requests `contents: read` only;
- has no repository secrets;
- checks out the PR merge commit with full history;
- runs the Ruby tool from `tools/thingino-arch/` in that checkout;
- writes a job summary and artifacts;
- fails only on new structural errors.

### Fork safety

A fork PR receives a read-only `GITHUB_TOKEN` and no secrets. The workflow does
not write comments, so the lack of write permission is not a problem. This is
the safest default for a public repository.

### The vendored tool is executable code

The deterministic job runs Ruby from the PR checkout. A PR that changes
`tools/thingino-arch/bin/thingino-arch` or `lib/thingino_arch/` can change what
the job does, including reading workspace files or making network requests
with the read-only token.

Mitigations:

- protect `tools/thingino-arch/**` and `.github/workflows/**` with
  `CODEOWNERS`;
- require maintainer review for those paths;
- require workflow approval for first-time fork contributors;
- review changes to the tool like any other executable dependency.

If the threat model requires stronger isolation, run the tool from the base
branch and use the PR checkout only as data. That is a larger workflow change
and should be evaluated separately.

### Baseline integrity

The baseline suppresses findings. If a PR could choose the baseline used for
its own review, it could hide findings.

The workflow therefore:

- reads `tools/thingino-arch/baseline.json` from the base branch when it exists;
- falls back to the PR baseline only during the first integration, when the
  base branch has no baseline yet.

The bootstrap PR must be reviewed carefully. After merge, the base baseline is
the authority.

A PR may intentionally update the baseline with a fix. That update takes effect
after merge; it does not affect the PR's own suppression set.

### Artifacts

The workflow uploads `arch-check.json`, `arch-impact.txt`, and
`arch-packet.md`. The packet contains the diff and source excerpts. Treat
artifacts with the same access policy as the repository. Do not upload them to
a public location if the PR is private.

## OCR workflow

The optional OCR workflow:

- is manual-dispatch only;
- requests `contents: read` and `pull-requests: write`;
- receives LLM credentials from repository secrets;
- runs the pinned OCR action and npm package;
- posts inline comments and a sticky summary.

### Secrets

Use dedicated credentials:

- a dedicated LLM token, not a personal key;
- a dedicated bot token or the scoped `GITHUB_TOKEN`;
- rotate on maintainer changes or suspected exposure.

The LLM token is available to the action. Do not add other secrets to the job.
Do not enable MCP servers or shell tools in the OCR configuration.

### Data sent to the model

OCR sends the diff, related file contents, the architecture brief, and the rule
text to the configured LLM endpoint. Thingino is open source, but:

- do not include secrets in prompts or background text;
- do not point the workflow at a private repository without reviewing the
  provider's data policy;
- prefer a self-hosted or organization-controlled OpenAI-compatible endpoint
  when required.

### Prompt injection

PR content is untrusted. A diff, commit message, or file can contain text that
tries to instruct the model to ignore the rules, reveal context, or produce a
misleading comment.

The OCR toolset is read/search/diff/comment; it has no shell execution tool in
the default configuration. The write token is limited to pull request comments.
Still, treat the output as untrusted review input:

- do not auto-merge based solely on an OCR approval;
- do not grant the action broader repository permissions;
- keep MCP disabled unless it is a trusted local tool;
- review comments before acting on them.

### Action and package pinning

The OCR workflow pins the action by commit SHA and the npm package by version.
Update both together after reviewing the upstream release.

GitHub-maintained actions such as `actions/checkout`, `ruby/setup-ruby`, and
`actions/upload-artifact` should also be pinned by SHA in a high-assurance
environment. The provided template uses version tags for readability; pin them
if your policy requires it.

## Native QEMU workflow

The firmware repository's `qemu-test.yaml` workflow is manual-dispatch and
runs on GitHub-hosted runners. It builds firmware and boots it in QEMU, so it
executes the selected branch's build and startup paths, not just the review
tool.

- The workflow has the default GitHub Actions permissions; keep them minimal
  (`contents: read` unless the workflow needs release caches).
- It uses the repository's `GITHUB_TOKEN` for release cache access; do not add
  unrelated secrets.
- Artifacts include serial logs, screenshots, and reports; treat them like the
  repository content.
- The QEMU binary is downloaded from a pinned release and checked against the
  package hash.
- `workflow_dispatch` cannot target a fork branch. Do not create base-repository
  branches from untrusted fork heads without reviewing what will run.
- QEMU runs on GitHub-hosted infrastructure, so the blast radius is the workflow
  token and artifacts, not a long-lived self-hosted host.

`thingino-arch verify --dispatch` only constructs and runs the `gh workflow run`
command; it does not bypass the workflow's permissions.

## Local use
## Local use

The CLI and installer run locally:

- no network access;
- no telemetry;
- no writes outside the target repository and the paths you pass;
- no Git commits.

The installer overwrites the tool directories in the target repository and
preflights workflow conflicts before copying. It does not overwrite firmware
source files.

## Recommendations

- Protect `tools/thingino-arch/**` and `.github/workflows/**`.
- Keep the deterministic job read-only.
- Keep the OCR job manual until its precision is proven.
- Use base-branch baselines in CI.
- Review baseline diffs like code.
- Rotate LLM credentials.
- Do not add MCP or shell tools to the OCR job.
- Do not treat LLM output as an authority on hardware behavior.

## Out of scope

The tool does not protect against:

- a compromised GitHub runner;
- a compromised LLM provider;
- a malicious maintainer with write access;
- vulnerabilities in Buildroot, the kernel, or firmware code;
- supply-chain attacks in upstream packages;
- secrets committed to the firmware repository.

Those require the project's normal security review and infrastructure
controls.
