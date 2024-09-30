#!/bin/haserl
<%in _common.cgi %>
<%
target=$GET_to
case "$target" in
	email | ftp | mqtt | telegram | webhook | yadisk)
		send2$target $opts >/dev/null
		redirect_back "success" "Sent to $target"
		;;
	termbin)
		case $GET_file in
			weblog) url=$(cat /tmp/webui.log | send2termbin) ;;
			*) url=$($GET_file | send2termbin) ;;
		esac
		redirect_to $url
		;;
	*)
		redirect_back "danger" "Unknown target $target"
esac
%>
