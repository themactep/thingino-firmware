#!/bin/bash
# make-bundle.sh — Produce a .tgz (Thingino Package Bundle) from a built package.
#
# Usage:
#   ./scripts/make-bundle.sh <package> <camera> <output-dir>
#   make bundle-<pkg> CAMERA=<camera>
#
# Requires a <package>.bundle file in package/<package>/ listing one file
# path per line (relative to target root).
#
# Example:
#   CAMERA=atom_cam2_t31x_gc2053_atbm6031 make
#   make bundle-go2rtc CAMERA=atom_cam2_t31x_gc2053_atbm6031
#
# Output:
#   <output-dir>/bundles/go2rtc-1.9.14-t31.tgz

set -eu

BR2_EXTERNAL="$(cd "$(dirname "$0")/.." && pwd)"

PKG_NAME="$1"
CAMERA="$2"
OUTPUT_DIR="$3"

[ -z "$PKG_NAME" ] && { echo "Usage: $0 <package> <camera> <output-dir>"; exit 1; }
[ -z "$CAMERA" ] && { echo "Usage: $0 <package> <camera> <output-dir>"; exit 1; }
[ -z "$OUTPUT_DIR" ] && { echo "Usage: $0 <package> <camera> <output-dir>"; exit 1; }
[ -d "$OUTPUT_DIR" ] || { echo "ERROR: output directory not found: $OUTPUT_DIR"; exit 1; }
[ -f "$OUTPUT_DIR/.config" ] || { echo "ERROR: no .config in $OUTPUT_DIR (has the build completed?)"; exit 1; }

# Paths
BUNDLE_FILE="$BR2_EXTERNAL/package/$PKG_NAME/$PKG_NAME.bundle"
[ -f "$BUNDLE_FILE" ] || { echo "ERROR: $BUNDLE_FILE not found"; exit 1; }

BUNDLE_DIR="$OUTPUT_DIR/bundles"

# Buildroot installs to per-package/<name>/target/ when BR2_PER_PACKAGE_DIRECTORIES=y,
# falling back to the global target/ directory otherwise.
TARGET_DIR="$OUTPUT_DIR/per-package/$PKG_NAME/target"
if [ ! -d "$TARGET_DIR" ]; then
	TARGET_DIR="$OUTPUT_DIR/target"
fi
[ -d "$TARGET_DIR" ] || { echo "ERROR: target directory not found: $TARGET_DIR"; exit 1; }

# Find package version from build directory
PKG_BUILD_DIR=$(ls -d "$OUTPUT_DIR/build/${PKG_NAME}-"* 2>/dev/null | head -1) || true
if [ -n "$PKG_BUILD_DIR" ]; then
	PKG_VERSION=$(basename "$PKG_BUILD_DIR" | sed "s/^${PKG_NAME}-//")
else
	PKG_VERSION="unknown"
	echo "WARNING: package '$PKG_NAME' may not have been built (no build/$PKG_NAME-* found)"
fi

# Determine SOC family from the build config
SOC_MODEL=$(grep '^BR2_INGENIC_SOC_MODEL=' "$OUTPUT_DIR/.config" 2>/dev/null | cut -d'"' -f2)
if [ -z "$SOC_MODEL" ]; then
	SOC_FAMILY="unknown"
	echo "WARNING: cannot determine SOC model from .config"
else
	SOC_FAMILY=$("$BR2_EXTERNAL/scripts/get_soc_params.sh" "$SOC_MODEL" family 2>/dev/null || echo "unknown")
fi

# Read the .bundle file (strip comments and blank lines)
BUNDLE_FILES=$(grep -v '^\s*#' "$BUNDLE_FILE" | grep -v '^\s*$' || true)
[ -z "$BUNDLE_FILES" ] && { echo "ERROR: $BUNDLE_FILE is empty"; exit 1; }

# Create temp work directory
WORK_DIR=$(mktemp -d -t bundle-XXXXX)
trap 'rm -rf "$WORK_DIR"' EXIT

# Find cross-compile strip tool
STRIP=$(ls "$OUTPUT_DIR/host/bin/"*-linux-strip 2>/dev/null | head -1)
if [ -z "$STRIP" ] || [ ! -x "$STRIP" ]; then
	echo "WARNING: strip tool not found, binaries will be unstripped"
	STRIP=""
fi

# Collect files from target directory
echo "Collecting files from $TARGET_DIR..."
FILE_COUNT=0
TOTAL_SIZE=0

while IFS= read -r file; do
	[ -z "$file" ] && continue
	# Strip leading slash if present
	file="${file#/}"

	src="$TARGET_DIR/$file"
	if [ ! -e "$src" ]; then
		# Fall back to global target/ (e.g. for webui files assembled there)
		src="$OUTPUT_DIR/target/$file"
		if [ ! -e "$src" ]; then
			echo "WARNING: file not found: $file"
			continue
		fi
	fi

	dest="$WORK_DIR/$file"
	mkdir -p "$(dirname "$dest")"

	if [ -d "$src" ]; then
		cp -a "$src" "$dest"
	else
		cp -a "$src" "$dest"
		sz=$(stat -c%s "$src" 2>/dev/null || echo 0)
		TOTAL_SIZE=$((TOTAL_SIZE + sz))
	fi

	FILE_COUNT=$((FILE_COUNT + 1))
	echo "  $file"
done <<EOF
$BUNDLE_FILES
EOF

echo "Collected $FILE_COUNT files"

# Strip binaries
if [ -n "$STRIP" ]; then
	echo "Stripping binaries..."
	find "$WORK_DIR" -type f -exec "$STRIP" {} \; 2>/dev/null || true
fi

# Refuse to create an empty bundle
if [ "$FILE_COUNT" -eq 0 ]; then
	echo "ERROR: no files collected from target directory"
	echo "Was the package built? Check that $PKG_NAME is enabled in the config and the build completed."
	exit 1
fi

# Calculate final size
SIZE_KB=$(((TOTAL_SIZE + 1023) / 1024))

# Generate manifest
MANIFEST="$WORK_DIR/.thingino-pkg.json"
cat > "$MANIFEST" <<MANIFEST_EOF
{
  "name": "$PKG_NAME",
  "version": "$PKG_VERSION",
  "soc_family": "$SOC_FAMILY",
  "size_kb": $SIZE_KB
}
MANIFEST_EOF

echo "Manifest:"
cat "$MANIFEST"
echo ""

# Create bundle
mkdir -p "$BUNDLE_DIR"
BUNDLE_NAME="${PKG_NAME}-${PKG_VERSION}-${SOC_FAMILY}.tgz"
BUNDLE_PATH="$BUNDLE_DIR/$BUNDLE_NAME"

echo "Creating $BUNDLE_PATH..."
tar -C "$WORK_DIR" -czf "$BUNDLE_PATH" .

BUNDLE_SIZE=$(stat -c%s "$BUNDLE_PATH" 2>/dev/null || echo 0)
BUNDLE_SIZE_KB=$(((BUNDLE_SIZE + 1023) / 1024))

echo ""
echo "Bundle created: $BUNDLE_PATH"
echo "  Package:    $PKG_NAME $PKG_VERSION"
echo "  SOC family: $SOC_FAMILY"
echo "  Files:      $FILE_COUNT"
echo "  Size:       ${BUNDLE_SIZE_KB} KB"
echo ""
echo "Install on device:"
echo "  scp -O $BUNDLE_PATH root@<camera-ip>:/tmp/"
echo "  ssh root@<camera-ip> thingino-pkg install /tmp/$BUNDLE_NAME"
