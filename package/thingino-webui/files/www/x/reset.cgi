#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Reset things"
%>
<%in _header.cgi %>
<div class="row row-cols-md-3 g-4 mb-4">
<div class="col">
<div class="alert alert-danger">
<h4>Reboot camera</h4>
<p>Reboot camera to apply new settings. That will also delete all data stored in partitions mounted into system memory, e.g. /tmp.</p>
<form action="reboot.cgi" method="post">
<input type="hidden" name="action" value="reboot">
<% button_submit "Reboot camera" "danger" %>
</form>
</div>
</div>
<div class="col">
<div class="alert alert-danger">
<h4>Wipe overlay</h4>
<p>Wiping out overlay will remove all <a href="info-overlay.cgi">files stored in the overlay</a> partition.
 That means that most of customization will be lost!</p>
<form action="firmware-reset.cgi" method="post">
<input type="hidden" name="action" value="wipeoverlay">
<input type="hidden" name="cmd" value="<% echo "flash_eraseall -j /dev/mtd4" | base64 %>">
<% button_submit "Wipe overlay" "danger" %>
</form>
</div>
</div>
<div class="col">
<div class="alert alert-danger">
<h4>Reset firmware</h4>
<p>Totally revert firmware to its original state. All custom settings and all files stored in the overlay partition will be lost!</p>
<form action="firmware-reset.cgi" method="post">
<input type="hidden" name="action" value="fullreset">
<input type="hidden" name="cmd" value="<% echo "firstboot -f" | base64 %>">
<% button_submit "Reset firmware" "danger" %>
</form>
</div>
</div>
</div>
<%in _footer.cgi %>
