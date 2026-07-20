#!/bin/sh

. /var/www/x/auth.sh
require_auth

printf 'Status: 200 OK\n'
printf 'Content-Type: application/json\n'
printf 'Cache-Control: no-store\n'
printf 'Connection: close\n'
printf '\n'
printf '{"status":"ok","message":"MQTT subscription service restart initiated"}\n'

/etc/init.d/S91mqttsub restart >/dev/null 2>&1 &
