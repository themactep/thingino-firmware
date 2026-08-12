#!/bin/sh
# shellcheck disable=SC1091
# Parse /proc/jz/isp/isp-m0 (T31+) or /proc/jz/isp/isp_info (T10/T20)
# into structured JSON for the ISP Inspector dashboard.
#
# Field reference: https://blog.thingino.com/reading-isp-m0

. /var/www/x/auth.sh
require_auth

printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-cache\r\n'
printf 'Connection: close\r\n'
printf '\r\n'

ISP_FILE=""
if [ -r /proc/jz/isp/isp-m0 ]; then
	ISP_FILE=/proc/jz/isp/isp-m0
elif [ -r /proc/jz/isp/isp_info ]; then
	ISP_FILE=/proc/jz/isp/isp_info
else
	printf '{"error":"No ISP proc file found (tried isp-m0 and isp_info)"}\n'
	exit 0
fi

# Escape a string value for JSON
json_str() {
	printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'
}

# Extract a value after a label.  Handles labels with trailing colon.
# Usage: getval "SENSOR NAME"  (returns rest of line after "SENSOR NAME :")
getval() {
	sed -n "s/^$1[[:space:]]*:[[:space:]]*//p" "$ISP_FILE" | head -1
}

sensor_name=$(getval "SENSOR NAME")
sensor_width=$(getval "SENSOR OUTPUT WIDTH")
sensor_height=$(getval "SENSOR OUTPUT HEIGHT")
fps_raw=$(getval "ISP OUTPUT FPS")
fps_num=""
fps_div=""
if [ -n "$fps_raw" ]; then
	fps_num=$(echo "$fps_raw" | awk -F'/' '{print $1}' | tr -d ' ')
	fps_div=$(echo "$fps_raw" | awk -F'/' '{print $2}' | tr -d ' ')
fi

run_mode=$(getval "ISP Runing Mode")
custom_mode=$(getval "ISP Custom Mode")
wdr_mode=$(getval "ISP WDR Mode")

int_time=$(getval "SENSOR Integration Time" | sed 's/ lines$//')
int_time_max=$(getval "SENSOR Max Integration Time" | sed 's/ lines$//')
# T10/T20: no max integration time field
: "${int_time_max:=}"
again=$(getval "SENSOR analog gain")
again_max=$(getval "MAX SENSOR analog gain")
dgain=$(getval "ISP digital gain")
dgain_max=$(getval "MAX ISP digital gain")
tgain=$(getval "ISP Tgain DB")

ev_val=$(getval "ISP EV value")
ev_log2=$(getval "ISP EV value log2")
ev_us=$(getval "ISP EV value us")
ev_min_int=$(getval "ISP EV min int")
ev_min_again=$(getval "ISP EV min again")
# T10/T20 fallbacks for EV fields
if [ -z "$ev_val" ]; then
	ev_val=$(getval "ISP total gain")
fi
if [ -z "$ev_log2" ]; then
	ev_log2=$(getval "ISP exposure log2 id")
fi

wb_rgain=$(getval "ISP WB weighted rgain")
wb_bgain=$(getval "ISP WB weighted bgain")
wb_ct=$(getval "ISP WB color temperature")
# T10/T20 fallbacks for WB fields
if [ -z "$wb_rgain" ]; then
	wb_rgain=$(getval "ISP WB rg")
fi
if [ -z "$wb_bgain" ]; then
	wb_bgain=$(getval "ISP WB bg")
fi
if [ -z "$wb_ct" ]; then
	wb_ct=$(getval "ISP WB Temperature")
fi
awb_start=$(getval "ISP AWB Start")

saturation=$(getval "Saturation")
sharpness=$(getval "Sharpness")
contrast=$(getval "Contrast")
brightness=$(getval "Brightness")

# Antiflicker: T31+ uses "Antiflicker", T10/T20 uses "ISP Antiflicker"
antiflicker=$(getval "Antiflicker")
if [ -z "$antiflicker" ]; then
	af_raw=$(getval "ISP Antiflicker")
	# T10/T20 format: "60[0 means disable]" — extract just the number
	af_num=$(echo "$af_raw" | sed 's/\[.*//')
	if [ "$af_num" = "0" ]; then
		af_num="0"
	fi
	antiflicker="$af_num"
