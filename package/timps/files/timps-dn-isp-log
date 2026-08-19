#!/bin/sh
# day/night exposure-index measurement - see scripts/dn-isp-probe.sh in timps
# Prefer the SD card so a reboot does not discard the series (/tmp is tmpfs).
# Deliberately NOT falling back to the /etc overlay: this runs once a MINUTE,
# and 1440 jffs2 writes a day would trade a rare reboot for certain flash wear.
# Boards without an SD card keep /tmp and get fetched more promptly instead.
OUT=""
for d in /mnt/mmcblk0p1 /media/mmcblk0p1 /sdcard; do
  [ -d "$d" ] && [ -w "$d" ] && { OUT="$d/dn-isp.csv"; break; }
done
[ -n "$OUT" ] || OUT=/tmp/dn-isp.csv
# carry over whatever the earlier /tmp-only version already collected
[ -f /tmp/dn-isp.csv ] && [ ! -f "$OUT" ] && cp /tmp/dn-isp.csv "$OUT" 2>/dev/null
MAX=4000                      # ~66 h at one sample a minute, ~250 KB
# T31 exposes isp-m0, T20 only isp_info; the field names match, but T20 has no
# max integration time, so that column stays empty there.
D=$(cat /proc/jz/isp/isp-m0 2>/dev/null)
[ -n "$D" ] || D=$(cat /proc/jz/isp/isp_info 2>/dev/null)
[ -n "$D" ] || exit 0
[ -f "$OUT" ] || echo "epoch,mode,int,max_int,again,dgain,ispdgain" > "$OUT"
[ "$(wc -l < "$OUT")" -lt "$MAX" ] || exit 0
f() { echo "$D" | sed -n "s/^$1 : *\([0-9]*\).*/\1/p" | head -1; }
M=$(echo "$D" | sed -n 's/.*ISP Runing Mode : *//p' | tr -d ' \r' | head -1)
ROW="$(date +%s),${M:-?},$(f 'SENSOR Integration Time'),$(f 'SENSOR Max Integration Time'),$(f 'SENSOR analog gain'),$(f 'SENSOR digital gain'),$(f 'ISP digital gain')"
echo "$ROW" >> "$OUT"

# Optional syslog copy - OFF by default: this runs once a MINUTE.
#   jct /etc/thingino.json set dnlog.isp_syslog true|false
# The local CSV is written either way and stays authoritative (syslog is UDP).
[ "$(jct /etc/thingino.json get dnlog.isp_syslog 2>/dev/null)" = "true" ] &&
	logger -t dnisp "$ROW" 2>/dev/null
