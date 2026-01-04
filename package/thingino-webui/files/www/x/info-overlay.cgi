#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Overlay partition"
s=$(df | awk '/\/overlay/{print $5}')
s_pct=${s%\%}
progress_class="primary"
[ "${s_pct:-0}" -ge 75 ] && progress_class="danger"
%>
<%in _header.cgi %>

<div class="alert alert-primary">
  <h5>Overlay partition is <%= $s %> full.</h5>
  <div class="progress" role="progressbar" aria-label="Overlay" aria-valuenow="<%= $s_pct %>" aria-valuemin="0" aria-valuemax="100">
    <div class="progress-bar progress-bar-striped progress-bar-animated bg-<%= $progress_class %>" style="width:100%"></div>
  </div>
</div>

<% ex "ls -Rl /overlay/" %>

<%in _footer.cgi %>
