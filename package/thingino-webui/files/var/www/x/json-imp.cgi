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

urldecode() {
	local i="${*//+/ }"
	echo -e "${i//%/\\x}"
}

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$cmd" ] && bad_request "missing required parameter cmd"

val="$(urldecode "$val")"

case "$cmd" in
	color)
		command="color $val"
		color $val
		;;
	daynight)
		command="daynight $val"
		daynight $val
		;;
	ir850 | ir940 | white)
		command="irled ${val:-read} $cmd"
		irled ${val:-read} $cmd
		;;
	ircut)
		command="ircut $val"
		ircut $val
		;;
esac

payload="{\"time\":\"$(date +%s)\",\"command\":\"$command\""

daynight=$(daynight read)
[ -z "$daynight" ] || payload="$payload,\"daynight\":\"$daynight\""

color=$(color read)
[ -z "$color" ] || payload="$payload,\"color\":$color"

ircut=$(ircut read)
[ -z "$ircut" ] || payload="$payload,\"ircut\":$ircut"

ir850=$(irled read ir850)
[ -z "$ir850" ] || payload="$payload,\"ir850\":$ir850"

ir940=$(irled read ir940)
[ -z "$ir940" ] || payload="$payload,\"ir940\":$ir940"

white=$(irled read white)
[ -z "$white" ] || payload="$payload,\"white\":$white"

payload="$payload}"

json_ok "$payload"
