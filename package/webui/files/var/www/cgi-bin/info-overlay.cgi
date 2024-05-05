#!/usr/bin/haserl
<%in p/common.cgi %>
<%
s=$(df | grep /overlay | xargs | cut -d' ' -f5)
page_title="Contents of the overlay partition"
%>
<%in p/header.cgi %>
<div class="alert alert-primary">
<h5>Overlay partition is <%= $s %> full.</h5>
<% progressbar "${s/%/}" %>
</div>
<% ex "ls -Rl /overlay/" %>
<%in p/reset-firmware.cgi %>
<%in p/footer.cgi %>
