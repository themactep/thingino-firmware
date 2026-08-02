#!/bin/sh
# SSE bridge: polls prudynt :8080/api/v1/osd-sei and streams as text/event-stream.
# Client connects once and receives push updates — no HTTP polling overhead.

PRUDYNT="http://127.0.0.1:8080/api/v1/osd-sei"
INTERVAL=1

printf "Content-Type: text/event-stream\r\n"
printf "Cache-Control: no-cache\r\n"
printf "Connection: keep-alive\r\n"
printf "\r\n"

last=""
while true; do
	data=$(curl -sS --connect-timeout 2 --max-time 3 "$PRUDYNT" 2>/dev/null) || data=""
	if [ -n "$data" ] && [ "$data" != "$last" ]; then
		printf "data: %s\n\n" "$data"
		last="$data"
	fi
	sleep "$INTERVAL"
done
