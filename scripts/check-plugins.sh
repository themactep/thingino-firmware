#!/bin/sh
# Validate all webui plugin manifests in the source tree.
#
# Usage:
#   scripts/check-plugins.sh
#
# Scans package/*/files/*.webui.json, copies them into a temporary
# staging directory, and runs the assembly validator in --check-only
# mode.  Reports duplicate names, page conflicts, and malformed JSON.
# The pages and page scripts of the same packages are staged beside the
# manifests, so the pages listed for in-place navigation are checked as
# the image build checks them.
# Does not require a CAMERA= to be set.

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

ASSEMBLY_SCRIPT="$REPO_ROOT/package/thingino-webui/scripts/assemble_plugins.py"

if [ ! -f "$ASSEMBLY_SCRIPT" ]; then
	echo "ERROR: Assembly script not found at $ASSEMBLY_SCRIPT" >&2
	exit 1
fi

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

mkdir -p "$tmpdir/var/www/a/plugins"

# Copy a package's pages and page scripts into the staging directory
stage_www() {
	[ -d "$1" ] || return 0
	for f in "$1"/*.html "$1"/a/*.js; do
		[ -f "$f" ] || continue
		case "$f" in
			*.html) cp "$f" "$tmpdir/var/www/" ;;
			*) cp "$f" "$tmpdir/var/www/a/" ;;
		esac
	done
}

# Collect all plugin manifests from the package tree
count=0
while IFS= read -r manifest; do
	[ -n "$manifest" ] || continue
	cp "$manifest" "$tmpdir/var/www/a/plugins/"
	stage_www "$(dirname "$manifest")/www"
	count=$((count + 1))
done <<EOF
$(find "$REPO_ROOT/package" -maxdepth 3 -name '*.webui.json' 2>/dev/null)
EOF

if [ "$count" -eq 0 ]; then
	echo "No webui plugin manifests found in package/"
	exit 0
fi

# The webui package's own pages go in last: where a plugin ships a page of
# the same name, the core list is checked against the core page.
stage_www "$REPO_ROOT/package/thingino-webui/files/www"

echo "Found $count plugin manifest(s):"
for f in "$tmpdir/var/www/a/plugins"/*.webui.json; do
	echo "  $(basename "$f")"
done

python3 "$ASSEMBLY_SCRIPT" --check-only "$tmpdir"
ret=$?

if [ "$ret" -eq 0 ]; then
	echo "All plugin manifests are valid."
else
	echo "Plugin manifest validation FAILED." >&2
	exit $ret
fi
