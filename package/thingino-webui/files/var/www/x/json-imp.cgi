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
	daynight)
		daynight $val
		;;
	ir850 | ir940 | white)
		irled ${val:-read} $cmd
		;;
	ircut)
		ircut $val
		;;
esac

json_ok "{\"daynight\":\"$(daynight read)\",\"ir850\":$(irled read ir850),\"ir940\":$(irled read ir940),\"ircut\":$(ircut read),\"color\":$(color read)}"
