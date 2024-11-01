#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Device status"
%>
<%in _header.cgi %>

<div class="row g-4 mb-4">
<div class="col">
<h3>System</h3>
<% ex "cat /etc/os-release" %>
</div>
</div>

<div class="row g-4 mb-4 ui-expert">
<div class="col">
<h3>Resources</h3>
<% ex "/usr/bin/uptime" %>
<% ex "df -T" %>
<% ex "cat /proc/meminfo | grep Mem" %>
</div>
</div>

<%in _footer.cgi %>
