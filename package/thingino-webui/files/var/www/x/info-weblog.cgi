#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Log read" %>
<%in p/header.cgi %>
<% ex "cat /tmp/webui.log" %>
<% button_refresh %>
<% button_download "weblog" %>
<%in p/footer.cgi %>
