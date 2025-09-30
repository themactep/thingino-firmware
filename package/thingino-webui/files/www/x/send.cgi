#!/bin/haserl
<%in _common.cgi %>
<%
. ./_json.sh

target=$GET_to
case "$target" in
	telegram)
		send2telegram snap >/dev/null &
		json_ok "Sent to $target"
		;;
	email | ftp | mount | mqtt | ntfy | webhook | yadisk)
		send2$target $opts >/dev/null &
		json_ok "Sent to $target"
		;;
	termbin)
		case $GET_file in
			weblog)
				url=$(cat /tmp/webui.log | send2termbin)
				;;
			*)
				cmd=$(echo "$GET_payload" | base64 -d) || cmd="$GET_payload"
				url=$($cmd | send2termbin)
				;;
		esac
		redirect_to $url
		;;
	*)
		redirect_back "danger" "Unknown target $target"
esac
%>
