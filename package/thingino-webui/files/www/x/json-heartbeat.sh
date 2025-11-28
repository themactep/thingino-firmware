#!/bin/sh

printf 'Content-Type: text/event-stream\r\n'
printf 'Cache-Control: no-cache\r\n\r\n'

while true; do
    TIME_NOW=$(date +%s)
    TIMEZONE=$(cat /etc/timezone 2>/dev/null || echo "$(date +%Z)")
    MEM_TOTAL=$(awk '/^MemTotal:/{print $2}' /proc/meminfo)
    MEM_ACTIVE=$(awk '/^Active:/{print $2}' /proc/meminfo)
    MEM_BUFFERS=$(awk '/^Buffers:/{print $2}' /proc/meminfo)
    MEM_CACHED=$(awk '/^Cached:/{print $2}' /proc/meminfo)
    MEM_FREE=$(awk '/^MemFree:/{print $2}' /proc/meminfo)
    OVERLAY_TOTAL=0; OVERLAY_USED=0; OVERLAY_FREE=0
    OPT_TOTAL=0; OPT_USED=0; OPT_FREE=0
    set -- $(df | awk '/\/overlay$/{print $2, $3, $4}')
    OVERLAY_TOTAL=$1; OVERLAY_USED=$2; OVERLAY_FREE=$3
    set -- $(df | awk '/\/opt$/{print $2, $3, $4}')
    OPT_TOTAL=$1; OPT_USED=$2; OPT_FREE=$3
    EXTRAS_TOTAL=$OPT_TOTAL
    EXTRAS_USED=$OPT_USED
    EXTRAS_FREE=$OPT_FREE
    DAYNIGHT_VALUE=$(imp-control gettotalgain 2>/dev/null || echo -1)
    UPTIME=$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)

    printf 'data: {"time_now":"%s","timezone":"%s","mem_total":"%s","mem_active":"%s","mem_buffers":"%s","mem_cached":"%s","mem_free":"%s","overlay_total":"%s","overlay_used":"%s","overlay_free":"%s","extras_total":"%s","extras_used":"%s","extras_free":"%s","daynight_value":"%s","uptime":"%s"}\n\n' \
        "$TIME_NOW" "$TIMEZONE" "$MEM_TOTAL" "$MEM_ACTIVE" "$MEM_BUFFERS" "$MEM_CACHED" "$MEM_FREE" \
        "$OVERLAY_TOTAL" "$OVERLAY_USED" "$OVERLAY_FREE" \
        "$EXTRAS_TOTAL" "$EXTRAS_USED" "$EXTRAS_FREE" \
        "$DAYNIGHT_VALUE" "$UPTIME"

    sleep 2
done
