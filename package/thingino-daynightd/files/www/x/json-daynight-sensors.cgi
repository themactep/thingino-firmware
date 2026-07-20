#!/bin/sh

# Return daynightd sensor data + brightness % thresholds from config.
# The % thresholds are merged in for backward compat with older daynightd
# binaries that don't write night_threshold_pct / day_threshold_pct yet.

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n\r\n'

if [ ! -r /run/thingino/daynight_sensors ]; then
	printf '{}\n'
	exit 0
fi

tmp=$(mktemp)
cat /run/thingino/daynight_sensors >"$tmp"

# Merge brightness % thresholds from config if daynightd hasn't written them
if command -v jct >/dev/null 2>&1 && [ -f /etc/thingino.json ]; then
	for key in night_threshold day_threshold; do
		# Only add if the pct field isn't already present
		if ! jct "$tmp" get "${key}_pct" >/dev/null 2>&1; then
			val=$(jct /etc/thingino.json get "daynight.$key" 2>/dev/null | tr -d '\n\r" ')
			if [ -n "$val" ] && [ "$val" != "null" ] && [ "$val" != "0" ]; then
				jct "$tmp" set "${key}_pct" "$val" >/dev/null 2>&1
			fi
		fi
	done
fi

cat "$tmp"
rm -f "$tmp"
