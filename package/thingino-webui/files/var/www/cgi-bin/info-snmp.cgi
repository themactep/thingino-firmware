#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="SNMP statistics" %>
<%in p/header.cgi %>
<% ex "cat /proc/net/snmp" %>
<% button_refresh %>
<% button_download "snmp" %>
<%in p/footer.cgi %>
