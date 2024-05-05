#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Top processes" %>
<%in p/header.cgi %>
<% ex "top -n 1 -b" %>
<%in p/footer.cgi %>
