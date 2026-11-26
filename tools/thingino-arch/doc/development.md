# Development

This document is for changing `thingino-arch` itself, not for applying it to a
firmware checkout.

## Requirements

- Ruby 3.3 or newer;
- Git 2.41 or newer;
- `shellcheck` and `shfmt` for the installer;
- `open-code-review` 1.13.3 or newer only for OCR validation.

The Ruby code uses the standard library only. Do not add gems unless there is
a strong reason and the change is discussed first.

## Repository layout

```
bin/thingino-arch              CLI entry point
integrate.sh                   installer for a firmware checkout
lib/thingino_arch.rb           requires the modules
lib/thingino_arch/repo.rb      filesystem and Git access
lib/thingino_arch/index.rb     source-of-truth parsers and graph
lib/thingino_arch/impact.rb    changed-file impact
lib/thingino_arch/verification.rb QEMU profile and suite selection
lib/thingino_arch/checks.rb    invariants and baseline
lib/thingino_arch/packet.rb    review packet
lib/thingino_arch/cli.rb       command dispatch
architecture/thingino.md       thingino architecture brief
rules/thingino-review.json     OCR rule pack
prompts/architecture-review.md architecture review prompt
ci/architecture-check.yml      deterministic PR workflow
ci/ocr-review.yml              optional OCR workflow
baseline.json                  reference baseline
test/thingino_arch_test.rb     Minitest suite
doc/                           this documentation
```

## Running tests

```sh
ruby -Ilib -Itest test/thingino_arch_test.rb
```

The suite creates a minimal Thingino fixture in a temporary directory for each
test. It covers:

- package, camera, WiFi, and plugin indexing;
- Kconfig source reachability;
- unregistered WiFi drivers;
- unknown SoC models;
- plugin conflicts for co-selected packages;
- impact mapping from packages and unreferenced fragments;
- QEMU profile selection and suite selection;
- the `verify` shell plan and dispatch command through the CLI;
- baseline suppression;
- changed-scope filtering through the CLI;
- OCR rule ordering.

Tests must not depend on a real Thingino checkout.

## Linting

Ruby syntax:

```sh
for file in lib/thingino_arch.rb lib/thingino_arch/*.rb bin/thingino-arch; do
  ruby -c "$file"
done
```

Installer syntax and style:

```sh
shfmt -d -i 0 -ci integrate.sh
shellcheck -x integrate.sh
```

Workflow syntax:

```sh
ruby -ryaml -e 'ARGV.each { |file| YAML.parse_file(file) }' \
  ci/architecture-check.yml ci/ocr-review.yml
```

Rule pack JSON:

```sh
ruby -rjson -e 'JSON.parse(File.read("rules/thingino-review.json"))'
```

## Testing the installer

Create a minimal target tree, then run the installer against it:

```sh
tmp=$(mktemp -d)
mkdir -p "$tmp/package/foo"
printf '%s\n' 'SOC_FAMILY := t31' > "$tmp/thingino.mk"
printf '%s\n' 'menu "Test"' \
  'source "$BR2_EXTERNAL_THINGINO_PATH/package/foo/Config.in"' \
  'endmenu' > "$tmp/Config.in"
printf '%s\n' 'config BR2_PACKAGE_FOO' '	bool "foo"' > "$tmp/package/foo/Config.in"
printf '%s\n' 'FOO_SITE = local' > "$tmp/package/foo/foo.mk"

./integrate.sh --repo "$tmp"
./integrate.sh --repo "$tmp" --dry-run
./integrate.sh --repo "$tmp" --with-ocr
```

Test the conflict path by editing an installed workflow and rerunning without
`--force`. The installer must fail before copying anything.

## Adding an index field

1. Decide which parser owns the field. Keep the parsing close to the existing
   source of truth.
2. Use relative paths in the index. `Repo#relative` normalizes them.
3. Add the field to `Index#to_h`.
4. Add a fixture assertion in the test suite.
5. Update [architecture.md](architecture.md) if the field is user-visible.
6. Run against the real firmware tree to check for parse errors.

Do not add a field that duplicates a derived value. Derive it from the same
source of truth instead.

## Adding a check

1. Add the logic to `Checks#run` or a private method.
2. Use a stable id, for example `camera.unknown_soc`.
3. Choose the path and entity deliberately. They are part of the baseline
   fingerprint.
