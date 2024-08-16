#!/usr/bin/haserl
<%in _common.cgi %>
<% page_title="HTTPd" %>
<%in _header.cgi %>
<% ex "cat /etc/httpd.conf" %>
<% button_restore_from_rom "/etc/httpd.conf" %>
<% ex "/bin/printenv" %>
<%in _footer.cgi %>
