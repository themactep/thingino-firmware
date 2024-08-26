#!/bin/haserl
<%in _common.cgi %>
<% page_title="Cron jobs" %>
<%in _header.cgi %>
<% ex "cat /etc/crontabs/root" %>
<p><a href="https://devhints.io/cron">Cron syntax cheatsheet</a></p>
<p><a class="btn btn-warning" href="texteditor.cgi?f=/etc/crontabs/root">Edit file</a></p>
<%in _footer.cgi %>
