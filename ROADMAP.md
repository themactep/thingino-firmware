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

- [ ] **O7** Merge the `--check` mode of `scripts/update-packages.py` into
  `scripts/update_packages.py` and retire the older hyphenated script.
- [ ] **O8** Retire `scripts/rtsp-stress-test.rb`; the docs and CI use the
  shell implementation.
- [ ] **O9** Extract the shared RTSP backchannel probe logic used by
  `backchannel-probe.py`, `rtsp-backchannel-probe.py`, and
  `backchannel-test.py`.
- [ ] **O10** Consolidate the three divergent `send2common` copies and the
  related `ha-common`.
- [ ] **O11** Deduplicate firmware blobs repeated across package `files/`
  directories (wifi firmware, Ingenic tools, logos).

## P3 - Hygiene

- [ ] **O12** Remove non-ASCII characters from tracked `.sh` files (em dashes,
  `✓`/`✗`, box drawing), per the repository's own rule.
- [ ] **O13** Fix stale `docs/ai/` references to scripts that no longer exist
  or moved.
- [ ] **O14** Verify and retire `configs/cameras-test` if it is unused by any
  `GROUP`, CI job, or documented workflow.
- [ ] **O15** Local housekeeping only: run `git gc` to drop the stray
  `tmp_pack_*` file and consolidate packs (not a repository change).

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
