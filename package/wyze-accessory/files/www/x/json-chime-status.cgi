#!/bin/sh
#
# json-chime-status.cgi – check whether any chimes are configured
#
# Returns {"configured": true} or {"configured": false}.
# Used by the web UI to show a warning banner when the doorbell
# feature is installed but no chimes have been paired.
#

. /var/www/x/auth.sh
require_auth

count=$(jct /etc/thingino.json path '$.chime.units.*~' --mode paths 2>/dev/null | grep -c '"')
if [ "$count" -gt 0 ]; then
	value=true
else
	value=false
fi

printf 'Content-Type: application/json\n'
printf 'Cache-Control: no-cache\n'
printf 'Connection: close\n\n'
printf '{"configured":%s}\n' "$value"
