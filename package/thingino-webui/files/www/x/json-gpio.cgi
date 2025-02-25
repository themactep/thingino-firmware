#!/bin/sh
. ./_json.sh

# @params: n - name, s -state
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$n" ] && json_error "Required parameter '$n' is not set"

eval pin=\$$n
[ -z "$pin" ] && json_error "GPIO is not found"

if [ "$s" -eq 0 ] || [ "$s" -eq 1 ]; then
	state=${s:-0}
else
	[ $(gpio read $pin) -eq 0 ] && state=1 || state=0
fi

# default to output high
[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"
case "${pin:0-1}" in
	o) pin_on=0; pin_off=1 ;;
	O) pin_on=1; pin_off=0 ;;
esac
pin=${pin:0:(-1)}

gpio set $pin $state

json_ok "{\"pin\":\"$pin\",\"status\":\"$(gpio read $pin)\"}"
