#!/bin/bash
#
# Post-build check: ensure no init script passes long options to busybox
# applets whose long-option support is compiled out.
#
# Thingino disables CONFIG_LONG_OPTS globally and per-applet
# FEATURE_*_LONG_OPTIONS. Scripts that use --long-option syntax with these
# applets will fail at runtime with "invalid option -- -".
#
# This script runs as a post-build hook. Set FATAL=1 to abort the build
# on violations (default: warn only).
#
# Usage:
#   scripts/check-busybox-lopts.sh <target-dir> [fatal]

TARGET_DIR="${1:-}"
FATAL="${2:-0}"

if [ -z "$TARGET_DIR" ] || [ ! -d "$TARGET_DIR" ]; then
	echo "Usage: $0 <target-dir> [fatal]" >&2
	exit 1
fi

INIT_DIR="${TARGET_DIR}/etc/init.d"
if [ ! -d "$INIT_DIR" ]; then
	exit 0
fi

FOUND=0

# ---------------------------------------------------------------------------
# start-stop-daemon — long options disabled in our busybox config
# ---------------------------------------------------------------------------
SSD_LONG_OPTS="start|stop|background|make-pidfile|pidfile|exec|test|quiet|oknodo|verbose|nicelevel|user|name|signal|chuid|chdir|startas|output|remove-pidfile"

SSD_RE="start-stop-daemon.*--(${SSD_LONG_OPTS})"

# ---------------------------------------------------------------------------
# If other applets are discovered to break, add patterns here.
# Pattern format: <applet_regex>|<long_opts_regex>
# e.g.: "udhcpc.*--(retries|timeout|tryagain)"
# ---------------------------------------------------------------------------

check_script() {
	local file="$1"
	local basename
	basename=$(basename "$file")

	while IFS='|' read -r applet_re long_opts; do
		[ -z "$applet_re" ] && continue
		if grep -qE "${applet_re}.*--(${long_opts})" "$file" 2>/dev/null; then
			local matches
			matches=$(grep -nE "${applet_re}.*--(${long_opts})" "$file" 2>/dev/null)
			echo "  $file:" >&2
			echo "$matches" | while IFS= read -r line; do
				echo "    $line" >&2
			done
			FOUND=1
		fi
	done <<'EOF'
start-stop-daemon[[:space:]]|start|stop|background|make-pidfile|pidfile|exec|test|quiet|oknodo|verbose|nicelevel|user|name|signal|chuid|chdir|startas|output|remove-pidfile
EOF
}

echo "=== Checking for long-option usage in init scripts ===" >&2

for script in "$INIT_DIR"/S* "$INIT_DIR"/K*; do
	[ -f "$script" ] || [ -L "$script" ] || continue
	check_script "$script"
done

if [ "$FOUND" -eq 1 ]; then
	echo "" >&2
	echo "ERROR: Some init scripts use long options with busybox applets" >&2
	echo "       that have long-option support compiled out." >&2
	echo "       These scripts will fail at runtime with 'invalid option -- -'." >&2
	echo "       Replace --long-option with the equivalent short option (-X)." >&2
	if [ "$FATAL" = "1" ]; then
		echo "" >&2
		echo "Build aborted due to long-option violations." >&2
		exit 1
	fi
fi

exit 0
