#!/usr/bin/haserl
<%in p/common.cgi %>
<% page_title="Majestic config" %>
<%in p/header.cgi %>
<% ex "cat /etc/majestic.yaml" %>
<p><a class="btn btn-warning" href="texteditor.cgi?f=/etc/majestic.yaml">Edit file</a></p>
<% button_restore_from_rom "/etc/majestic.yaml" %>
<%in p/footer.cgi %>
