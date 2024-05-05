#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="HTTPd" %>
<%in p/header.cgi %>
<% ex "cat /etc/httpd.conf" %>
<% button_restore_from_rom "/etc/httpd.conf" %>
<% ex "/bin/printenv" %>
<%in p/footer.cgi %>
