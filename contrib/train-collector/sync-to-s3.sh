#!/bin/sh
# Move finished spool days to an S3-compatible bucket.
#
# A frame is deleted locally only after `aws s3 sync` exits zero, so a failed or
# interrupted run leaves the day in place for the next attempt. The current day
# is never touched: its files are still being written.
#
#   S3_URI=s3://thingino-training/frames ./sync-to-s3.sh
#
# Needs the AWS CLI v2 (or any compatible client that understands `s3 sync`).
set -eu

S3_URI="${S3_URI:?S3_URI is required, e.g. s3://bucket/prefix}"
DATA_DIR="${TRAIN_DATA_DIR:-data}"
KEEP_DAYS="${TRAIN_KEEP_DAYS:-2}"

if ! command -v aws >/dev/null 2>&1; then
	echo "aws CLI not found in PATH" >&2
	exit 1
fi

if [ ! -d "$DATA_DIR/frames" ]; then
	echo "no spool at $DATA_DIR/frames" >&2
	exit 1
fi

cutoff=$(date -u -d "$KEEP_DAYS days ago" +%s)
list=$(mktemp "${TMPDIR:-/tmp}/train-sync.XXXXXX")
trap 'rm -f "$list"' EXIT

find "$DATA_DIR/frames" -mindepth 3 -maxdepth 3 -type d | sort >"$list"

failed=0
while IFS= read -r day_dir; do
	day=$(basename "$day_dir")
	month=$(basename "$(dirname "$day_dir")")
	year=$(basename "$(dirname "$(dirname "$day_dir")")")
	stamp="$year-$month-$day"

	# Keep the last KEEP_DAYS days, including today, on local disk.
	if [ -z "$(date -u -d "$stamp" +%s 2>/dev/null)" ]; then
		echo "skipping unparsable day directory $day_dir" >&2
		continue
	fi
	stamp_epoch=$(date -u -d "$stamp" +%s)
	if [ "$stamp_epoch" -ge "$cutoff" ]; then
		continue
	fi

	relative=${day_dir#"$DATA_DIR"/}
	if aws s3 sync "$day_dir" "$S3_URI/$relative" --only-show-errors; then
		rm -rf "$day_dir"
		echo "synced $relative"
	else
		echo "sync failed for $day_dir, keeping it" >&2
		failed=1
	fi
done <"$list"

[ "$failed" -eq 0 ] || exit 1
exit 0
