#!/bin/sh
. ./_json.sh

if [ "true" = "$(fw_printenv -n wlanap_enabled)" ]; then
	[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
	now=$(date +%s)
	ys=31557600

	[ -z "$ts" ] && json_error "Missing required parameter 'ts'."
	[ "$ts" -lt $now ] && json_error "Cannot go back in time: $ts"
	[ "$ts" -gt $((now + ys)) ] && json_error "Time gap is more that a year. It's time to upgrade!"

	date -s "$ts"
	json_ok "Camera time synctronized from the browser. Time is $(date)"
else
	if ntpd -n -q -N; then
		json_ok "Camera time synchronized with NTP server. Time is $(date)"
	else
		json_error "Synchronization failed!"
	fi
fi

