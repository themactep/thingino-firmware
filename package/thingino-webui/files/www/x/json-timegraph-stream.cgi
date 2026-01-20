#!/bin/sh
http_200() {
  printf 'Status: 200 OK\r\n'
}

http_400() {
  printf 'Status: 400 Bad Request\r\n'
}

http_412() {
  printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_412
  json_header
  printf '{"error":{"code":412,"message":"%s"}}
' "$1"
  exit 0
}

json_ok() {
  http_200
  json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}
' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}
' "$1"
  fi
  exit 0
}


STREAM_INTERVAL="${STREAM_INTERVAL:-2}"
STREAM_RETRY_MS=$((STREAM_INTERVAL * 1000))

stream_payload() {
  # Try to read sensor/daynight metrics from prudyntctl (preferred method)
  daynight_json=""
  ev="0"
  gb_gain="0"
  gr_gain="0"
  brightness_pct="0"
  total_gain="0"
  ae_luma="0"
  awb_ct="0"
  night_threshold="0"
  day_threshold="0"

  if command -v prudyntctl >/dev/null 2>&1; then
    daynight_json=$(echo '{"daynight":{"status":null}}' | prudyntctl json - 2>/dev/null)
  fi

  # Parse from JSON if available
  if [ -n "$daynight_json" ]; then
    # Extract numeric values more precisely
    ev=$(echo "$daynight_json" | grep -o '"ev":[0-9-]*' | cut -d: -f2)
    gb_gain=$(echo "$daynight_json" | grep -o '"gb":[0-9-]*' | cut -d: -f2)
    gr_gain=$(echo "$daynight_json" | grep -o '"gr":[0-9-]*' | cut -d: -f2)
    brightness_pct=$(echo "$daynight_json" | grep -o '"brightness_percent":[0-9-]*' | cut -d: -f2)
    total_gain=$(echo "$daynight_json" | grep -o '"total_gain":[0-9-]*' | cut -d: -f2)
    ae_luma=$(echo "$daynight_json" | grep -o '"ae_luma":[0-9-]*' | cut -d: -f2)
    awb_ct=$(echo "$daynight_json" | grep -o '"awb_color_temp":[0-9-]*' | cut -d: -f2)
    night_threshold=$(echo "$daynight_json" | grep -o '"total_gain_night_threshold":[0-9-]*' | cut -d: -f2)
    day_threshold=$(echo "$daynight_json" | grep -o '"total_gain_day_threshold":[0-9-]*' | cut -d: -f2)
  fi

  # Ensure all values have defaults if still empty
  ev="${ev:-0}"
  gb_gain="${gb_gain:-0}"
  gr_gain="${gr_gain:-0}"
  brightness_pct="${brightness_pct:-0}"
  total_gain="${total_gain:-0}"
  ae_luma="${ae_luma:-0}"
  awb_ct="${awb_ct:-0}"
  night_threshold="${night_threshold:-0}"
  day_threshold="${day_threshold:-0}"
  daynight_mode=$(awk 'NR==1 {print $1}' /run/prudynt/daynight_mode 2>/dev/null || echo "unknown")

  printf '{"time_now":"%s","mem_total":"%d","mem_active":"%d","mem_buffers":"%d","mem_cached":"%d","mem_free":"%d","overlay_total":"%d","overlay_used":"%d","overlay_free":"%d","extras_total":"%d","extras_used":"%d","extras_free":"%d","uptime":"%s","ev":"%s","gb_gain":"%s","gr_gain":"%s","daynight_brightness":"%s","total_gain":"%s","ae_luma":"%s","awb_color_temp":"%s","total_gain_night_threshold":"%s","total_gain_day_threshold":"%s","daynight_mode":"%s","opt_total":"%d","opt_used":"%d","opt_free":"%d"}' \
    "$(date +%s)" \
    "$(awk '/^MemTotal:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Active:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Buffers:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Cached:/{print $2}' /proc/meminfo)" \
    "$(awk '/^MemFree:/{print $2}' /proc/meminfo)" \
    "$(df | awk '/\/overlay$/{print $2}' | head -1)" \
    "$(df | awk '/\/overlay$/{print $3}' | head -1)" \
    "$(df | awk '/\/overlay$/{print $4}' | head -1)" \
    "$(df | awk '/\/opt$/{print $2}' | head -1)" \
    "$(df | awk '/\/opt$/{print $3}' | head -1)" \
    "$(df | awk '/\/opt$/{print $4}' | head -1)" \
    "$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss\n",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)" \
    "$ev" \
    "$gb_gain" \
    "$gr_gain" \
    "$brightness_pct" \
    "$total_gain" \
    "$ae_luma" \
    "$awb_ct" \
    "$night_threshold" \
    "$day_threshold" \
    "$daynight_mode"
}

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

EOF
}

stream_data() {
  while true; do
    printf 'retry: %d\n' "$STREAM_RETRY_MS" || exit 0
    printf 'data: %s\n\n' "$(stream_payload)" || exit 0
    sleep "$STREAM_INTERVAL" || exit 0
  done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_data
