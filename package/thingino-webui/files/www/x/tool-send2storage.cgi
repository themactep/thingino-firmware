#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Send to Storage"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)

domain="storage"
config_file="/etc/send2.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for template "${network_hostname}-%Y%m%d-%H%M%S"
	default_for send_photo "false"
	default_for send_video "false"
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	mount=$(get_value mount)
	device_path=$(get_value device_path)
	template=$(get_value template)
	send_photo=$(get_value send_photo)
	send_video=$(get_value send_video)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	mount="$POST_mount"
	device_path="$POST_device_path"
	template="$POST_template"
	send_photo="$POST_send_photo"
	send_video="$POST_send_video"

	error_if_empty "$mount" "Mount point cannot be empty."
	error_if_empty "$template" "Filename template cannot be empty."

	defaults

	if [ -z "$error" ]; then
		set_value mount "$mount"
		set_value device_path "$device_path"
		set_value template "$template"
		set_value send_photo "$send_photo"
		set_value send_video "$send_video"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3">
<div class="col">
<% field_select "mount" "Storage mount point" "$MOUNTS" "SD card or network share" %>
<% field_text "device_path" "Device-specific path" "Subdirectory within mount point (optional)" %>
<a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a>
</div>
<div class="col">
<% field_text "template" "Filename template" "$STR_SUPPORTS_STRFTIME" "do not use extension" %>
<p class="label">Media to save</p>
<% field_switch "send_photo" "Save photo" %>
<% field_switch "send_video" "Save video" %>
</div>
<div class="col">
<div class="alert alert-info">
<p>Save snapshots and video clips to a mounted storage device (SD card or network share).</p>
<p class="small mb-0">The mount point must be writable. Files will be saved with automatic .jpg or .mp4 extension.</p>
</div>
</div>
</div>
<% button_submit %>
</form>

<button type="button" class="btn btn-dark border mb-2" title="Send to Storage" data-sendto="storage">Test</button>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#mount').value
})
</script>

<%in _footer.cgi %>
