#!/bin/sh
# shellcheck disable=SC1091
# Parse /proc/jz/isp/isp-fs (frame source DMA buffer stats)
# into structured JSON for the ISP Inspector dashboard.

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

ISP_FS=/proc/jz/isp/isp-fs
if [ ! -r "$ISP_FS" ]; then
	printf '{"error":"/proc/jz/isp/isp-fs not found"}\n'
	exit 0
fi

# Extract a value: grep for pattern, take first match, strip label
getval() {
	grep "$1" "$ISP_FS" 2>/dev/null | head -1 | sed "s/.*$1[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//"
}

# Read an ISP module parameter, trying each tx_isp_* module.
isp_param() {
	for f in /sys/module/tx_isp_*/parameters/"$1"; do
		if [ -r "$f" ]; then
			cat "$f" 2>/dev/null
			return
		fi
	done
}

queue_count=$(getval "queue count")
ch0_drop=$(getval "ch0_pre_dequeue_drop is")
ch0_intc=$(getval "ch0_pre_dequeue_intc_ahead_cnt is")
ch1_drop=$(getval "ch1_pre_dequeue_drop is")
ch1_intc=$(getval "ch1_pre_dequeue_intc_ahead_cnt is")

# Pre-dequeue forces a single-buffer schedule on the non-scaled channel, so
# the inspector needs to know it is on to not flag queue count 1 as starvation.
pd_time=$(isp_param isp_ch0_pre_dequeue_time)
pd_lines=$(isp_param isp_ch0_pre_dequeue_valid_lines)

# Per-buffer stats: look for entries like "ch0_buf_0" or "buf[0]"
buf_json="["
first=1
# Try numbered buffer pattern
for i in 0 1 2 3 4 5 6 7; do
	line=$(grep "ch0_buf_${i}" "$ISP_FS" 2>/dev/null | head -1)
	if [ -z "$line" ]; then
		# Try alternate format: "buf[0]"
		line=$(grep "buf\[${i}\]" "$ISP_FS" 2>/dev/null | head -1)
	fi
	if [ -n "$line" ]; then
		if [ "$first" -eq 0 ]; then
			buf_json="${buf_json},"
		fi
		first=0
		escaped=$(printf '%s' "$line" | sed 's/\\/\\\\/g; s/"/\\"/g')
		buf_json="${buf_json}\"${escaped}\""
	fi
done
buf_json="${buf_json}]"

printf '{'
printf '"timestamp":%d,' "$(date +%s)"
printf '"ch0":{"queue_count":"%s","drop":"%s","intc_ahead":"%s"},' \
	"$queue_count" "$ch0_drop" "$ch0_intc"
printf '"ch1":{"drop":"%s","intc_ahead":"%s"},' \
	"$ch1_drop" "$ch1_intc"
printf '"pre_dequeue":{"time":"%s","valid_lines":"%s"},' \
	"$pd_time" "$pd_lines"
printf '"buffers":%s' "$buf_json"
printf '}\n'
