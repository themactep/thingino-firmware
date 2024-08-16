#!/usr/bin/haserl
<%in _common.cgi %>
<% page_title="Log read" %>
<%in _header.cgi %>
<% ex "cat /tmp/webui.log" %>
<% button_refresh %>
<% button_download "weblog" %>
<%in _footer.cgi %>