4. Pick the severity:
   - `error` for a build break or broken contract;
   - `warning` for a likely defect or incomplete integration;
   - `info` for a latent issue or mutually exclusive alternative.
5. If the check depends on co-selection, use `index.cameras_by_package` and
   `packages_coexist?`.
6. Add a test that creates the condition and asserts the finding.
7. Run against the real tree. If the finding is pre-existing, review it and
   update the baseline only if it is intentional.
8. Update [checks.md](checks.md).

Changing a check message changes its fingerprint. Previously baselined
findings will reappear. That is expected when the check semantics change.

## Adding an OCR rule

1. Add the path pattern and rule text to `rules/thingino-review.json`.
2. Place specific rules before broad catch-alls. The `**/files/**` rule must
   stay after C, JS/Python, `.in`, `.sh`/`.cgi`, and service-script rules.
3. Add the pattern to `include` if OCR excludes the extension by default.
4. Add the pattern to `exclude` if it is an asset, generated file, or bulk
   patch store.
5. Validate with:

   ```sh
   ocr rules check --rule rules/thingino-review.json <path>
   ```

6. Preview a real commit:

   ```sh
   ocr review -c <commit> --preview --rule rules/thingino-review.json
   ```

7. Update [ocr.md](ocr.md) and the ordering test.

Rule text should describe a checklist, not an essay. It must tell the model to
ignore style and deterministic findings that CI already covers.

## Adding a QEMU profile or suite mapping

QEMU profiles come from `configs/cameras-testing/*/qemu-test.json` in the
firmware tree; the tool indexes them automatically.

When the firmware adds a profile or a suite changes capability requirements:

1. add or update the profile in the firmware tree;
2. verify the index sees the profile:

   ```sh
   bin/thingino-arch index --repo ../firmware/master --output /tmp/index.json
   ruby -rjson -e 'p JSON.parse(File.read("/tmp/index.json"))["qemu_profiles"]'
   ```

3. check the plan for the affected family:

   ```sh
   bin/thingino-arch verify --repo ../firmware/master \
     --files path/to/changed/file --format text
   ```

4. update `Verification` when a new capability or suite needs a selection
   rule;
5. add a fixture profile and a test assertion;
6. update [ci.md](ci.md) if the native workflow inputs or behavior change.

## Changing the architecture brief

`architecture/thingino.md` is passed to the model. Keep it:

- concise enough to fit in context alongside a diff;
- specific to Thingino's source of truth and traps;
- current with the tree;
- free of claims that cannot be verified from the repository.

When a new subsystem or integration recipe appears, add it to the brief and
the packet, not only to a rule.

## Testing against the real firmware tree

Use a clean checkout or worktree. Do not run the installer against a tree you
do not want to modify.

```sh
bin/thingino-arch index --repo ../firmware/master --output /tmp/index.json
bin/thingino-arch impact --repo ../firmware/master --from origin/master --to HEAD
bin/thingino-arch check --repo ../firmware/master --baseline baseline.json
bin/thingino-arch packet --repo ../firmware/master \
  --from origin/master --to HEAD --baseline baseline.json --output /tmp/packet.md
```

Inspect the index stats and a few affected entities. A parser regression often
shows up as a sudden drop in packages, cameras, WiFi drivers, plugins, or init
scripts.

## Baseline policy

- The baseline is a reviewed snapshot, not a suppression tool.
- Regenerate it only after fixing or accepting the findings.
- Do not update it in the same commit as a check that changes fingerprints
  without explaining why.
- Keep the baseline diff reviewable.

## Style

- Ruby: standard library only; meaningful names; small methods; no hidden
  global state beyond the index.
- Shell: POSIX `sh`, quoted variables, no bashisms; `shellcheck` and
  `shfmt -i 0 -ci` must pass.
- JSON: valid, pretty-printed, stable ordering where it matters.
- Markdown: concise, technical, no marketing language.
- Documentation: update the relevant `doc/` page when behavior changes.

## Versioning

The version is defined in `lib/thingino_arch.rb`. Bump it when the CLI, index
schema, check semantics, or packet format changes in a way that affects users.

The OCR action and npm version are pinned separately in `ci/ocr-review.yml`.
Update both together when validating a new OCR release.
