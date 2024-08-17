#!/bin/sh
# shellcheck disable=SC2039

mem_total=$(awk '/^MemTotal:/ {print $2}' /proc/meminfo)
mem_free=$(awk '/^MemFree:/ {print $2}' /proc/meminfo)
mem_active=$(awk '/^Active:/ {print $2}' /proc/meminfo)
mem_buffers=$(awk '/^Buffers:/ {print $2}' /proc/meminfo)
mem_cached=$(awk '/^Cached:/ {print $2}' /proc/meminfo)
timenow=$(date +%s)
timezone=$(cat /etc/timezone)
overlay_total=$(df | grep /overlay | xargs | cut -d' ' -f2)
overlay_used=$(df | grep /overlay | xargs | cut -d' ' -f3)
overlay_free=$(df | grep /overlay | xargs | cut -d' ' -f4)
daynight_value=$(imp-control gettotalgain)
uptime=$(awk '{m=$1/60; h=m/60; printf "%sd %sh %sm %ss\n", int(h/24), int(h%24), int(m%60), int($1%60) }' /proc/uptime)
payload=$(printf '{"time_now":"%s","timezone":"%s","mem_total":"%d","mem_active":"%d","mem_buffers":"%d","mem_cached":"%d","mem_free":"%d","overlay_total":"%d","overlay_used":"%d","overlay_free":"%d","daynight_value":"%d","uptime":"%s"}' "$timenow" "$timezone" "$mem_total" "$mem_active" "$mem_buffers" "$mem_cached" "$mem_free" "$overlay_total" "$overlay_used" "$overlay_free" "$daynight_value" "$uptime")

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

$payload
"
