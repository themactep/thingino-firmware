#!/bin/sh
. ./_json.sh

[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

case "$target" in
	enabled)
		case "$state" in
			true | false)
				jct /etc/prudynt.json set "motion.$target" $state
				json_ok "{\"target\":\"$target\",\"status\":$state}"
				;;
			*)
				json_error "state missing"
				;;
		esac
		;;
	send2email | send2ftp | send2mqtt | send2ntfy | send2telegram | send2webhook)
		case "$state" in
			true | false)
				jct /etc/motion.json set "motion.$target" $state
				json_ok "{\"target\":\"$target\",\"status\":$state}"
				;;
			*)
				json_error "state missing"
				;;
		esac
		;;
	sensitivity | cooldown_time)
			jct /etc/motion.json set "motion.$target" $state
			json_ok "{\"target\":\"$target\",\"state\":$state}"
		;;
	*)
		json_error "target missing"
		;;
esac
