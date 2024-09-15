#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Overlay partition"
s=$(df | awk '/\/overlay/{print $5}')
%>
<%in _header.cgi %>
<div class="alert alert-primary">
<h5>Overlay partition is <%= $s %> full.</h5>
<% progressbar "${s/%/}" %>
</div>
<% ex "ls -Rl /overlay/" %>
<%in _reset-firmware.cgi %>
<%in _footer.cgi %>
