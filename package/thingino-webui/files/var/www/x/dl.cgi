#!/usr/bin/haserl
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
echo "HTTP/1.0 200 OK
Date: $(time_http)
Server: $SERVER_SOFTWARE
Content-type: ${mime}
Content-Disposition: attachment; filename=${fname}
Content-Length: $(stat -c%s $file)
Cache-Control: no-store
Pragma: no-cache
"
cat $file
%>
