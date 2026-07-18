#!/usr/bin/env bash
#
# worktree.sh - manage git worktrees for parallel Thingino development
#
# One task, one branch, one worktree, one agent.
#
# Usage:
#   scripts/worktree.sh create <branch> [base]   Create worktree + init buildroot + patches + shared dl
#   scripts/worktree.sh sync [base]              Rebase current worktree branch onto origin/<base>
#   scripts/worktree.sh remove <branch|path>     Remove a worktree (branch is preserved)
#   scripts/worktree.sh list                     List all worktrees
#
# See docs/worktrees.md for the full workflow.

set -euo pipefail

usage() {
	sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'
	exit 1
}

die() {
	echo "ERROR: $*" >&2
	exit 1
}

# Default base branch: origin HEAD, falling back to master
default_base() {
	git symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null | sed 's|^origin/||' || echo master
}

repo_root() {
	git rev-parse --show-toplevel 2>/dev/null || die "not inside a git repository"
}

git_common_dir() {
	local d
	d="$(git rev-parse --git-common-dir)"
	(cd "$d" && pwd)
}

# Apply Thingino buildroot override patches to a worktree's buildroot submodule.
# Mirrors the apply loop of `make update` (idempotent: skips already-applied).
apply_buildroot_patches() {
	local wt="$1"
	local patch_dir="$wt/package/all-patches/buildroot"
	[ -d "$patch_dir" ] || {
		echo "No buildroot override patch directory: $patch_dir"
		return 0
	}
	local patch
	for patch in $(find "$patch_dir" -maxdepth 1 -type f -name '*.patch' | LC_ALL=C sort); do
		if git -C "$wt/buildroot" apply --check "$patch" 2>/dev/null; then
			echo "Applying $(basename "$patch")"
			git -C "$wt/buildroot" apply "$patch"
		elif git -C "$wt/buildroot" apply -R --check "$patch" 2>/dev/null; then
			echo "Already applied: $(basename "$patch")"
		else
			die "failed to apply buildroot patch: $patch"
		fi
	done
}

cmd_create() {
	local branch="${1:?Usage: $0 create <branch> [base]}"
	local base="${2:-$(default_base)}"
	local root name safe wt_path common ref

	root="$(repo_root)"
	common="$(git_common_dir)"
	name="$(basename "$root")"
	safe="${branch//\//-}"
	wt_path="$(dirname "$root")/${name}-${safe}"

	case "$wt_path" in
		*" "*) die "worktree path contains spaces (dep_check.sh forbids this): $wt_path" ;;
	esac
	[ -e "$wt_path" ] && die "target already exists: $wt_path"

	echo "Branch:   $branch"
	echo "Base:     $base"
	echo "Worktree: $wt_path"
	echo ""

	git fetch origin 2>/dev/null || echo "(no remote or offline -- skipping fetch)"

	# New branch from base, or check out an existing branch
	git worktree add -b "$branch" "$wt_path" "$base" 2>/dev/null ||
		git worktree add "$wt_path" "$branch"

	echo ""
	echo "=== INITIALIZING BUILDROOT SUBMODULE ==="
	ref="$common/modules/buildroot"
	if [ -d "$ref" ]; then
		# Share objects with the main checkout's submodule store (no re-download)
		git -C "$wt_path" submodule update --init --reference "$ref" -- buildroot
	else
		git -C "$wt_path" submodule update --init -- buildroot
	fi

	echo ""
	echo "=== APPLYING BUILDROOT OVERRIDES ==="
	apply_buildroot_patches "$wt_path"

	echo ""
	echo "=== SHARING DOWNLOAD CACHE ==="
	if [ -e "$root/dl" ] && [ ! -e "$wt_path/dl" ]; then
		ln -s "$root/dl" "$wt_path/dl"
		echo "Symlinked $wt_path/dl -> $root/dl"
	else
		echo "No dl/ in main checkout (or already present) -- export BR2_DL_DIR to share downloads"
	fi

	echo ""
	echo "Worktree ready: $wt_path"
	echo ""
	echo "Not carried over (gitignored, set up manually if needed):"
	echo "  local.mk overrides/ user/ .selected_camera"
	echo ""
	echo "Next steps:"
	echo "  cd $wt_path"
	echo "  CAMERA=<camera_name> make fast"
	echo ""
	echo "Do NOT run 'make update' in this worktree; use 'scripts/worktree.sh sync' instead."
}

cmd_sync() {
	local base="${1:-$(default_base)}"
	local branch root

	root="$(repo_root)"
	branch="$(git rev-parse --abbrev-ref HEAD)"

	if [ "$branch" = "$base" ]; then
		echo "Already on $base -- nothing to sync."
		exit 0
	fi

	# Refuse a dirty tree (patched buildroot submodule content is expected -- ignore it)
	if ! git diff --quiet --ignore-submodules=dirty ||
		! git diff --cached --quiet --ignore-submodules=dirty; then
		echo "ERROR: uncommitted changes detected. Commit a checkpoint first:" >&2
		echo "  git add -A && git commit -m 'checkpoint: work in progress'" >&2
		exit 1
	fi

	echo "Syncing '$branch' onto 'origin/$base'..."
	git fetch origin
	git rebase "origin/$base" --autostash

	echo ""
	echo "=== SYNCING BUILDROOT SUBMODULE ==="
	git submodule update -- buildroot
	apply_buildroot_patches "$root"

	echo ""
	echo "Done. '$branch' is up to date with origin/$base."
	echo "When ready to push: git push --force-with-lease origin $branch"
}

cmd_remove() {
	local target="${1:?Usage: $0 remove <branch|path>}"
	local root name safe wt_path

	root="$(repo_root)"
	name="$(basename "$root")"

	if [ -d "$target" ]; then
		wt_path="$(cd "$target" && pwd)"
	else
		safe="${target//\//-}"
		wt_path="$(dirname "$root")/${name}-${safe}"
		[ -d "$wt_path" ] || die "no such worktree: $target ($wt_path)"
	fi
	[ "$wt_path" = "$root" ] && die "refusing to remove the main worktree"

	echo "Worktree: $wt_path"
	echo "Branch:   $(git -C "$wt_path" rev-parse --abbrev-ref HEAD)"
	echo ""
	echo "This deletes the directory, including untracked files (output/, logs)."
	echo "The branch and its commits are preserved in git."
	git -C "$wt_path" status --short --ignore-submodules=dirty | head -20
	printf "Proceed? [y/N] "
	read -r answer
	case "$answer" in
		y | Y) ;;
		*)
			echo "Aborted."
			exit 0
			;;
	esac

	# git refuses to remove worktrees with populated submodules -- deinit first
	git -C "$wt_path" submodule deinit -f -- buildroot 2>/dev/null || true
	git worktree remove --force "$wt_path"
	git worktree prune
	echo "Removed. Branch preserved -- delete it with: git branch -D <branch>"
}

cmd_list() {
	git worktree list
}

case "${1:-}" in
	create)
		shift
		cmd_create "$@"
		;;
	sync)
		shift
		cmd_sync "$@"
		;;
	remove)
		shift
		cmd_remove "$@"
		;;
	list)
		cmd_list
		;;
	*)
		usage
		;;
esac
