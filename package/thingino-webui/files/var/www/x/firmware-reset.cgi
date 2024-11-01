#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Erase overlay"
%>
<%in _header.cgi %>
<pre id="output" data-cmd="<% echo $POST_cmd | base64 -d %>" data-reboot="true"></pre>
<a class="btn btn-primary" href="/">Go home</a>
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<%in _footer.cgi %>
