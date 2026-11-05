# Optimization Roadmap

Working list of build-system and repository improvements. Each item has a
stable ID so later commits can reference it. Update the status line in the
same commit that lands an item.

Status: `[ ]` planned, `[~]` in progress, `[x]` done.

## P0 - Correctness

- [x] **O1** Repair the `make lint` defconfig-sort glob (it currently expands
  to a literal path and checks nothing) and cover every camera group
  (`cameras`, `cameras-exp`, `cameras-test`, `cameras-testing`) in
  `make lint`, `sort-defconfigs`, the pre-commit hook, and CI.
- [x] **O2** Broaden `make shellcheck` to every tracked shell script (not just
  `scripts/`) and add an `shfmt` check to `make lint` so the local suite
  matches the PR format gate.
- [x] **O3** Remove the parse-time `git ls-remote` from `show-vars`; for
  official-tarball kernels `KERNEL_SITE`/`KERNEL_BRANCH` are empty, so it
  queries the main repository's `origin` and fails offline.
- [x] **O4** Correct the documented build defaults: `make` is incremental,
  not clean; `make cleanbuild` is the clean build.

## P1 - Build performance

- [x] **O5** Stop evaluating `ROOTFS_DIRTY_INPUTS` (a `find` over the whole
  per-package tree) on every make invocation, including non-build targets.
- [x] **O6** Skip the unconditional `olddefconfig` in `defconfig` when
  `check-config` already reports the configuration is current.

## P2 - Duplication

- [x] **O7** Merge the `--check` mode of `scripts/update-packages.py` into
  `scripts/update_packages.py` and retire the older hyphenated script.
- [x] **O8** Retire `scripts/rtsp-stress-test.rb`; the docs and CI use the
  shell implementation.
- [x] **O9** Extract the shared RTSP DESCRIBE/digest logic used by
  `backchannel-probe.py` and `rtsp-backchannel-probe.py` into
  `scripts/rtsp_probe.py`. `backchannel-test.py` keeps its own Basic-auth
  response parser; it is a different tool.
- [x] **O10** Keep the three `send2common` copies separate. Each is installed
  as `/usr/share/send2common` by exactly one streamer package, and snapshot /
  clip access differs per streamer. The reason is documented in each file so
  it is not "deduplicated" later.
- [x] **O11** Remove the unused prebuilt `ingenic-tools-fpag` tree (the
  U-Boot patch adds its sources, but `tools/Makefile` only builds
  `ingenic-tools`). Keep the remaining intentional duplicates and add
  `scripts/check-duplicate-files.sh` to `make lint` so they cannot drift.

## P3 - Hygiene

- [x] **O12** Remove non-ASCII characters from tracked `.sh` files (em dashes,
  `✓`/`✗`, box drawing) and add `scripts/check-ascii.sh` to `make lint` so
  they do not come back.
- [x] **O13** Fix stale `docs/ai/` references to scripts that no longer exist
  or moved; add an archive index and mark the unimplemented proposals.
- [x] **O14** (not planned) Keep `configs/cameras-test`; it has an active use.
- [x] **O15** Local housekeeping only: `git gc` dropped the stray
  `tmp_pack_*` file and consolidated the packs (not a repository change).
- [x] **O16** Migrate the two `configs/cameras-exp` defconfigs that still use
  the removed `BR2_SOC_INGENIC_*` symbols to `BR2_INGENIC_SOC_MODEL`.

## Progress log

### Turn 1

- O1 done. `make lint` now expands the defconfig glob and covers all four
  camera groups. The repaired check immediately found
  `configs/cameras-exp/wyze_floodlightv2_t41nq_gc3003a_atbm6031` out of sort
  order; it is sorted in this commit. The same glob now covers `make
  sort-defconfigs`, the pre-commit hook, `pr-format.yml`, and `lint.yml`.
- O2 done. `make shellcheck` lints all 97 tracked `*.sh` files; `make lint`
  gained `shfmt-check` using the same `-i 0 -ci` rules as the hook. Two files
  (`scripts/disk_sectors_written.sh`, `scripts/update_toolchain_bundles.sh`)
  were reformatted.
- O3 done. `show-vars` prints the already-resolved `$(KERNEL_HASH)` instead of
  re-querying the network.
