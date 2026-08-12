#!/bin/sh
# shellcheck disable=SC1091
# SSE stream of ISP status: combines isp-m0 + isp-fs into unified events.
# Client connects once; server pushes updates at the requested interval.

. /var/www/x/auth.sh
require_auth

# Parse query string for interval (default 2s)
INTERVAL=2
if echo "$QUERY_STRING" | grep -q 'interval='; then
	iv=$(echo "$QUERY_STRING" | sed 's/.*interval=\([0-9]*\).*/\1/')
	if [ -n "$iv" ] && [ "$iv" -ge 1 ] 2>/dev/null; then
		INTERVAL="$iv"
	fi
fi

printf 'Content-Type: text/event-stream\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: keep-alive\r\n'
printf 'X-Accel-Buffering: no\r\n'
printf '\r\n'

# Determine ISP file
ISP_FILE=""
if [ -r /proc/jz/isp/isp-m0 ]; then
	ISP_FILE=/proc/jz/isp/isp-m0
elif [ -r /proc/jz/isp/isp_info ]; then
	ISP_FILE=/proc/jz/isp/isp_info
fi

ISP_FS=/proc/jz/isp/isp-fs

json_str() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

getval() {
	sed -n "s/^$1[[:space:]]*:[[:space:]]*//p" "$2" | head -1
}

# Determine platform from soc command for accurate model
platform=$(soc -f 2>/dev/null || echo "unknown")

