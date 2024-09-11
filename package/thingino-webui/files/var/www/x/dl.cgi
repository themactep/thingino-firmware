#!/bin/haserl
<%in _common.cgi %>
<%
file=$GET_file
if [ "/tmp/webui.log" = "$file" ]; then
	fname="webui-$(date +%s).log"
	mime="text/plain"
else
	fname=$(basename $file)
	mime="application/octet-stream"
fi
check_file_exist $file
echo -en "HTTP/1.0 200 OK\r\n
Date: $(time_http)\r\n
Server: $SERVER_SOFTWARE\r\n
Content-type: ${mime}\r\n
Content-Disposition: attachment; filename=${fname}\r\n
Content-Length: $(stat -c%s $file)\r\n
Cache-Control: no-store\r\n
Pragma: no-cache\r\n
\r\n"
cat $file
%>
