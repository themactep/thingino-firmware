#!/bin/sh

# Return daynightd's current sensor sample as JSON.
# Data source: /run/thingino/daynight_sensors (written by daynightd)

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

if [ -r /run/thingino/daynight_sensors ]; then
	cat /run/thingino/daynight_sensors
else
	printf '{}\n'
fi