- O4 done. `make help` and `AGENTS.md` now describe the incremental default and
  `cleanbuild` correctly.

### Turn 2

- O5 done. `ROOTFS_DIRTY_INPUTS` now scans Buildroot's
  `.stamp_target_installed` files (one per package) instead of every file
  under `per-package/*/target/`. Warm scan drops from 0.13 s to 0.009 s
  (cold: ~0.9 s), and a touched install stamp is still detected as dirty.
- O6 done. `defconfig` skips `olddefconfig` when `.config` has not been
  rewritten since the last kconfig pass. The stamp is set by both
  `force-config` and `defconfig`; `clean-config` removes it. An up-to-date
  `make defconfig` drops from 1.57 s to 0.29 s while a touched `.config`
  still triggers a rebuild.

### Turn 3

- O7 done. `scripts/update_packages.py --check` now verifies that every
  `$(call github,...)` package records the current tarball name in its
  `.hash` file, offline. The check is part of `make lint` and the lint CI
  job. Retired the older `scripts/update-packages.py`.
- The new check found and this turn fixes three real hash problems:
  `scriba` had no entry for its current commit, and `thingino-sensor-info`
  and `wifi-rtw-hostapd` had no `.hash` file at all. Hashes were computed
  from verified tarball downloads, not typed by hand.
- O8 done. Removed `scripts/rtsp-stress-test.rb`; it was last touched in
  May and the maintained shell implementation superseded it in October.

### Turn 4

- O9 done. Added `scripts/rtsp_probe.py` and moved the duplicated
  `recv_response`, digest challenge, authorization, and DESCRIBE code out of
  both probe scripts. `backchannel-test.py` is unchanged: it speaks Basic
  auth and uses a different response parser for its RTP send path.
- O10 closed as not-a-defect. The `send2common` files are per-streamer
  variants installed exclusively by the selected streamer package; snapshot
  and clip access differ. Each copy now says so at the top.

### Turn 5

- O11 done as approved (options 1 and 4). Removed the unused prebuilt
  `thingino-uboot/files/2013.07/tools/ingenic-tools-fpag/` tree (~1.3 MiB).
  The large U-Boot patch still adds that directory's sources, but the
  top-level `tools/Makefile` only builds `ingenic-tools`; the prebuilt
  binaries were never used. Added `scripts/check-duplicate-files.sh`, which
  keeps the nine intentionally duplicated wifi/Linux asset groups in sync.
  A deliberate divergence is handled by editing the manifest, not by
  silently changing one copy.
- O12 done. Converted all 27 tracked `.sh` files to ASCII (2,545 characters:
  box drawing, em/en dashes, bullets, arrows, status glyphs, emoji). Added
  `scripts/check-ascii.sh` to `make lint` and the lint CI job. No runtime
  firmware scripts were affected; all were host/build/docs tools.

### Turn 6

- O13 done. Added `docs/ai/README.md` as an archive index and marked the
  three never-implemented SOC database proposals as historical. Rewrote
  `INGENIC_SOC_MODEL_IMPLEMENTATION.md` to describe the real
  `soc/<vendor>/*.mk` lookup, fixed the `assemble_plugins.py` path in
  `docs/dev/plugin-system.md`, and removed the stale legacy-variable promise
  from the `BR2_INGENIC_SOC_MODEL` help text.
- O14 closed as not planned: `configs/cameras-test` has an active use.
- O15 done. `git gc` went from 23 packs and 22,371 loose objects to 2 packs
  and 0 loose; removed the 5.2 MiB stale `tmp_pack_*`. Object storage fell
  from about 1.08 GiB to 889 MiB.
- New O16: two `configs/cameras-exp` defconfigs still set the removed
  `BR2_SOC_INGENIC_T23N` / `BR2_SOC_INGENIC_T31N` symbols and therefore set
  no model. Flagged for a separate fix.

### Turn 7

- O16 done. Replaced `BR2_SOC_INGENIC_T23N` / `BR2_SOC_INGENIC_T31N` in the
  two `configs/cameras-exp` defconfigs with `BR2_INGENIC_SOC_MODEL="t23n"` /
  `"t31n"` and re-sorted them. `show-vars` now resolves t23 / 64 MB and
  t31 / 64 MB respectively; no legacy symbols remain under `configs/`.
