#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Diagnostic log"
if [ "POST" = "$REQUEST_METHOD" ]; then
	[ "true" = "$POST_iagree" ] || set_error_flag "You must explicitly give your consent."
	[ -z "$error" ] && result=$(yes yes | thingino-diag | tail -1)
fi
%>
<%in _header.cgi %>
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-6">
<% if [ -z "$result" ]; then %>
<p>The button below generates a massive log that needs to be further shared with developers to help them diagnose problems.
That log may contain sensitive or personal information, so be sure to review the result before sharing the link!</p>
<p>We use the termbin.com service to share the log. Please review their <a href="https://www.termbin.com/" target="_blank">acceptable use policy</a>.</p>
<form action="<%= $SCRIPT_NAME %>" method="post">
<p><label><input type="checkbox" name="iagree" id="iagree" value="true" class="form-check-input me-1">
I've read and understood the information above. I want to proceed.</label></p>
<p><input type="submit" class="btn btn-primary" value="Generate the diagnostic log"></p>
</form>
<% else %>
<% if [ "https://" = "${result:0:8}" ]; then %>
<h3 class="mb-4"><a href="<%= $result %>"><%= $result %></a></h3>
<p>Please review the link and share it with the developers.</p>
<% else %>
<h3 class="text-danger"><%= $result %></h3>
<% fi %>
<% fi %>
</div>
</div>
<%in _footer.cgi %>
