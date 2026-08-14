#!/bin/sh
# Enforce the do-not-edit manifest for generated/vendored files.
#
# Reads newline-separated repo-relative paths from argv or stdin and fails
# when any path matches an entry in scripts/do-not-edit.txt.
#
# Usage:
#   scripts/check-do-not-edit.sh [FILE...]
#   git diff --cached --name-only | scripts/check-do-not-edit.sh

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
MANIFEST="$SCRIPT_DIR/do-not-edit.txt"

if [ ! -f "$MANIFEST" ]; then
	echo "ERROR: do-not-edit manifest not found: $MANIFEST" >&2
	exit 1
fi

failed=0

check_file() {
	file="$1"
	while IFS='|' read -r pattern remediation; do
		case "$pattern" in
			'' | '#'*)
				continue
				;;
		esac
		# Glob matching is the whole point of the manifest.
		# shellcheck disable=SC2254
		case "$file" in
			$pattern)
				echo "do-not-edit: $file"
				echo "  -> $remediation"
				failed=1
				;;
		esac
	done <"$MANIFEST"
}

if [ "$#" -gt 0 ]; then
	for file in "$@"; do
		check_file "$file"
	done
else
	while IFS= read -r file; do
		[ -n "$file" ] || continue
		check_file "$file"
	done
fi

if [ "$failed" -ne 0 ]; then
	echo "do-not-edit check failed: one or more generated files were modified." >&2
	exit 1
fi

exit 0
