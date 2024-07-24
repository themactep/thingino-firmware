#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Log read" %>
<%in p/header.cgi %>
<% ex "/sbin/logread" %>
<% button_refresh %>
<% button_download "logread" %>
<a class="btn btn-warning" href="send.cgi?to=termbin&file=logread" target="_blank">Send to TermBin</a>
<%in p/footer.cgi %>
