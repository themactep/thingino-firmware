#!/bin/sh
# shellcheck disable=SC2039
. ./_json.sh

bad_request() {
  http_400
  echo
  echo "$1"
  exit 1
}

we_are_good() {
  echo "we are good"
}

unknown_command() {
  bad_request "unknown command"
}

unknown_value() {
  bad_request "unknown value"
}

# Read POST data
read -r POST_DATA

# Parse JSON (supports quoted or numeric val)
cmd=$(printf '%s' "$POST_DATA" | awk -F'"' '/"cmd"/{for(i=1;i<=NF;i++){if($i=="cmd"){print $(i+2); exit}}}')
val=$(printf '%s' "$POST_DATA" | sed -n 's/.*"val"[[:space:]]*:[[:space:]]*"\{0,1\}\([^",}]*\).*/\1/p')

[ -z "$cmd" ] && bad_request "missing required parameter cmd"
[ -z "$val" ] && bad_request "missing required parameter val"

case "$cmd" in
  color)
    command="color $val"
    ret=$(color $val >/dev/null)
    ;;
  daynight)
    command="daynight $val"
    echo "{\"daynight\":{\"force_mode\":\"$val\"}}" | prudyntctl json - >/dev/null 2>&1
    json_ok
    exit 0
    ;;
  ir850 | ir940 | white)
    command="light $cmd $val"
    ret=$(light $cmd $val)
    ;;
  ircut)
    command="ircut $val"
    ret=$(ircut $val >/dev/null)
    ;;
esac

payload="{\"time\":\"$(date +%s)\",\"command\":\"$command\",\"result\":\"$ret\""

daynight=$(awk 'NR==1 {print $1}' /run/prudynt/daynight_mode 2>/dev/null || echo "unknown")
[ -z "$daynight" ] || payload="$payload,\"daynight\":\"$daynight\""

color=$(color read)
[ -z "$color" ] || payload="$payload,\"color\":$color"

ircut=$(ircut read)
[ -z "$ircut" ] || payload="$payload,\"ircut\":$ircut"

ir850=$(light ir850 read)
[ -z "$ir850" ] || payload="$payload,\"ir850\":$ir850"

ir940=$(light ir940 read)
[ -z "$ir940" ] || payload="$payload,\"ir940\":$ir940"

white=$(light white read)
[ -z "$white" ] || payload="$payload,\"white\":$white"

payload="$payload}"

json_ok "$payload"