fi

# Mirror/Flip: on T31+ both are on one line: "Mirror: Disable, Flip: Disable"
mirror_line=$(getval "Mirror")
if [ -n "$mirror_line" ]; then
	mirror=$(echo "$mirror_line" | sed 's/,.*//')
	flip=$(echo "$mirror_line" | sed 's/.*Flip: *//')
else
	mirror=""
	flip=""
fi

antiflicker_nodes=$(getval "Antiflicker nodes")

debug_line=$(getval "debug")
debug1_line=$(getval "debug1")

# T10/T20 extras from isp_info
sinter=$(getval "ISP Sinter")
temper=$(getval "ISP Temper")
iridix=$(getval "ISP Iridix")
lsc_mesh=$(getval "ISP LSC mesh")
black_level=$(getval "ISP Black level")
ccm=$(getval "ISP CCM")
defect_pixel=$(getval "ISP Defect pixel")
sharp_dir=$(getval "ISP sharpening directional")
sharp_undir=$(getval "ISP sharpening undirectional")

# Derive platform from soc command for accurate model
platform=$(soc -f 2>/dev/null || echo "unknown")
case "$ISP_FILE" in
	*isp-m0) : ;;   # T31+
	*isp_info) : ;; # T10/T20
esac

printf '{'
printf '"platform":"%s",' "$platform"
printf '"timestamp":%d,' "$(date +%s)"
printf '"sensor":{"name":"%s","width":"%s","height":"%s"},' \
	"$(json_str "$sensor_name")" "$sensor_width" "$sensor_height"
printf '"fps":{"raw":"%s","num":"%s","div":"%s"},' \
	"$(json_str "$fps_raw")" "$fps_num" "$fps_div"
printf '"mode":{"running":"%s","custom":"%s","wdr":"%s"},' \
	"$(json_str "$run_mode")" "$(json_str "$custom_mode")" "$(json_str "$wdr_mode")"
printf '"exposure":{"int_time":"%s","int_time_max":"%s","again":"%s","again_max":"%s","dgain":"%s","dgain_max":"%s","tgain_db":"%s"},' \
	"$int_time" "$int_time_max" "$again" "$again_max" "$dgain" "$dgain_max" "$tgain"
printf '"ev":{"value":"%s","log2":"%s","us":"%s","min_int":"%s","min_again":"%s"},' \
	"$ev_val" "$ev_log2" "$ev_us" "$ev_min_int" "$ev_min_again"
printf '"wb":{"rgain":"%s","bgain":"%s","color_temp":"%s","awb_start":"%s"},' \
	"$wb_rgain" "$wb_bgain" "$wb_ct" "$(json_str "$awb_start")"
printf '"image":{"saturation":"%s","sharpness":"%s","contrast":"%s","brightness":"%s"},' \
	"$saturation" "$sharpness" "$contrast" "$brightness"
printf '"antiflicker":{"mode":"%s","mirror":"%s","flip":"%s","nodes":"%s"},' \
	"$antiflicker" "$(json_str "$mirror")" "$(json_str "$flip")" "$(json_str "$antiflicker_nodes")"
printf '"debug":{"ch0":"%s","debug1":"%s"},' \
	"$(json_str "$debug_line")" "$(json_str "$debug1_line")"
# T10/T20 extras
if [ "$platform" = "t10" ]; then
	printf '"t10_extras":{"sinter":"%s","temper":"%s","iridix":"%s","lsc_mesh":"%s","black_level":"%s","ccm":"%s","defect_pixel":"%s","sharp_dir":"%s","sharp_undir":"%s"}' \
		"$(json_str "$sinter")" "$(json_str "$temper")" "$(json_str "$iridix")" \
		"$(json_str "$lsc_mesh")" "$(json_str "$black_level")" "$(json_str "$ccm")" \
		"$(json_str "$defect_pixel")" "$(json_str "$sharp_dir")" "$(json_str "$sharp_undir")"
else
	printf '"t10_extras":null'
fi
printf '}\n'
