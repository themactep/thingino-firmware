#!/bin/sh
# Thin relay: pipes SSE from prudynt's internal endpoint to the browser.
# Prudynt handles polling + SSE framing; this CGI only adds auth + headers.

. /var/www/x/auth.sh
require_auth

printf 'Status: 200 OK\r\n'
printf 'Content-Type: text/event-stream\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: keep-alive\r\n'
printf 'Pragma: no-cache\r\n'
printf 'Expires: 0\r\n\r\n'

exec curl -sS -N --max-time 0 \
	-H 'Accept: text/event-stream' \
	http://localhost:8080/api/v1/osd-sei
