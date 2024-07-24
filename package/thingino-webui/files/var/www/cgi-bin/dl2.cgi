#!/usr/bin/haserl
<%in p/common.cgi %>
<%
file=$(mktemp)
log="$GET_log"
case "$log" in
	dmesg)
		dmesg >$file
		;;
	logread)
		logread >$file
		;;
	netstat)
		netstat -a >$file
		;;
	weblog)
		cat /tmp/webui.log >$file
		;;
	*)
		echo "Unknown file."
		exit 1
		;;
esac
check_file_exist $file
echo "HTTP/1.0 200 OK
Date: $(time_http)
Server: $SERVER_SOFTWARE
Content-type: text/plain
Content-Disposition: attachment; filename=${log}-$(date +%s).txt
Content-Length: $(stat -c%s $file)
Cache-Control: no-store
Pragma: no-cache
"
cat $file
rm $file
%>
