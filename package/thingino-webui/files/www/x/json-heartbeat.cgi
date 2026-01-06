#!/bin/sh
. ./_json.sh

HEARTBEAT_INTERVAL="${HEARTBEAT_INTERVAL:-5}"
HEARTBEAT_RETRY_MS=$((HEARTBEAT_INTERVAL * 1000))

heartbeat_payload() {
  ch0_rec="false"; [ -f "/run/prudynt/mp4ctl-ch0.active" ] && ch0_rec="true"
  ch1_rec="false"; [ -f "/run/prudynt/mp4ctl-ch1.active" ] && ch1_rec="true"
  motion_enabled="false"; [ -f "/run/prudynt/motion.active" ] && motion_enabled="true"
  privacy_enabled="false"; [ -f "/run/prudynt/privacy.active" ] && privacy_enabled="true"

  # Read hardware states
  color_mode=$(color read 2>/dev/null || echo "")
  ircut_state=$(ircut read 2>/dev/null || echo "")
  ir850_state=$(light ir850 read 2>/dev/null || echo "")
  ir940_state=$(light ir940 read 2>/dev/null || echo "")
  white_state=$(light white read 2>/dev/null || echo "")

  # Read audio states
  audio_states=$(echo '{"audio":{"mic_enabled":null,"spk_enabled":null}}' | prudyntctl json - 2>/dev/null)
  mic_enabled=$(echo "$audio_states" | grep -o '"mic_enabled":[^,}]*' | cut -d: -f2)
  spk_enabled=$(echo "$audio_states" | grep -o '"spk_enabled":[^,}]*' | cut -d: -f2)

  printf '{"time_now":"%s","timezone":"%s","mem_total":"%d","mem_active":"%d","mem_buffers":"%d","mem_cached":"%d","mem_free":"%d","overlay_total":"%d","overlay_used":"%d","overlay_free":"%d","uptime":"%s","daynight_brightness":"%s","daynight_mode":"%s","extras_total":"%d","extras_used":"%d","extras_free":"%d","rec_ch0":%s,"rec_ch1":%s,"motion_enabled":%s,"privacy_enabled":%s,"color_mode":%s,"ircut_state":%s,"ir850_state":%s,"ir940_state":%s,"white_state":%s,"mic_enabled":%s,"spk_enabled":%s}' \
    "$(date +%s)" \
    "$(cat /etc/timezone)" \
    "$(awk '/^MemTotal:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Active:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Buffers:/{print $2}' /proc/meminfo)" \
    "$(awk '/^Cached:/{print $2}' /proc/meminfo)" \
    "$(awk '/^MemFree:/{print $2}' /proc/meminfo)" \
    $(df | awk '/\/overlay$/{print $2,$3,$4}') \
    "$(awk '{m=$1/60;h=m/60;printf "%sd %sh %sm %ss\n",int(h/24),int(h%24),int(m%60),int($1%60)}' /proc/uptime)" \
    "$(awk '{print $1}' /run/prudynt/daynight_brightness 2>/dev/null || echo "unknown")" \
    "$(awk 'NR==1 {print $1}' /run/prudynt/daynight_mode 2>/dev/null || echo "unknown")" \
    $(df | awk '/\/opt$/{print $2,$3,$4}') \
    "$ch0_rec" \
    "$ch1_rec" \
    "$motion_enabled" \
    "$privacy_enabled" \
    "${color_mode:-null}" \
    "${ircut_state:-null}" \
    "${ir850_state:-null}" \
    "${ir940_state:-null}" \
    "${white_state:-null}" \
    "${mic_enabled:-false}" \
    "${spk_enabled:-false}"
}

send_headers() {
  http_200
  cat <<EOF
Content-Type: text/event-stream
Cache-Control: no-cache
Connection: keep-alive

EOF
}

stream_heartbeat() {
  while true; do
    printf 'retry: %d\n' "$HEARTBEAT_RETRY_MS" || exit 0
    printf 'data: %s\n\n' "$(heartbeat_payload)" || exit 0
    sleep "$HEARTBEAT_INTERVAL" || exit 0
  done
}

trap 'exit 0' INT TERM PIPE HUP
send_headers
stream_heartbeat
