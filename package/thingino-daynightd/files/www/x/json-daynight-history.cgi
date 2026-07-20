#!/bin/sh

# Return daynightd history JSON as a JSON array.
# Data source: /run/thingino/daynight_history (written by daynightd)

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

if [ -r /run/thingino/daynight_history ]; then
	cat /run/thingino/daynight_history
else
	printf '[]\n'
fi
