#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Majestic configuration changes" %>
<%in p/header.cgi %>
<div class="row">
<div class="col-md-8 col-lg-9 col-xl-9 col-xxl-10">
<%
config_file=/etc/majestic.yaml
diff /rom$config_file $config_file >/tmp/majestic.patch
ex "cat /tmp/majestic.patch"
%>
</div>
<div class="col-md-4 col-lg-3 col-xl-3 col-xxl-2">
<div class="d-grid d-sm-flex d-md-grid gap-2">
<a class="btn btn-secondary" href="texteditor.cgi?f=<%= $config_file %>">Edit config as text</a>
</div>
</div>
</div>
<%in p/footer.cgi %>
