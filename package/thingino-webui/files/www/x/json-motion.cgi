#!/bin/sh
. ./_json.sh

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

case "$target" in
	email | ftp | mqtt | telegram | webhook | ntfy | yadisk | local)
		case "$state" in
			true | false)
				sed -i "/^motion_send2$target/d" $CONFIG_FILE
				echo "motion_send2$target=\"$state\"" >> $CONFIG_FILE

				json_ok "{\"target\":\"$target\",\"status\":$state}"
				;;
			*)
				json_error "state missing"
				;;
		esac
		;;
	*)
		json_error "target missing"
		;;
esac

service restart prudynt >/dev/null
service restart vbuffer >/dev/null