# Main SSE loop
while true; do
	ts=$(date +%s)

	# ── Build isp-m0 JSON ──────────────────────────────────
	m0_json="null"
	if [ -n "$ISP_FILE" ]; then
		f="$ISP_FILE"

		s_name=$(getval "SENSOR NAME" "$f")
		s_width=$(getval "SENSOR OUTPUT WIDTH" "$f")
		s_height=$(getval "SENSOR OUTPUT HEIGHT" "$f")

		fps_raw=$(getval "ISP OUTPUT FPS" "$f")
		fps_num=""
		fps_div=""
		if [ -n "$fps_raw" ]; then
			fps_num=$(echo "$fps_raw" | awk -F'/' '{print $1}' | tr -d ' ')
			fps_div=$(echo "$fps_raw" | awk -F'/' '{print $2}' | tr -d ' ')
		fi

		run_mode=$(getval "ISP Runing Mode" "$f")
		custom_mode=$(getval "ISP Custom Mode" "$f")
		wdr_mode=$(getval "ISP WDR Mode" "$f")

		int_time=$(getval "SENSOR Integration Time" "$f" | sed 's/ lines$//')
		int_time_max=$(getval "SENSOR Max Integration Time" "$f" | sed 's/ lines$//')
		# T10/T20: no max integration time field
		: "${int_time_max:=}"
		again=$(getval "SENSOR analog gain" "$f")
		again_max=$(getval "MAX SENSOR analog gain" "$f")
		dgain=$(getval "ISP digital gain" "$f")
		dgain_max=$(getval "MAX ISP digital gain" "$f")
		tgain_db=$(getval "ISP Tgain DB" "$f")

		ev_val=$(getval "ISP EV value" "$f")
		ev_log2=$(getval "ISP EV value log2" "$f")
		ev_us=$(getval "ISP EV value us" "$f")
		ev_min_int=$(getval "ISP EV min int" "$f")
		ev_min_again=$(getval "ISP EV min again" "$f")
		# T10/T20 fallbacks for EV fields
		if [ -z "$ev_val" ]; then
			ev_val=$(getval "ISP total gain" "$f")
		fi
		if [ -z "$ev_log2" ]; then
			ev_log2=$(getval "ISP exposure log2 id" "$f")
		fi

		wb_rgain=$(getval "ISP WB weighted rgain" "$f")
		wb_bgain=$(getval "ISP WB weighted bgain" "$f")
		wb_ct=$(getval "ISP WB color temperature" "$f")
		# T10/T20 fallbacks for WB fields
		if [ -z "$wb_rgain" ]; then
			wb_rgain=$(getval "ISP WB rg" "$f")
		fi
		if [ -z "$wb_bgain" ]; then
			wb_bgain=$(getval "ISP WB bg" "$f")
		fi
		if [ -z "$wb_ct" ]; then
			wb_ct=$(getval "ISP WB Temperature" "$f")
		fi
		awb_start=$(getval "ISP AWB Start" "$f")

		sat=$(getval "Saturation" "$f")
		sharp=$(getval "Sharpness" "$f")
		contrast=$(getval "Contrast" "$f")
		bright=$(getval "Brightness" "$f")

		af_val=$(getval "Antiflicker" "$f")
		if [ -z "$af_val" ]; then
			af_raw=$(getval "ISP Antiflicker" "$f")
			af_val=$(echo "$af_raw" | sed 's/\[.*//')
		fi

		mirror=""
		flip=""
		mirror_line=$(getval "Mirror" "$f")
		if [ -n "$mirror_line" ]; then
			mirror=$(echo "$mirror_line" | sed 's/,.*//')
			flip=$(echo "$mirror_line" | sed 's/.*Flip: *//')
		fi
		af_nodes=$(getval "Antiflicker nodes" "$f")

		dbg_line=$(getval "debug" "$f")
		dbg1_line=$(getval "debug1" "$f")

		m0_json=$(
			printf '{'
			printf '"sensor":{"name":"%s","width":"%s","height":"%s"},' \
				"$(json_str "$s_name")" "$s_width" "$s_height"
			printf '"fps":{"raw":"%s","num":"%s","div":"%s"},' \
				"$(json_str "$fps_raw")" "$fps_num" "$fps_div"
			printf '"mode":{"running":"%s","custom":"%s","wdr":"%s"},' \
				"$(json_str "$run_mode")" "$(json_str "$custom_mode")" "$(json_str "$wdr_mode")"
			printf '"exposure":{"int_time":"%s","int_time_max":"%s","again":"%s","again_max":"%s","dgain":"%s","dgain_max":"%s","tgain_db":"%s"},' \
				"$int_time" "$int_time_max" "$again" "$again_max" "$dgain" "$dgain_max" "$tgain_db"
			printf '"ev":{"value":"%s","log2":"%s","us":"%s","min_int":"%s","min_again":"%s"},' \
				"$ev_val" "$ev_log2" "$ev_us" "$ev_min_int" "$ev_min_again"
			printf '"wb":{"rgain":"%s","bgain":"%s","color_temp":"%s","awb_start":"%s"},' \
				"$wb_rgain" "$wb_bgain" "$wb_ct" "$(json_str "$awb_start")"
			printf '"image":{"saturation":"%s","sharpness":"%s","contrast":"%s","brightness":"%s"},' \
				"$sat" "$sharp" "$contrast" "$bright"
			printf '"antiflicker":{"mode":"%s","mirror":"%s","flip":"%s","nodes":"%s"},' \
				"$af_val" "$(json_str "$mirror")" "$(json_str "$flip")" "$(json_str "$af_nodes")"
			printf '"debug":{"ch0":"%s","debug1":"%s"}' \
				"$(json_str "$dbg_line")" "$(json_str "$dbg1_line")"
			printf '}'
		)
	fi

	# ── Build isp-fs JSON ──────────────────────────────────
	fs_json="null"
	if [ -r "$ISP_FS" ]; then
		qc=$(grep "queue count" "$ISP_FS" 2>/dev/null | head -1 | sed 's/.*queue count[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//')
		ch0_drop=$(grep "ch0_pre_dequeue_drop is" "$ISP_FS" 2>/dev/null | head -1 | sed 's/.*ch0_pre_dequeue_drop is[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//')
		ch0_intc=$(grep "ch0_pre_dequeue_intc_ahead_cnt is" "$ISP_FS" 2>/dev/null | head -1 | sed 's/.*ch0_pre_dequeue_intc_ahead_cnt is[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//')
		ch1_drop=$(grep "ch1_pre_dequeue_drop is" "$ISP_FS" 2>/dev/null | head -1 | sed 's/.*ch1_pre_dequeue_drop is[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//')
		ch1_intc=$(grep "ch1_pre_dequeue_intc_ahead_cnt is" "$ISP_FS" 2>/dev/null | head -1 | sed 's/.*ch1_pre_dequeue_intc_ahead_cnt is[[:space:]]*[:=]*[[:space:]]*//; s/[[:space:]]*$//')

		fs_json=$(printf '{"ch0":{"queue_count":"%s","drop":"%s","intc_ahead":"%s"},"ch1":{"drop":"%s","intc_ahead":"%s"}}' \
			"$qc" "$ch0_drop" "$ch0_intc" "$ch1_drop" "$ch1_intc")
	fi

	printf 'event: isp\ndata: {"platform":"%s","timestamp":%s,"m0":%s,"fs":%s}\n\n' \
		"$platform" "$ts" "$m0_json" "$fs_json"

	sleep "$INTERVAL"
done
