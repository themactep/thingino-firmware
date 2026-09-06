#!/bin/sh
# shellcheck disable=SC2086
#
# Build one camera for the build-all target.
#
# Usage: build_all_camera.sh <camera> <log_dir> [make_cmd]
#
# Runs a clean build (distclean/defconfig/build_fast/pack) for one camera,
# writing the output to <log_dir>/<camera>.log and a .ok.<camera> or
# .fail.<camera> marker that the build-all target aggregates into its
# summary. Exits 0 for a build result (success or failure); only a
# genuine infrastructure error is non-zero.

set -eu

camera="$1"
log_dir="$2"
make_cmd="${3:-make}"

log_file="$log_dir/$camera.log"

printf 'Building %s -> %s\n' "$camera" "$log_file"

if env -u OUTPUT_DIR $make_cmd CAMERA="$camera" distclean defconfig build_fast pack >"$log_file" 2>&1; then
	printf '[OK] SUCCESS: %s\n' "$camera" | tee -a "$log_file"
	touch "$log_dir/.ok.$camera"
else
	printf '[FAIL] FAILED: %s\n' "$camera" | tee -a "$log_file"
	touch "$log_dir/.fail.$camera"
fi
