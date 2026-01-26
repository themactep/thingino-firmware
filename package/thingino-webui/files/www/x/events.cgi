#!/bin/sh
# BusyBox httpd CGI for server-sent events (SSE)

printf "Cache-Control: no-cache\r\n"
printf "Content-Type: text/event-stream\r\n"
printf "\r\n"

# Stream prudynt events, converting lines to SSE frames
prudyntctl events | sed -u 's/^/data: /' | while IFS= read -r line; do
	echo "$line"
	echo
done

