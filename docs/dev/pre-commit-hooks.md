# Pre-commit Hooks and Defconfig Sorting

The repository ships local git hooks in `.githooks/`. They keep committed
files consistently formatted so diffs stay reviewable. Enable them once per
clone:

```bash
make setup-hooks    # sets git config core.hooksPath .githooks
```

## What the pre-commit hook does

On every `git commit`, the hook processes **staged** files only:

| Staged files | Action | Tool |
|---|---|---|
| any changed file matching `scripts/do-not-edit.txt` | reject | `scripts/check-do-not-edit.sh` |
| `package/thingino-webui/files/www/a/*.js` | reformat | Prettier (via `npx`) |
| `configs/cameras*/…defconfig…` | sort entries | `scripts/sort_defconfig.py` |
| any file starting with `#!/bin/sh` | reformat | `shfmt -w -i 0 -ci` |
| any file starting with `#!…/(ba)?sh` | lint | `shellcheck -x` |
| `package/*/files/*.webui.json` | validate | `scripts/check-plugins.sh` |

The reformat actions modify the file in the working tree and re-stage it with
`git add`, so the commit already contains the normalized version. The reject
and lint actions fail the commit instead.

> **Note:** because the hook re-stages the whole file, partial staging
> (`git add -p`) of an affected file will end up fully staged. Commit
> formatting-sensitive files separately if that matters to you.

`shfmt` must be installed for the shell-script step; the hook aborts the
commit with a message if it is missing. `scripts/dep_check.sh` (run by
`make dep-check`) verifies shfmt, npx, and ripgrep are available.

## PR format gate (CI)

`.github/workflows/pr-format.yml` runs on every pull request and applies the
same criteria as the pre-commit hook — do-not-edit, shfmt, shellcheck,
Prettier, defconfig sorting, plugin validation — but in **check mode**
(`-d`/`--check`, fail instead of rewrite) over the files the PR touches.
Anything that fails in CI would have been caught locally by the hook, so run
`make dep-check` + `make setup-hooks` in your clone and fix before pushing;
`make lint` covers the shellcheck/defconfig/plugin halves.

`*.patch` files are excluded from all formatting checks (both in the gate and
in the hook) — they are generated/vendored artifacts. They remain subject to
the do-not-edit manifest, which still protects them from being edited.

The shfmt version used in CI is pinned in the workflow (`SHFMT_VERSION` at
the top of `.github/workflows/pr-format.yml`) — keep it in sync with the
version you run locally.

## Camera defconfig sorting

Camera defconfigs under `configs/cameras/<camera>/` and
`configs/cameras-exp/<camera>/` follow a canonical layout with three regions:

1. **Header** — the leading run of comment/blank lines (`# NAME:`, `# FRAG:`,
   optional prose hardware notes). Never reordered.
2. **Body** — the config entries, sorted alphabetically.
3. **Footer** — optional trailing freeform notes (stock firmware parameters,
   TODOs). Never reordered.

### Body sort rules

- Stable sort in **C-locale byte order**. The key is the full line with any
  leading `#` and whitespace stripped.
- `=` (0x3D) sorts before `_` (0x5F), so a bare option precedes its
  longer-named derivatives:

  ```
  BR2_PACKAGE_THINGINO_KOPT_DWC2=y
  BR2_PACKAGE_THINGINO_KOPT_DWC2_OTG=y
  BR2_THINGINO_AUDIO=y
  BR2_THINGINO_AUDIO_DMIC=y
  ```

- Non-`BR2_` keys (`FLASH_SIZE_MB=16`, `FLASH_NOR=y`) land after all
  `BR2_*` entries.
- **Commented-out entries** (`#BR2_...=...`) sort by their option name and
  therefore stay next to their active siblings:

  ```
  BR2_SENSOR_1_NAME="sc2336p"
  #BR2_SENSOR_1_PARAMS="shvflip=0"
  ```

- **Freeform annotation comments** inside the body belong to the entry
  directly below them and move with it:

  ```
  # 4-bit MMC sometimes hangs in U-Boot. Works fine on Linux.
  BR2_TARGET_UBOOT_BOARDNAME="isvp_t23n_sfcnor_mmc1bit"
  ```

  When writing new annotations, place them on the line(s) immediately above
  the entry they describe — never below, and never describing a group of
  entries (sorting scatters groups).
- Blank lines inside the body are dropped; duplicate entries keep their
  relative order.

### The sorter script

```bash
./scripts/sort_defconfig.py                 # fix all defconfigs in configs/cameras*/
./scripts/sort_defconfig.py FILE ...        # fix specific files
./scripts/sort_defconfig.py --check         # dry run, exit 1 if anything is unsorted
./scripts/sort_defconfig.py --check FILE    # dry run for specific files
```

Do not hand-sort defconfigs or write ad-hoc one-liners — run the script so
the exact key rules (C locale, `#`-stripping, comment attachment) stay
uniform across the tree. The pre-commit hook runs it automatically for
staged defconfigs, so a well-formed file is simply committed unchanged.

### Verifying a bulk change

After editing many defconfigs, confirm content was only reordered and no
lines were lost:

```bash
f=configs/cameras/<camera>/<camera>_defconfig
diff <(git show HEAD:$f | grep -v '^\s*$' | sort) \
     <(grep -v '^\s*$' $f | sort)
```

## Shellcheck suppression policy

`package/`, `overlay/`, and most scripts were never shellcheck-clean, so
the tree carries a legacy baseline. Files with findings carry a single
suppression line after the shebang:

```sh
# shellcheck disable=SC3043,SC2086,SC1091,SC2317
```

The rationale lives here rather than in every file — the suppressed
categories are:

- `SC3043`, `SC3026`, `SC3037`, `SC3045`, `SC3046`, `SC3051`, `SC3052`,
  `SC3054`, `SC3057`, `SC3060` — busybox ash extensions (`local`,
  `echo -n/-e`, `${var//old/new}`, `source`, `$(( ))` with `$`, shifts)
  that the cameras' BusyBox ash supports but POSIX does not define.
- `SC2018`, `SC2019`, `SC2028`, `SC2034`, `SC2153`, `SC2154` — `tr`
  byte-escape usage and variables consumed by sourced code or the runtime
  environment.
- `SC1090`, `SC1091` — sourced files that exist only on the target at
  runtime (e.g. `/var/www/x/auth.sh`), not in the repo.
- `SC2086`, `SC2046`, `SC2068` — intentional word splitting of internal
  variables (e.g. `$DAEMON_ARGS` must word-split).
- `SC2317`, `SC2329` — functions invoked via variable names, and
  single-use functions kept for readability.
- `SC2015` — intentional `test && cmd || other` one-liners.
- `SC2162`, `SC2059`, `SC2004`, `SC2155`, `SC2181`, `SC2126`, `SC2220`,
  `SC2231`, `SC2295` — idiomatic busybox-ash patterns.

Rules for contributors:

- Do **not** add codes to a baseline header to silence new findings —
  that defeats the point. Fix the code or add a targeted per-line
  `# shellcheck disable=SCxxxx` with a comment.
- If a file's findings are genuinely fixed, remove the header.
- `*.patch` files are excluded from all formatting checks entirely.

A full-tree sweep (same selector as the hook) must stay clean:

```bash
git ls-files | while read -r f; do
    [ -f "$f" ] || continue
    head -1 "$f" | grep -qE '^#!.*/(ba)?sh' && shellcheck -x "$f"
done
```
