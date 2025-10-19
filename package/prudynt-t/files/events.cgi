#!/bin/sh
# BusyBox httpd CGI for server-sent events (SSE)

echo "Cache-Control: no-cache"
echo "Content-Type: text/event-stream"
echo

# Stream prudynt events, converting lines to SSE frames
prudyntctl events | sed -u 's/^/data: /' | while IFS= read -r line; do
	echo "$line"
	echo
done

