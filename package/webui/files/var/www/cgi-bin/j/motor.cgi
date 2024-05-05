#!/bin/sh

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"

case "$d" in
	g)
		motors -d g -x $x -y $y >/dev/null
		;;
	r)
		motors -r >/dev/null
		;;
	x)
		motors -d x -x $x -y $y >/dev/null
		;;
esac

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

$(motors -j)
"
