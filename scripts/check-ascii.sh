#!/bin/sh
# Fail if a tracked shell script contains non-ASCII characters.
set -eu

root=$(CDPATH='' cd -- "$(dirname -- "$0")/.." && pwd)
failed=0

if ! printf 'a\n' | LC_ALL=C grep -qP 'a'; then
	echo "grep -P is required for the ASCII check" >&2
	exit 1
fi

# Paths contain no whitespace (enforced by dep_check.sh).
# shellcheck disable=SC2046
for f in $(git -C "$root" ls-files '*.sh'); do
	if hits=$(LC_ALL=C grep -nP '[^\x00-\x7F]' "$root/$f"); then
		echo "NON-ASCII: $f" >&2
		printf '%s\n' "$hits" | head -3 >&2
		failed=1
	fi
done

if [ "$failed" -ne 0 ]; then
	echo "Shell scripts must be ASCII only." >&2
	exit 1
fi
echo "Shell scripts are ASCII only."
