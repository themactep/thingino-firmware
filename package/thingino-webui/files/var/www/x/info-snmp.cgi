#!/bin/haserl
<%in _common.cgi %>
<% page_title="SNMP statistics" %>
<%in _header.cgi %>
<% ex "cat /proc/net/snmp" %>
<% button_refresh %>
<% button_download "snmp" %>
<%in _footer.cgi %>
