#!/usr/bin/haserl
<%in p/common.cgi %>
<%
target=$GET_to
case "$target" in
	email | ftp | mqtt | telegram | webhook | yadisk)
		/usr/sbin/send2${target} $opts >/dev/null
		redirect_back "success" "Sent to $target"
		;;
	pastebin)
		t=$(mktemp)
		$GET_file >$t
		url=$(/usr/sbin/send2${target} $t)
		rm $t
		redirect_to $url
		;;
	*)
		redirect_back "danger" "Unknown target $target"
esac
%>
