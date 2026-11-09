#!/bin/sh
# shellcheck disable=SC1091
. /var/www/x/auth.sh
require_auth
printf "Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n"
export PATH=/sbin:/usr/sbin:/bin:/usr/bin

f=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*f=\([0-9][0-9]*\).*/\1/p')
if [ -z "$f" ]; then
	echo '{"status":"error","reason":"need f"}'
	exit 0
fi
[ "$f" -lt 1000 ] && f=1000
[ "$f" -gt 8000 ] && f=8000

cur=$(cat /run/raptor-zoom 2>/dev/null)
[ -z "$cur" ] && cur=1000

if [ "$f" -ge "$cur" ]; then
	# more zoom (or same): shrink buffers in place, instant
	raptorctl rvd set-zoom "$f" >/dev/null 2>&1
	printf '{"status":"ok","factor":%s,"mode":"inplace"}\n' "$f"
else
	# less zoom: grow needs a clean re-init; persist and restart the streamer
	echo "$f" >/run/raptor-zoom
	(/etc/init.d/S31raptor restart >/dev/null 2>&1 &)
	printf '{"status":"ok","factor":%s,"mode":"restart"}\n' "$f"
fi
exit 0
