# Troubleshooting

## The tool says the path is not a Thingino firmware tree

```
not a Thingino firmware tree: /path
```

The target must contain `thingino.mk` and a `package/` directory. Point
`--repo` at the firmware root, not at a component repository or a build output
directory.

```sh
bin/thingino-arch index --repo ../firmware/master
```

## `origin/<base>` is missing

The CI checkout does not have the base branch. Ensure:

- `actions/checkout` uses `fetch-depth: 0`;
- the workflow runs `git fetch origin "$BASE_REF"` before the range commands.

For local runs, fetch the base:

```sh
git -C ../firmware/master fetch origin master
```

## Check reports no findings

Several normal reasons:

- the baseline suppresses existing findings;
- `--changed` kept only findings in the changed scope, and none matched;
- the change is tooling/docs only, which has no camera impact;
- the check set simply does not cover that class of issue.

Inspect the summary line:

```
Summary: 0 errors, 0 warnings, 0 info, 105 baselined
```

`105 baselined` means the findings exist but are suppressed. Use
`--all-findings` on `packet` to include them, or run `check` without a baseline
to see the full set.

## The job fails on a finding I thought was baselined

Possible causes:

- the finding's message or id changed, so its fingerprint changed;
- the baseline used in CI is the base-branch baseline, not the PR's edited
  baseline;
- the finding is on a different path or entity than expected;
- the baseline file is malformed or empty.

Inspect `arch-check.json` for the finding's `id`, `path`, and `entity`. Compare
its fingerprint with the baseline file.

## The first integration PR fails

The base branch has no baseline yet. The workflow falls back to the PR
baseline. If the PR baseline is missing or outdated, all current findings are
reported.

Resolve by:

1. generating the baseline with the installer or `--write-baseline`;
2. reviewing the baseline contents;
3. committing it with the tool;
4. merging the first integration PR after review.

## Installer reports a workflow conflict

```
error: <repo>/.github/workflows/architecture-check.yml already exists and differs; use --force to replace it
```

The installed workflow has local changes. Merge the source changes by hand, or
replace it:

```sh
./integrate.sh --repo ../firmware/master --force
```

The installer preflights conflicts before copying, so a conflict does not leave
a partial install.

## Installer regenerated the baseline unexpectedly

The installer only regenerates when:

- `baseline.json` does not exist; or
- `--refresh-baseline` was passed.

Check the command line. If the baseline is missing, restore it from Git before
rerunning.

## OCR does not review a file that should be reviewed

Check the rule pack resolution:

```sh
ocr rules check --rule rules/thingino-review.json <path>
```

Common causes:

- the path matches `exclude` before it matches `include`;
- a broad rule appears before a specific rule;
- the file is in `package/all-patches/**`, which is excluded;
- the extension is not in `include` and is not in OCR's default allowlist;
- OCR's binary or generated-file gate rejected the file.

