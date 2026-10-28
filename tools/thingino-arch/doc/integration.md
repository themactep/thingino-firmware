# Integration and installation

`integrate.sh` installs `thingino-arch` into a Thingino firmware checkout. It
is intended for the main firmware repository, but it works with any tree that
has `thingino.mk` and `package/`.

## Requirements

- a Thingino firmware checkout;
- Ruby 3.3 or newer;
- Git 2.41 or newer;
- a writable `.github/workflows` directory if the CI workflow is installed.

The installed tool has no external Ruby gem dependencies.

## Basic install

```sh
cd thingino-review
./integrate.sh --repo ../firmware/master
```

The script:

1. validates the target tree and tool source;
2. copies the tool to `<repo>/tools/thingino-arch/`;
3. generates `<repo>/tools/thingino-arch/baseline.json` if it does not exist;
4. installs `.github/workflows/architecture-check.yml`;
5. runs a smoke check against the installed baseline.

It does not commit. Review the copied files and commit them with your normal
workflow.

## Options

| Option | Description |
| --- | --- |
| `--repo PATH` | Firmware checkout; default `$THINGINO_REPO` or `../firmware/master` |
| `--tool PATH` | `thingino-arch` source directory; default the script directory |
| `--with-ocr` | Also install the optional OCR workflow |
| `--refresh-baseline` | Regenerate `tools/thingino-arch/baseline.json` |
| `--force` | Replace an existing workflow file that differs from the source |
| `--dry-run` | Print actions without changing anything |
| `-h`, `--help` | Show usage |

Examples:

```sh
./integrate.sh --repo ../firmware/master --dry-run
./integrate.sh --repo ../firmware/master --with-ocr
./integrate.sh --repo ../firmware/master --refresh-baseline
./integrate.sh --repo ../firmware/master --force
```

## Installed layout

```
<repo>/
  .github/workflows/
    architecture-check.yml
    ocr-architecture-review.yml        # with --with-ocr
  tools/thingino-arch/
    bin/thingino-arch
    lib/thingino_arch/...
    architecture/thingino.md
    rules/thingino-review.json
    prompts/architecture-review.md
    doc/...
    ci/...                             # workflow templates
    README.md
    baseline.json
```

The test suite is not copied into the firmware repository. It stays in the
tool source repository.

## Baseline lifecycle

The baseline is generated from the current firmware tree on first install.

On later runs:

- if `baseline.json` exists, it is preserved;
- `--refresh-baseline` regenerates it from the current tree.

This is deliberate. Regenerating on every install would baseline new findings
and defeat the purpose of the check.

The baseline belongs to the firmware repository once installed. The source
repository's `baseline.json` is a reference snapshot from
`thingino-firmware@c3cd414ff`; it is not copied by the installer.

To update the baseline after fixing findings:

```sh
tools/thingino-arch/bin/thingino-arch check \
  --repo . \
  --write-baseline tools/thingino-arch/baseline.json
```

Review the baseline diff. Do not regenerate it just to make a new finding
disappear.

## Updating the tool

Re-run the installer:

```sh
./integrate.sh --repo ../firmware/master
```

Behavior:

- `bin/`, `lib/`, `architecture/`, `rules/`, and `prompts/` are replaced with
  the source versions;
- `README.md` is replaced;
- `baseline.json` is preserved;
- workflow files are compared:
  - identical: left unchanged;
  - different: the script fails before modifying anything;
  - different with `--force`: replaced.

The preflight is intentional. A workflow conflict does not leave a partially
updated install.

## Workflow conflict

If the installer reports:

```
error: <repo>/.github/workflows/architecture-check.yml already exists and differs; use --force to replace it
```

You have local edits in the installed workflow. Either:

- merge the source changes by hand; or
- replace it with the source version:

```sh
./integrate.sh --repo ../firmware/master --force
```

The same applies to the OCR workflow with `--with-ocr`.

## Dry run

`--dry-run` validates the tree and prints the copy, baseline, and workflow
commands without changing files. Use it before the first install or in a
release checklist.

```sh
./integrate.sh --repo ../firmware/master --dry-run
```

## Smoke check

After a real install, the script runs:

```sh
tools/thingino-arch/bin/thingino-arch check \
  --repo . \
  --baseline tools/thingino-arch/baseline.json
```

On a fresh install this should report the baseline count and no new findings.
If it reports new findings, review the tree and the baseline before committing.

## Uninstall

Remove the installed directories and workflows:

```sh
rm -rf <repo>/tools/thingino-arch
rm -f <repo>/.github/workflows/architecture-check.yml
rm -f <repo>/.github/workflows/ocr-architecture-review.yml
```

If the baseline was committed, remove it with the tool directory. No firmware
source files are modified by the installer.

## Installing into another Thingino repository

The tool expects the firmware tree layout: `thingino.mk`, `package/`,
`configs/`, `soc/`, `kernels/`, `overlay/`.

For a component-only repository such as `prudynt-t` or `open-tx-isp`, the
firmware index is not applicable. Use the architecture brief and the OCR rule
pack as review context, but do not run the firmware checks unless the tree
matches the expected layout.

## Security and review

The installer runs locally and does not contact the network. It does not
commit, push, or configure secrets.

The installed deterministic workflow is safe on fork PRs, but it executes the
Ruby tool from the PR checkout. Protect `tools/thingino-arch/**` and
`.github/workflows/**` with code owners and branch protection. See
[security.md](security.md).
