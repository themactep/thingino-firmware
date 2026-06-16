#!/bin/bash
#
# build-all-lean.sh - Build all cameras one by one, keeping only output/images/
#                     after each build to conserve disk space.
#
set -euo pipefail

BR2_EXTERNAL="$(cd "$(dirname "$0")/.." && pwd)"
OUTPUT_ROOT="$BR2_EXTERNAL/output"
GIT_BRANCH="$(cd "$BR2_EXTERNAL" && git rev-parse --abbrev-ref HEAD | tr -d '()' | xargs)"
CAMERA_SUBDIR="$BR2_EXTERNAL/configs/cameras"

log_dir="$HOME/output-$GIT_BRANCH/build-all-lean-logs-$(date +%Y%m%d-%H%M%S)"
mkdir -p "$log_dir"
echo "Logs will be saved to: $log_dir"

failed_cameras=""
total=0
success=0
failed=0

for camera_dir in "$CAMERA_SUBDIR"/*; do
	if [ -d "$camera_dir" ]; then
		camera=$(basename "$camera_dir")
		total=$((total + 1))
		log_file="$log_dir/$camera.log"

		echo ""
		echo "========================================"
		echo "Building camera $total: $camera"
		echo "Log: $log_file"
		echo "========================================"

		if env -u OUTPUT_DIR make -C "$BR2_EXTERNAL" CAMERA="$camera" distclean defconfig build_fast pack 2>&1 | tee "$log_file"; then
			echo "  SUCCESS: $camera" | tee -a "$log_file"
			success=$((success + 1))
		else
			echo "  FAILED: $camera" | tee -a "$log_file"
			failed=$((failed + 1))
			failed_cameras="${failed_cameras}${camera}\n"
		fi

		# Prune output: delete everything except images/
		output_branch_dir="$OUTPUT_ROOT/$GIT_BRANCH"
		for candidate in "$output_branch_dir"/"$camera"-*; do
			if [ -d "$candidate" ]; then
				echo "Pruning: $candidate (keeping only images/)" | tee -a "$log_file"
				find "$candidate" -maxdepth 1 -mindepth 1 ! -name images -exec rm -rf {} +
			fi
		done
	fi
done

echo ""
echo "========================================" | tee "$log_dir/summary.log"
echo "BUILD SUMMARY" | tee -a "$log_dir/summary.log"
echo "========================================" | tee -a "$log_dir/summary.log"
echo "Total cameras: $total" | tee -a "$log_dir/summary.log"
echo "Successful: $success" | tee -a "$log_dir/summary.log"
echo "Failed: $failed" | tee -a "$log_dir/summary.log"
echo "Logs saved to: $log_dir" | tee -a "$log_dir/summary.log"
if [ "$failed" -gt 0 ]; then
	echo "" | tee -a "$log_dir/summary.log"
	echo "Failed cameras:" | tee -a "$log_dir/summary.log"
	printf "%b" "$failed_cameras" | tee -a "$log_dir/summary.log"
	exit 1
fi
