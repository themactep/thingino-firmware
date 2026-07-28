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
| `package/thingino-webui/files/www/a/*.js` | reformat | Prettier (via `npx`) |
| `configs/cameras*/…defconfig…` | sort entries | `scripts/sort_defconfig.py` |
| any file starting with `#!/bin/sh` | reformat | `shfmt -w -i 0 -ci` |

All three actions modify the file in the working tree and re-stage it with
`git add`, so the commit already contains the normalized version.

> **Note:** because the hook re-stages the whole file, partial staging
> (`git add -p`) of an affected file will end up fully staged. Commit
> formatting-sensitive files separately if that matters to you.

`shfmt` must be installed for the shell-script step; the hook aborts the
commit with a message if it is missing.

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
  BR2_THINGINO_AUDIO_GPIO=63
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
