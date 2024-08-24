#!/bin/haserl
<%in _common.cgi %>
<% page_title="Diagnostic messages" %>
<%in _header.cgi %>
<% ex "dmesg" %>
<% button_refresh %>
<% button_download "dmesg" %>
<% button_send2tb "dmesg" %>
<%in _footer.cgi %>
