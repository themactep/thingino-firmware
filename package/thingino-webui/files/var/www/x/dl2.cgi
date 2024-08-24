#!/bin/haserl
<%in _common.cgi %>
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
	snmp)
		cat /proc/net/snmp >$file
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
echo -en "HTTP/1.0 200 OK\r\n
Date: $(time_http)\r\n
Server: $SERVER_SOFTWARE\r\n
Content-type: text/plain\r\n
Content-Disposition: attachment; filename=${log}-$(date +%s).txt\r\n
Content-Length: $(stat -c%s $file)\r\n
Cache-Control: no-store\r\n
Pragma: no-cache\r\n
\r\n"
cat $file
rm $file
%>
