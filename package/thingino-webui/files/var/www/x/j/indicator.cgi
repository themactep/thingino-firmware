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

state=$s
[ -z "$state" ] && state=0

color=$c
[ -z "$color" ] && error "Missing mandatory parameter 'c' for color"

pin=$(fw_printenv -n gpio_led_$color)
[ -z "$pin" ] && error "GPIO is not set for $c LED"

gpio set "$pin" "$state"
pin_status=$(cat /sys/class/gpio/gpio${pin}/value)

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

{\"code\":200,\"message\":{\"pin\":\"$pin\",\"status\":\"$pin_status\"}}
"
