#!/bin/haserl
<%in _common.cgi %>
<%
page_title="SD Card"
%>
<%in _header.cgi %>
<% if ! grep -l SD$ /sys/bus/mmc/devices/**/type > /dev/null; then %>
<div class="alert alert-danger">
<h3>Does this camera support SD Card?</h3>
<p class="mb-0">Your camera does not have an SD Card slot or SD Card is not inserted.</p>
</div>
<% else
device_name="$(awk -F= '/DEVNAME/{print $2}' /sys/bus/mmc/devices/*/block/*/uevent)"
if [ "POST" = "$REQUEST_METHOD" ]; then %>
<div class="alert alert-danger">
<h3>ATTENTION! SD Card formatting takes time.</h3>
<p>Please do not refresh this page. Wait until partition formatting is finished!</p>
<div class="progress" role="progressbar" aria-label="progress" aria-valuenow="100" aria-valuemin="0" aria-valuemax="100">
<div class="progress-bar progress-bar-striped progress-bar-animated bg-danger" style="width:100%"></div>
</div>
</div>
<% if formatsd $POST_fstype > /dev/null; then %>
<script>$('.alert-danger').remove();</script>
<div class="alert alert-success">
<h3>SD card formatted</h3>
<% ex "fdisk -l /dev/$device_name" %>
</div>
<% else %>
<div class="alert alert-danger">
<h3>Failed to format</h3>
<pre><%= $error %></pre>
</div>
<% fi %>
<a class="btn btn-primary" href="/">Go home</a>
<% else %>
<h4>SD card partitions</h4>
<% ex "df -h | grep 'dev/mmc'" %>
<h4>SD card mounts</h4>
<% ex "grep ^/dev/mmc /proc/mounts" %>
<h2>Format SD card</h2>
<div class="alert alert-danger">
<h3>ATTENTION! Formatting will destroy all data on the SD Card.</h3>
<p>Make sure you have a backup copy if you are going to use the data in the future.</p>
<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row">
<div class="col col-auto">
<div class="btn-group my-2" role="group" aria-label="Filesystem selection buttons">
<input type="radio" class="btn-check" name="fstype" id="fstype-exfat" value="exfat" autocomplete="off" checked>
<label class="btn btn-outline-danger" for="fstype-exfat">EXFAT</label>
<input type="radio" class="btn-check" name="fstype" id="fstype-fat32" value="fat32" autocomplete="off">
<label class="btn btn-outline-danger" for="fstype-fat32">FAT32</label>
</div>
</div>
<div class="col col-auto">
<% button_submit "Format SD Card" "danger" %>
</div>
</div>
</form>
</div>
<% fi; fi %>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% if [ -n "$device_name" ]; then %>
<% ex "fdisk -l /dev/$device_name" %>
<% end %>
</div>

<%in _footer.cgi %>
