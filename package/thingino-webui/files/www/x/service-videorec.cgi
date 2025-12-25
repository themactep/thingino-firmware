#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Video Recorder"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

domain="recorder"
config_file="/etc/prudynt.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for autostart "false"
	default_for channel 0
	default_for device_path "$(hostname)/records"
	default_for filename "$RECORD_FILENAME_FB"
	[ "/" = "${filename:0-1}" ] && filename="$RECORD_FILENAME_FB"
	default_for duration 60
	default_for limit 15
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	jct "$temp_config_file" set "$domain.$1" "$2" >/dev/null 2>&1
}

get_value() {
	jct "$config_file" get "$domain.$1" 2>/dev/null
}

read_config() {
	[ -f "$config_file" ] || return

	autostart=$(get_value autostart)
	channel=$(get_value channel)
	device_path=$(get_value device_path)
	duration=$(get_value duration)
	filename=$(get_value filename)
	limit=$(get_value limit)
	mount=$(get_value mount)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	autostart="$POST_autostart"
	channel="$POST_channel"
	device_path="$POST_device_path"
	duration="$POST_duration"
	filename="$POST_filename"
	limit="$POST_limit"
	mount="$POST_mount"

	defaults

	# normalize
	[ "/" = "${filename:0:1}" ] && filename="${filename:1}"

	# validate
	error_if_empty "$mount" "Record mount cannot be empty."
	error_if_empty "$filename" "Record filename cannot be empty."

	if [ -z "$error" ]; then
		set_value autostart "$autostart"
		set_value channel "$channel"
		set_value device_path "$device_path"
		set_value duration "$duration"
		set_value filename "$filename"
		set_value limit "$limit"
		set_value mount "$mount"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		update_caminfo

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
<% field_select "mount" "Storage mount" "$MOUNTS" "SD card or a network share" %>
<div class="row g-1">
<div class="col-8"><% field_text "device_path" "Device-specific path" "Helps to deal with multiple devices" %></div>
<div class="col-4"><% field_number "limit" "Storage limit" "" "gigabytes" %></div>
</div>
<a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a>

<div class="row g-1">
<div class="col-8"><% field_text "filename" "File name template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-2"><% field_select "channel" "Channel" "0,1" %></div>
<div class="col-2"><% field_number "duration" "Duration" "" "seconds" %></div>
</div>
</div>
<div class="col">
<% field_switch "autostart" "Start recording on boot" %>
</div>
</div>
<% button_submit %>
</form>

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
