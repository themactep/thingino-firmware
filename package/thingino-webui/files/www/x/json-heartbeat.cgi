#!/bin/sh
. ./_json.sh
LOCKFILE=/tmp/heartbeat
http_200
json_header
if [ -f $LOCKFILE ]; then
	printf '{"error":"Another request is in progress"}'
	exit 0
fi
touch $LOCKFILE
printf '{"time_now":"%s","timezone":"%s","mem_total":"%d","mem_active":"%d","mem_buffers":"%d","mem_cached":"%d","mem_free":"%d","overlay_total":"%d","overlay_used":"%d","overlay_free":"%d","extras_total":"%d","extras_used":"%d","extras_free":"%d","daynight_value":"%d","uptime":"%s"}' \
	"$(date +%s)" \
	"$(cat /etc/timezone)" \
	"$(awk '/^MemTotal:/{print $2}' /proc/meminfo)" \
	"$(awk '/^Active:/{print $2}' /proc/meminfo)" \
	"$(awk '/^Buffers:/{print $2}' /proc/meminfo)" \
	"$(awk '/^Cached:/{print $2}' /proc/meminfo)" \
	"$(awk '/^MemFree:/{print $2}' /proc/meminfo)" \
	$(df | awk '/\/overlay$/{print $2,$3,$4}') \
	$(df | awk '/\/opt$/{print $2,$3,$4}') \
	"$(imp-control gettotalgain)" \
	"$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss\n",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)"
[ -f $LOCKFILE ] && rm $LOCKFILE
exit 0
