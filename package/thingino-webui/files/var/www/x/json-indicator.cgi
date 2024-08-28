#!/bin/sh

error() {
	echo "HTTP/1.1 412 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

{\"error\":{\"code\":412,\"message\":\"$1\"}}
"
	exit
}

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

state=${s:-0}

color=$c
[ -z "$color" ] && error "Missing mandatory parameter 'c' for color"

pin=$(fw_printenv -n gpio_led_$color)
[ -z "$pin" ] && error "GPIO is not set for $c LED"

# default to output high
[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"
case "${pin:0-1}" in
	o) pin_on=0; pin_off=1 ;;
	O) pin_on=1; pin_off=0 ;;
esac
pin=${pin:0:(-1)}

gpio set "$pin" "$state"
pin_status=$(cat /sys/class/gpio/gpio$pin/value)

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

{\"code\":200,\"message\":{\"pin\":\"$pin\",\"status\":\"$pin_status\"}}
"
