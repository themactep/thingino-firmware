#!/bin/sh
. ./_json.sh

CONF_FILE="/etc/webui/motion.conf"

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

case "$target" in
	email | ftp | mqtt | telegram | webhook | yadisk)
		case "$state" in
			true | false)
				sed -i "/^motion_send2$target/d" $CONF_FILE
				echo "motion_send2$target=\"$state\"" >> $CONF_FILE
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
/etc/init.d/S95prudynt restart >/dev/null
