#!/bin/sh
# shellcheck disable=SC2039
. ./_json.sh

bad_request() {
  http_400
  echo
  echo "$1"
  exit 1
}

# Read POST data
read -r POST_DATA

# Parse JSON (supports quoted or numeric val)
cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
  auto)
    echo '{"daynight":{"enabled":true}}' | prudyntctl json - >/dev/null 2>&1
    ;;
  color)
    echo "{\"daynight\":{\"enabled\":false},\"image\":{\"running_mode\": $val}}" | prudyntctl json - >/dev/null 2>&1
    ;;
  daynight)
    echo "{\"daynight\":{\"enabled\":false,\"force_mode\":\"$val\"}}" | prudyntctl json - >/dev/null 2>&1
    ;;
  ir850 | ir940 | white)
    echo '{"daynight":{"enabled":false}}' | prudyntctl json - >/dev/null 2>&1
    light $cmd $val
    ;;
  ircut)
    echo '{"daynight":{"enabled":false}}' | prudyntctl json - >/dev/null 2>&1
    ircut $val >/dev/null
    ;;
esac

# All state data is provided by heartbeat, no need to build payload here
json_ok
