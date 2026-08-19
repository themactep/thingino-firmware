#!/bin/sh
# Forward NEW lines of the Ingenic alog into syslog. `logcat -t` prefixes each
# line with the event's own epoch time, so the marker is that timestamp: it
# survives a ring wrap, a reboot and a truncated buffer without counting lines.
# The forwarded line keeps its prefix - syslog's own time is the shipping time,
# which for a once-a-minute cron is up to 60 s late.
TAG=logcat
STATE=/tmp/.logcat-ship
DUMP=/tmp/.logcat-dump.$$

trap 'rm -f "$DUMP"' EXIT
logcat -t >"$DUMP" 2>/dev/null || exit 0
[ -s "$DUMP" ] || exit 0

last=0
[ -r "$STATE" ] && read -r last <"$STATE" 2>/dev/null
case "$last" in ''|*[!0-9.]*) last=0 ;; esac

# awk keeps the numeric compare in one pass; the timestamps are epoch seconds
# with a fractional part, so a string compare would be wrong.
awk -v last="$last" '$1 + 0 > last + 0' "$DUMP" | while IFS= read -r line; do
	[ -n "$line" ] && logger -t "$TAG" "$line"
done

newest=$(awk 'BEGIN{m=0} $1 + 0 > m + 0 {m = $1} END{print m}' "$DUMP")
[ -n "$newest" ] && printf '%s\n' "$newest" >"$STATE"
