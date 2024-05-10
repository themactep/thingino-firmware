#!/bin/sh
# shellcheck disable=SC2039

mem_total=$(awk '/MemTotal/ {print $2}' /proc/meminfo)
mem_free=$(awk '/MemFree/ {print $2}' /proc/meminfo)
mem_used=$(( 100 - (mem_free / (mem_total / 100)) ))
overlay_used=$(df | grep /overlay | xargs | cut -d' ' -f5)
daynight_value=$(imp-control gettotalgain)
uptime=$(awk '{m=$1/60; h=m/60; printf "%sd %sh %sm %ss\n", int(h/24), int(h%24), int(m%60), int($1%60) }' /proc/uptime)
payload=$(printf '{"time_now":"%s","timezone":"%s","mem_used":"%d","overlay_used":"%d","daynight_value":"%d","uptime":"%s"}' \
 	"$(date +%s)" "$(cat /etc/timezone)" "$mem_used" "${overlay_used//%/}" "$daynight_value" "$uptime")

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

$payload
"
