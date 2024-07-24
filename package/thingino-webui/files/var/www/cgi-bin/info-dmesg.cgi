#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Diagnostic messages" %>
<%in p/header.cgi %>
<% ex "/bin/dmesg" %>
<% button_refresh %>
<% button_download "dmesg" %>
<a class="btn btn-warning" href="send.cgi?to=termbin&file=dmesg" target="_blank">Send to TermBin</a>
<%in p/footer.cgi %>
