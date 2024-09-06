#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Web UI Log"
%>
<%in _header.cgi %>
<%
ex "cat /tmp/webui.log"
button_refresh
button_download "weblog"
button_send2tb "weblog"
%>
<%in _footer.cgi %>