The rule order is documented in [ocr.md](ocr.md#rule-order).

## OCR applies the wrong rule

The first matching rule wins. A broad payload rule such as `**/files/**` must
come after language-specific rules. Check the resolved pattern with
`ocr rules check`.

A common case is a JavaScript file under `package/<name>/files/www/`. If it
matches the payload catch-all instead of the JS rule, the rule order is wrong.

## OCR excludes a patch

`package/all-patches/**` is excluded deliberately. The patched upstream source
is not in the firmware checkout, so a textual patch review would be shallow.

Use the architecture impact report to see which cameras are affected. Review
the patch in the upstream component checkout when deep review is required.

## The packet is too large

Reduce the scope:

```sh
bin/thingino-arch packet \
  --repo ../firmware/master \
  --from origin/master --to HEAD \
  --max-cameras 10 \
  --max-diff-bytes 50000 \
  --baseline baseline.json \
  --output out/packet.md
```

For a global change, the impact table can still be large. Review the impact
JSON separately and include only the affected packages or profiles in a manual
prompt.

## The index looks wrong

Run `index` and inspect the stats:

```sh
bin/thingino-arch index --repo ../firmware/master --output /tmp/index.json
ruby -rjson -e 'puts JSON.parse(File.read("/tmp/index.json"))["stats"]'
```

A sudden drop in packages, cameras, WiFi drivers, plugins, or init scripts
indicates a parser regression. Check the tree layout first; the tool expects
the standard firmware structure.

For a specific entity:

```sh
ruby -rjson -e '
  d = JSON.parse(File.read("/tmp/index.json"))
  p d["cameras"]["cameras/foo"]
  p d["packages"]["foo"]
'
```

## Impact lists too many cameras

Impact is conservative. These causes are common:

- the changed path is `overlay/`, a top-level `Config.in`, `thingino.mk`, or a
  Makefile;
- the changed package is selected by a default system package;
- the changed fragment is implicit (toolchain or U-Boot);
- the changed path is `package/all-patches/**`.

Use the reasons in the impact output to see why each camera was included.
Narrow the review to the entities that actually use the changed code.

## Impact lists too few cameras

- A package may be selected only through a Kconfig `select` chain that the
  static parser does not resolve.
- A conditional `depends on` may make a default invalid.
- A component may be pinned by a package but built outside the firmware tree.

Treat the impact report as a starting point, especially for cross-repo or
conditional changes.

## A structural finding is a false positive

Check whether the tool is modeling the tree correctly:

1. Read the finding's path and details.
2. Inspect the index entry for that entity.
3. Check the source-of-truth file, not only the diff.
4. If the parser is wrong, fix the parser and add a fixture.
5. If the tree intentionally uses an unsupported pattern, document it and
   decide whether to suppress the finding in the baseline.

Do not add a baseline entry for a parser bug. Fix the parser.

## The OCR review is noisy

- Raise the severity routing threshold.
- Remove or narrow noisy rules.
- Exclude docs, generated files, and bulk patches.
- Use a stricter architecture brief that says what not to report.
- Compare models and effort levels.
- Only run OCR on PRs that touch code or structural configuration.

Noise is a rule-pack problem before it is a model problem.

## The OCR review misses an integration point

- Check that the path is in `include` and not in `exclude`.
- Check that the relevant rule is selected.
- Check that the architecture brief covers the subsystem.
- Check whether the missing file is outside the reviewed group; use the packet
  for a global pass.
- Add a concrete integration recipe to the brief rather than a vague warning.

## Ruby version error

The tool requires Ruby 3.3 or newer. Check:

```sh
ruby --version
```

In CI, `ruby/setup-ruby` installs the requested version. In a local
environment, use the system package manager or a version manager.

## Checkout is slow in CI

Thingino's full history is large. `fetch-depth: 0` is used for merge-base
diffing and the base-branch baseline.

If checkout time becomes a problem, implement a targeted fetch of the base and
PR SHAs while keeping the baseline extraction. Do not switch to a shallow
checkout that breaks `git diff base..head`.

## QEMU verification plan has no profiles

Causes:

- the change is documentation/tooling only;
- no affected camera family has a QEMU test profile;
- the plan was capped by `--max-profiles`;
- the changed package is not selected by any camera.

Run `verify` with `--format text` and read the skipped-family reasons. Add a
`configs/cameras-testing/<profile>/qemu-test.json` profile for a missing family,
or use `--full` to include all affected families.

## A QEMU profile is skipped or uses a fallback

`verify` prefers a profile with the capabilities the change needs. If a
family has no wired profile, for example, it may fall back to a WiFi-only
profile and note that the required suite will be skipped.

The note names the fallback. Add or adjust a profile if that coverage matters.

## QEMU run needs sudo or fails to open a tap device

Profiles with `"net": "tap"` or `"net": "slip"` need root and `/dev/net/tun`.
`run.sh` re-execs under `sudo`. For local runs, configure passwordless sudo and
the tun device. The native GitHub-hosted workflow already provides this.

## QEMU cannot find the image or QEMU binary

`run.sh` expects the newest image for the profile under `output/` and the QEMU
binary pinned by `package/qemu-ingenic`. Build first:

```sh
make GROUP=testing CAMERA=qemu_t31x_eth fast
scripts/qemu-test/run.sh qemu_t31x_eth
```

The QEMU binary is downloaded and hash-checked on first use. Offline runners
need it pre-populated in the cache or provided with `QEMU_BIN`.

## QEMU reports a failure that is not related to the change

- Check the base branch with the same profile and suite.
- Use stable check names to compare runs.
- Lab and Playwright suites are more sensitive to host load and timing.
- Start with `max_profiles=1` and the required suites, then expand.
- A pre-existing failure should be recorded explicitly, not hidden by
  reducing the plan.

## QEMU build takes too long

- Reduce `--max-profiles`.
- Use a single representative family for broad changes.
- Cache toolchain downloads and the QEMU binary.
- Keep `qemu-reports/` artifacts small by uploading only the needed profiles.
- Use the native workflow caches and a single representative profile.

## T33, C100, or CW080 has no QEMU plan

The QEMU fork has machines for these SoCs, but the firmware tree may not have a
`configs/cameras-testing` profile for them yet. Add the profile and a
`qemu-test.json` first; the tool indexes it automatically.

## `verify --dispatch` fails

Check:

- `gh` is installed and authenticated;
- `origin` points at the GitHub repository, or pass `--github-repo OWNER/REPO`;
- `--ref` names a branch or tag, not a detached HEAD;
- the workflow file exists and is dispatchable;
- the target branch's QEMU workflow contains the non-`master` output path fix.

`workflow_dispatch` cannot target a fork branch directly. Create a temporary
branch in the base repository at the PR head, or use the existing
pull-request-triggered infrastructure. Do not create a base branch from an
untrusted fork without reviewing what will run.

If `--only` was supplied, remove it: the native workflow runs the full suite.

## Where to look next

- [cli.md](cli.md) for command options and exit codes
- [checks.md](checks.md) for finding semantics
- [architecture.md](architecture.md) for the index and impact model
- [ocr.md](ocr.md) for rule selection and evaluation
- [ci.md](ci.md) for workflow behavior
- [security.md](security.md) for trust boundaries
