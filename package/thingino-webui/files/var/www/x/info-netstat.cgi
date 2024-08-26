#!/bin/haserl
<%in _common.cgi %>
<% page_title="Networking statistics" %>
<%in _header.cgi %>
<% ex "netstat -a" %>
<% button_refresh %>
<% button_download "netstat" %>
<%in _footer.cgi %>
