#!/usr/bin/haserl
<%in _common.cgi %>
<% page_title="Log read" %>
<%in _header.cgi %>
<% ex "/sbin/logread" %>
<% button_refresh %>
<% button_download "logread" %>
<a class="btn btn-warning" href="send.cgi?to=termbin&file=logread" target="_blank">Send to TermBin</a>
<%in _footer.cgi %>
