#!/bin/sh
. ./_json.sh

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"
[ -z "$i" ] && i="b"

case "$d" in
	g)
		motors -d g -x $x -y $y >/dev/null
		;;
	r)
		motors -r >/dev/null
		;;
	h)
		motors -d h -x $x -y $y >/dev/null
		;;
	i)
		motors -I $i >/dev/null
		;;
esac

json_ok "$(motors -j)"
