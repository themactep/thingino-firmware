#!/bin/sh
# Optimized heartbeat using cached data

# Check authentication
. /var/www/x/auth.sh
require_auth

CACHE_FILE="/tmp/heartbeat_cache.json"
CACHE_MAX_AGE=1

http_200() {
  printf 'Status: 200 OK\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Cache-Control: no-cache\r\n'
  printf '\r\n'
}

# Check if cache is fresh (< CACHE_MAX_AGE seconds old)
is_cache_fresh() {
  [ -f "$CACHE_FILE" ] || return 1
  local cache_age=$(($(date +%s) - $(stat -c %Y "$CACHE_FILE" 2>/dev/null || echo 0)))
  [ "$cache_age" -lt "$CACHE_MAX_AGE" ]
}

# Generate heartbeat data (expensive operations)
generate_heartbeat() {
  ch0_rec="false"; [ -f "/run/prudynt/mp4ctl-ch0.active" ] && ch0_rec="true"
  ch1_rec="false"; [ -f "/run/prudynt/mp4ctl-ch1.active" ] && ch1_rec="true"
  motion_enabled="false"; [ -f "/run/prudynt/motion.active" ] && motion_enabled="true"
  privacy_enabled="false"; [ -f "/run/prudynt/privacy.active" ] && privacy_enabled="true"

  # Single prudyntctl call to get all data at once
  local prudynt_data=$(prudyntctl json - 2>/dev/null <<'PRUDYNT_EOF'
{
  "image": {"running_mode": null},
  "audio": {"mic_enabled": null, "spk_enabled": null},
  "daynight": {"status": null, "enabled": null}
}
PRUDYNT_EOF
)

  # Parse prudyntctl response
  color_mode=$(echo "$prudynt_data" | grep -o '"running_mode":[^,}]*' | cut -d: -f2)
  mic_enabled=$(echo "$prudynt_data" | grep -o '"mic_enabled":[^,}]*' | cut -d: -f2)
  spk_enabled=$(echo "$prudynt_data" | grep -o '"spk_enabled":[^,}]*' | cut -d: -f2)
  total_gain=$(echo "$prudynt_data" | grep -o '"total_gain":[0-9-]*' | cut -d: -f2)
  total_gain="${total_gain:-0}"
  daynight_enabled=$(echo "$prudynt_data" | grep -o '"enabled":[^,}]*' | cut -d: -f2)

  # Read hardware states (lighter operations)
  ircut_state=$(ircut read 2>/dev/null || echo "null")
  ir850_state=$(light ir850 read 2>/dev/null || echo "null")
  ir940_state=$(light ir940 read 2>/dev/null || echo "null")
  white_state=$(light white read 2>/dev/null || echo "null")

  # WireGuard status
  wg_status=0
  if command -v wg >/dev/null 2>&1; then
    wg show wg0 2>/dev/null | grep -q "latest handshake" && wg_status=1
  fi

  printf '{"time_now":%s,"daynight_brightness":"%s","total_gain":%s,"daynight_mode":"%s","rec_ch0":%s,"rec_ch1":%s,"motion_enabled":%s,"privacy_enabled":%s,"color_mode":%s,"ircut_state":%s,"ir850_state":%s,"ir940_state":%s,"white_state":%s,"mic_enabled":%s,"spk_enabled":%s,"daynight_enabled":%s,"wg_status":%s}' \
    "$(date +%s)" \
    "$(awk '{print $1}' /run/prudynt/daynight_brightness 2>/dev/null || echo "unknown")" \
    "$total_gain" \
    "$(awk 'NR==1 {print $1}' /run/prudynt/daynight_mode 2>/dev/null || echo "unknown")" \
    "$ch0_rec" \
    "$ch1_rec" \
    "$motion_enabled" \
    "$privacy_enabled" \
    "${color_mode:-null}" \
    "${ircut_state}" \
    "${ir850_state}" \
    "${ir940_state}" \
    "${white_state}" \
    "${mic_enabled:-false}" \
    "${spk_enabled:-false}" \
    "${daynight_enabled:-false}" \
    "$wg_status"
}

# Get heartbeat data (from cache if fresh, otherwise regenerate)
get_heartbeat() {
  if is_cache_fresh; then
    cat "$CACHE_FILE"
  else
    # Use flock to prevent multiple simultaneous cache updates
    (
      flock -n 200 || { cat "$CACHE_FILE" 2>/dev/null && exit 0; }
      generate_heartbeat > "$CACHE_FILE.tmp"
      mv "$CACHE_FILE.tmp" "$CACHE_FILE"
      cat "$CACHE_FILE"
    ) 200>/tmp/heartbeat_cache.lock
  fi
}

# Send response
http_200
json_header
get_heartbeat
