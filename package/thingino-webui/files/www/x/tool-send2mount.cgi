#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Save to Mount"

defaults() {
	default_for "send_mount_save_mount" "/mnt/mmcblk0p1"
	default_for "send_mount_save_subdir" "records"
	default_for "send_mount_save_template" "${network_hostname}-%Y%m%d-%H%M%S"
	default_for "send_mount_save_video" "false"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""
	read_from_post "send_mount_save" "mount subdir template video"
	[ -z "$send_mount_save_mount" ] && error="Directory mount cannot be empty."
	[ -z "$send_mount_save_subdir" ] && error="Sub directory cannot be empty."
	defaults

	if [ -z "$error" ]; then
		save2config "
send_mount_save_mount=\"$send_mount_save_mount\"
send_mount_save_subdir=\"$send_mount_save_subdir\"
send_mount_save_template=\"$send_mount_save_template\"
send_mount_save_video=\"$send_mount_save_video\"
"
		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
	<div class="row row-cols-1 row-cols-md-2">
		<div class="col">
			<% field_text "send_mount_save_mount" "Mount point for storage" "External storage mount point such as sdcard or NFS mount." %>
			<% field_text "send_mount_save_subdir" "Sub directory to use on mount point" "Relative path to save files on mount point" %>
			<% field_text "send_mount_save_template" "Filename template" "$STR_SUPPORTS_STRFTIME" "without extension" %>
		</div>
		<div class="col">
			<% field_checkbox "send_mount_save_video" "Save video buffer instead of snapshot" %>
		</div>
	</div>
	<% button_submit %>
</form>

<a href="gallery-send2mount.cgi" class="btn btn-secondary border mb-2" title="Open Gallery">Open Gallery</a>
<button type="button" class="btn btn-dark border mb-2" title="Save Now" data-sendto="savemount">Test</button>

<div class="alert alert-dark ui-debug d-none">
	<h4 class="mb-3">Debug info</h4>
	<% ex "grep ^save_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
