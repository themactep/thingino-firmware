# Git Worktrees for Parallel Thingino Development

A git worktree is a second (third, fourth...) working directory checked out
from the same repository. All worktrees share one `.git` object store and
history, but each has its own checked-out files, its own branch, and its own
build state. An agent or developer working in one worktree cannot see or
corrupt work in another.

This matters most for AI-assisted development: a coding agent builds up
context over a session. Switching branches under a running agent destroys
that context; two agents editing the same directory silently overwrite each
other. The fix is an infrastructure pattern, not a tooling one:

> **One task, one branch, one worktree, one agent.**

(Background reading: [Git Worktrees for AI Development](https://www.kdnuggets.com/git-worktrees-for-ai-development), KDnuggets.)

## Quick start

```bash
# From the main checkout
scripts/worktree.sh create feat/motion-tuning        # branch from origin/master
scripts/worktree.sh create fix/rtsp-crash master     # explicit base
scripts/worktree.sh list

cd ../thingino-firmware-feat-motion-tuning
CAMERA=atom_cam2_t31x_gc2053_atbm6031 make fast

# At checkpoints (inside the worktree)
scripts/worktree.sh sync                             # rebase onto origin/master

# When the PR is merged (from the main checkout)
scripts/worktree.sh remove feat/motion-tuning
git branch -D feat/motion-tuning                     # optional
```

Worktrees are created as siblings of the main checkout:
`<parent>/thingino-firmware-<branch-with-dashes>/`. Paths with spaces are
rejected (`dep_check.sh` forbids them).

## What `scripts/worktree.sh create` does for you

A bare `git worktree add` is **not enough** for this repo. The helper script
performs the Thingino-specific setup that a fresh worktree needs:

1. **Buildroot submodule init.** Submodule working trees are per-worktree.
   The script runs `git submodule update --init --reference` against the main
   checkout's module store (`.git/modules/buildroot`), so no network clone is
   needed and objects are shared via alternates.
2. **Buildroot override patches.** `make update` normally applies the patches
   from `package/all-patches/buildroot/` to the submodule. The script applies
   them directly (idempotently), because you must *not* run `make update` in
   a feature worktree (see below).
3. **Shared download cache.** `BR2_DL_DIR` defaults to `<tree>/dl`, which
   would be empty in a new worktree. If the main checkout has a `dl/`
   directory, the script symlinks it. Buildroot's download logic is safe for
   concurrent use of a shared `dl/`. (Container builds get the dl cache from
   the named volume instead — nothing to do.)

## What is shared vs. per-worktree

| Thing | Shared? | Notes |
|---|---|---|
| Git history / objects / remotes | shared | one `.git`, commits visible everywhere instantly |
| Branch | per-worktree | a branch can only be checked out in **one** worktree at a time |
| `buildroot/` submodule tree | per-worktree | init'd by the script; objects shared via `--reference` |
| `dl/` download cache | shared | symlinked by the script (or `export BR2_DL_DIR`) |
| `output/` | per-worktree | also namespaced by branch: `output/<branch>/<camera>-...` — no collisions |
| ccache (`~/.buildroot-ccache`) | shared | automatic; makes the *second* worktree's "clean" build much faster |
| Toolchain bundles | shared | they live in the dl cache |
| `local.mk`, `overrides/` | **not carried** | gitignored; set up per worktree if needed (see below) |
| `user/` config layers | **not carried** | gitignored; copy or symlink manually, or build with `PRISTINE=1` |
| `.selected_camera` | not carried | pass `CAMERA=` explicitly (agents should always do this) |

## Thingino-specific rules and gotchas

### Never run `make update` in a feature worktree

`make update` starts with `git pull --rebase` on the *current branch* and is
designed for the main checkout tracking `master`. In a feature worktree use:

```bash
scripts/worktree.sh sync        # commit a checkpoint first if dirty
```

This rebases onto `origin/master`, re-syncs the buildroot submodule pointer,
and re-applies the buildroot override patches. Sync at the end of every
significant session — a worktree that drifts for days becomes a merge
project of its own.

### Branch exclusivity

`fatal: '<branch>' is already checked out at ...` means another worktree owns
that branch. Either work there, or remove that worktree first. This is a
feature: it makes the "two agents on one branch" failure mode impossible.

### Container builds from a linked worktree

In a linked worktree, `.git` is a *file* containing an absolute host path
into the main checkout's `.git/worktrees/...`. `build-container.sh` /
`Makefile.container` mount only the current tree at `/workspace`, so git
inside the container cannot resolve the repo — branch detection and
`OUTPUT_DIR` break.

Options, in order of preference:

1. Build on the host in worktrees; use the container from the main checkout.
2. Add an extra mount of the main repository at the **same absolute path**
   inside the container (both `.git` gitfile paths must resolve).

### Package overrides (`local.mk` + `overrides/`)

Override source directories are shared mutable state. Two worktrees pointing
at the same `overrides/<pkg>/` checkout defeats the whole isolation model —
two agents would edit one source tree again. If a worktree task needs an
override, give it its **own** clone under that worktree's `overrides/`
directory and its own `local.mk` entry.

### Disk budget

Per worktree: ~1 GB checkout (incl. buildroot submodule tree, objects shared)
plus several GB of `output/` per camera built. Shared ccache softens rebuild
time, not disk. Remove worktrees when their PR merges; don't hoard them.

### Locking during long builds

A firmware build takes 30+ minutes. Protect a worktree from accidental
pruning while an agent/build is running:

```bash
git worktree lock ../thingino-firmware-feat-x --reason "agent build running"
git worktree unlock ../thingino-firmware-feat-x
```

## Lifecycle

```
create ──► scope task ──► agent works ──► checkpoint commit ──► sync ──► PR ──► remove
                                    ▲                            │
                                    └────────────────────────────┘
```

1. **Create**: `scripts/worktree.sh create <branch>` — one per task.
2. **Scope**: tell the agent, in the session prompt, exactly which worktree
   it owns, the task, and the acceptance criteria. Agents must treat every
   other worktree as read-only foreign territory.
3. **Work**: normal build flow, always with explicit `CAMERA=`. Output and
   logs stay inside the worktree (`output/<branch>/.../logs/`).
4. **Checkpoint**: commit early and often (`checkpoint:` commits are fine;
   squash before the PR). Then `scripts/worktree.sh sync`.
5. **PR**: push with `git push --force-with-lease` after a sync rebase;
   open the PR as usual.
6. **Remove**: `scripts/worktree.sh remove <branch>` from the main checkout.
   The branch and commits survive; only the directory (including its
   `output/`) is deleted. The script asks for confirmation.

## Command reference

| Command | What it does |
|---|---|
| `scripts/worktree.sh create <branch> [base]` | full Thingino-ready worktree (submodule, patches, dl) |
| `scripts/worktree.sh sync [base]` | rebase onto `origin/<base>` + re-sync buildroot |
| `scripts/worktree.sh remove <branch\|path>` | confirm + remove worktree, keep branch |
| `scripts/worktree.sh list` | list all worktrees |
| `git worktree lock/unlock <path>` | protect a worktree during long runs |
| `git worktree prune` | clean metadata after a manual `rm -rf` |
| `git worktree repair` | fix links after moving directories |

## Troubleshooting

| Symptom | Cause | Fix |
|---|---|---|
| `'X' is already checked out` | branch owned by another worktree | work there, or remove that worktree |
| buildroot dir empty in new worktree | submodule not init'd | `scripts/worktree.sh create` does this; manually: `git submodule update --init --reference <main>/.git/modules/buildroot -- buildroot` |
| build fails deep in buildroot with XBurst2/NaN errors | override patches not applied | run the apply loop: `scripts/worktree.sh sync`, or re-create the worktree |
| every package re-downloads | `dl/` not shared | symlink main `dl/` or `export BR2_DL_DIR` |
| git broken inside build container | linked-worktree `.git` gitfile path not mounted | build on host, or mount main repo at same absolute path |
| worktree still listed after `rm -rf` | stale metadata | `git worktree prune` |
| `git worktree remove` refuses | populated submodule / untracked files | `scripts/worktree.sh remove` handles both (deinit + confirm + force) |
