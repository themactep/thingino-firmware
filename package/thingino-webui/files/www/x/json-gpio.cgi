#!/bin/sh
. ./_json.sh

# @params: n - name, s - state
if [ "$REQUEST_METHOD" = "POST" ]; then
  eval $(echo "$CONTENT" | sed "s/&/;/g")
else
  eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

[ -z "$n" ] && json_error "Required parameter '$n' is not set"

eval pin=\$$n
[ -z "$pin" ] && json_error "GPIO is not found"

case "$s" in
  0 | 1) state=${s:-0} ;;
  *) [ $(gpio read $pin) -eq 0 ] && state=1 || state=0 ;;
esac

# default to output high
[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"
case "${pin:0-1}" in
  o) pin_on=0; pin_off=1 ;;
  O) pin_on=1; pin_off=0 ;;
esac
pin=${pin:0:(-1)}

gpio set "$pin" "$state"

json_ok "{\"pin\":\"$pin\",\"status\":\"$(gpio read $pin)\"}"
