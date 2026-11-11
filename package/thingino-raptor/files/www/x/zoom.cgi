#!/bin/sh
# shellcheck disable=SC1091  # auth.sh is installed on the camera, not in the build tree
. /var/www/x/auth.sh
require_auth
printf 'Content-Type: application/json\r\nCache-Control: no-store\r\n\r\n'
export PATH=/sbin:/usr/sbin:/bin:/usr/bin

cur=$(cat /run/raptor-zoom 2>/dev/null)
case "$cur" in
	'' | *[!0-9]*) cur=1000 ;;
esac
[ "$cur" -lt 1000 ] && cur=1000
[ "$cur" -gt 8000 ] && cur=8000

# ?info=1: the page probes support before rendering the buttons. The paired
# raptor build answers get-zoom; older builds have no such command.
case "$QUERY_STRING" in
	*info=1*)
		if raptorctl rvd get-zoom 2>/dev/null | grep -q '"enable"'; then
			supported=true
		else
			supported=false
		fi
		printf '{"status":"ok","supported":%s,"factor":%s}\n' "$supported" "$cur"
		exit 0
		;;
esac

f=$(printf '%s' "$QUERY_STRING" | sed -n 's/.*f=\([0-9][0-9]*\).*/\1/p')
if [ -z "$f" ]; then
	printf '{"status":"error","reason":"need f"}\n'
	exit 0
fi
f=$(printf '%s' "$f" | sed 's/^0*//')
[ -z "$f" ] && f=1000
[ ${#f} -gt 6 ] && f=8000
[ "$f" -lt 1000 ] && f=1000
[ "$f" -gt 8000 ] && f=8000

if [ "$f" -eq "$cur" ]; then
	printf '{"status":"ok","factor":%s,"mode":"none"}\n' "$f"
	exit 0
fi

if [ "$f" -gt "$cur" ]; then
	# more zoom: shrink buffers in place, instant
	if raptorctl rvd set-zoom "$f" >/dev/null 2>&1; then
		printf '{"status":"ok","factor":%s,"mode":"inplace"}\n' "$f"
	else
		printf '{"status":"error","reason":"set-zoom failed"}\n'
	fi
else
	# less zoom: grow needs a clean re-init; persist and restart the streamer
	echo "$f" >/run/raptor-zoom
	(/etc/init.d/S31raptor restart >/dev/null 2>&1 &)
	printf '{"status":"ok","factor":%s,"mode":"restart"}\n' "$f"
fi
exit 0
