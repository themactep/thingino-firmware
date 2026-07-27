#!/bin/sh
. ./_json.sh

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$x" ] && x=0
[ -z "$y" ] && y=0
[ -z "$d" ] && d="g"

case "$d" in
g) motors -d g -x "$x" -y "$y" >/dev/null ;;
r) motors -r >/dev/null ;;
h) motors -d h -x "$x" -y "$y" >/dev/null ;;
esac

json_ok "$(motors -j)"
