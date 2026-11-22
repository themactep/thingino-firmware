#!/bin/sh
# shellcheck disable=SC1091

. /var/www/x/auth.sh
require_auth

. /var/www/x/timps-heartbeat.sh

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

timps_heartbeat_payload
