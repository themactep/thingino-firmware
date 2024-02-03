#!/bin/sh

plugin="snapshot"

. /usr/sbin/common-plugins
singleton

show_help() {
	echo "Usage: $0 [-v] [-h] [-f] [-r]
  -f   Saving a new snapshot, no matter what.
  -r   Use HEIF image format.
  -v   Verbose output.
  -h   Show this help.
"
	exit 0
}

get_snapshot() {
	log "Trying to save a snapshot."
	LIMIT_ATTEMPTS=$(( LIMIT_ATTEMPTS - 1 ))

	command="curl --verbose"
	command="${command} --connect-timeout ${curl_timeout}"
	command="${command} --max-time ${curl_timeout}"
	command="${command} --silent --fail"
	command="${command} --url ${snapshot_url}?t=$(date +"%s") --output ${snapshot}"
	log "$command"
	if $command >>"$LOG_FILE"; then
		log "Snapshot saved to ${snapshot}."
		quit_clean 0
	fi

	if [ "$LIMIT_ATTEMPTS" -le 0 ]; then
		log "Maximum amount of retries reached."
		quit_clean 2
	else
		log "${LIMIT_ATTEMPTS} attempts left."
		sleep 1
		get_snapshot
	fi
}

SECONDS_TO_EXPIRE=120
LIMIT_ATTEMPTS=5

while getopts fhrv flag; do
	case "$flag" in
		f)
			force="true"
			;;
		r)
			use_heif="true"
			;;
		v)
			verbose="true"
			;;
		h|*)
			show_help
			;;
	esac
done

if [ "true" = "$use_heif" ] && [ "h265" = "$(yaml-cli -g .video0.codec)" ]; then
	snapshot="/tmp/snapshot4cron.heif"
	snapshot_url="http://127.0.0.1/image.heif"
else
	snapshot="/tmp/snapshot4cron.jpg"
	snapshot_url="http://127.0.0.1/image.jpg"
fi

if [ "true" = "$force" ]; then
	log "Enforced run."
	get_snapshot
elif [ ! -f "$snapshot" ]; then
	log "Snapshot not found."
	get_snapshot
elif [ "$(date -r "$snapshot" +%s)" -le "$(( $(date +%s) - SECONDS_TO_EXPIRE ))" ]; then
	log "Snapshot is expired."
	rm $snapshot
	get_snapshot
else
	log "Snapshot is up to date."
	sleep 2
	quit_clean 0
fi

[ "true" = "$verbose" ] && cat "$LOG_FILE"

exit 0
