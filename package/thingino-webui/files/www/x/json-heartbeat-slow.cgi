#!/bin/sh

# Slow heartbeat proxied from Thingino agent

. /var/www/x/auth.sh
require_auth

. /usr/libexec/thingino-webui/heartbeat-lib.sh

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

thingino_heartbeat_payload
