#!/bin/sh
. ./_json.sh

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))

heartbeat_payload() {
	ch0_rec="false"; [ -f "/run/prudynt/mp4ctl-ch0.active" ] && ch0_rec="true"
	ch1_rec="false"; [ -f "/run/prudynt/mp4ctl-ch1.active" ] && ch1_rec="true"

	printf '{"time_now":"%s","timezone":"%s","mem_total":"%d","mem_active":"%d","mem_buffers":"%d","mem_cached":"%d","mem_free":"%d","overlay_total":"%d","overlay_used":"%d","overlay_free":"%d","uptime":"%s","dnd_gain":"%s","dnd_mode":"%s","extras_total":"%d","extras_used":"%d","extras_free":"%d","rec_ch0":%s,"rec_ch1":%s}' \
		"$(date +%s)" \
		"$(cat /etc/timezone)" \
		"$(awk '/^MemTotal:/{print $2}' /proc/meminfo)" \
		"$(awk '/^Active:/{print $2}' /proc/meminfo)" \
		"$(awk '/^Buffers:/{print $2}' /proc/meminfo)" \
		"$(awk '/^Cached:/{print $2}' /proc/meminfo)" \
		"$(awk '/^MemFree:/{print $2}' /proc/meminfo)" \
		$(df | awk '/\/overlay$/{print $2,$3,$4}') \
		"$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss\n",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)" \
		"$(awk '{print $1}' /run/prudynt/daynight_brightness 2>/dev/null || echo "unknown")" \
		"$(awk 'NR==1 {print $1}' /run/prudynt/daynight_mode 2>/dev/null || echo "unknown")" \
		$(df | awk '/\/opt$/{print $2,$3,$4}') \
		"$ch0_rec" \
		"$ch1_rec"
}

send_headers() {
	http_200
	cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

EOF
}

stream_heartbeat() {
	while true; do
		printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0
		printf 'data: %s\n\n' "$(heartbeat_payload)" || exit 0
		sleep "$HEARTBEAT_INTERVAL" || exit 0
	done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_heartbeat
