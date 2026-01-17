#!/bin/sh
. ./_json.sh

# Detect platform and set EV limits accordingly
detect_platform_ev_limits() {
  local platform="generic"
  local ev_min="40000"
  local ev_max="2400000"

  # Use soc -f to get platform family (most reliable method)
  if command -v soc >/dev/null 2>&1; then
    platform=$(soc -f 2>/dev/null)
  fi

  # Set EV limits based on platform family
  case "$platform" in
    t23)
      ev_min="42857"
      ev_max="2227731"
      ;;
    t31)
      ev_min="0"
      ev_max="60000"
      ;;
    t20|t21|t30)
      ev_min="0"
      ev_max="50000"
      ;;
    *)
      # Conservative fallback for unknown platforms
      ev_min="40000"
      ev_max="2400000"
      ;;
  esac

  echo "$ev_min"
  echo "$ev_max"
}

# Get EV limits
ev_limits=$(detect_platform_ev_limits)
ev_min=$(echo "$ev_limits" | head -1)
ev_max=$(echo "$ev_limits" | tail -1)

# Fetch current threshold config from prudynt
ev_night_high=$(prudyntctl get daynight.ev_night_high 2>/dev/null || echo "1900000")
ev_day_low_primary=$(prudyntctl get daynight.ev_day_low_primary 2>/dev/null || echo "479832")
ev_day_low_secondary=$(prudyntctl get daynight.ev_day_low_secondary 2>/dev/null || echo "361880")

# Convert EV thresholds to percentages for display
# Note: EV is INVERTED - higher EV = darker scene
# percentage = ((ev - EVmin) * 100) / (EVmax - EVmin)
convert_ev_to_percent() {
  local ev=$1
  local ev_min=$2
  local ev_max=$3

  if [ "$ev_max" -le "$ev_min" ]; then
    echo "0"
    return
  fi

  local range=$((ev_max - ev_min))
  local num=$(( (ev - ev_min) * 100 ))
  local pct=$((num / range))

  # Clamp to 0-100
  if [ "$pct" -lt 0 ]; then pct=0; fi
  if [ "$pct" -gt 100 ]; then pct=100; fi

  echo "$pct"
}

night_percent=$(convert_ev_to_percent "$ev_night_high" "$ev_min" "$ev_max")
day_percent=$(convert_ev_to_percent "$ev_day_low_primary" "$ev_min" "$ev_max")

send_headers() {
  http_200
  cat <<EOF
Content-Type: application/json
Cache-Control: no-cache

EOF
}

send_headers

printf '{"platform":{"ev_min":%d,"ev_max":%d},"daynight":{"ev_night_high":%d,"ev_day_low_primary":%d,"ev_day_low_secondary":%d,"night_percent":%d,"day_percent":%d}}' \
  "$ev_min" \
  "$ev_max" \
  "$ev_night_high" \
  "$ev_day_low_primary" \
  "$ev_day_low_secondary" \
  "$night_percent" \
  "$day_percent"
