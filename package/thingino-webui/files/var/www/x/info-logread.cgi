#!/bin/haserl
<%in _common.cgi %>
<% page_title="logread" %>
<%in _header.cgi %>
<% ex "/sbin/logread" %>
<% button_refresh %>
<% button_download "logread" %>
<% button_send2tb "logread" %>
<%in _footer.cgi %>
