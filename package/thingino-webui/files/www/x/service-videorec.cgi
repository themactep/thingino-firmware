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
	default_for channel 0
	default_for device_path "$(hostname)/records"
	default_for filename "$RECORD_FILENAME_FB"
	[ "/" = "${filename:0-1}" ] && filename="$RECORD_FILENAME_FB"
	default_for duration 60
	default_for limit 15
}

set_value() {
	[ -f "$temp_config_file" ] || echo '{}' > "$temp_config_file"
	local sanitized_value
	sanitized_value="$(sanitize_json_value "$2")"
	jct "$temp_config_file" set "$domain.$1" "$sanitized_value" >/dev/null 2>&1
}

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

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
		set_value channel "$channel"
		set_value device_path "$device_path"
		set_value duration "$duration"
		set_value filename "$filename"
		set_value limit "$limit"
		set_value mount "$mount"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		if [ "true" = "$enabled" ]; then
			service start record >/dev/null
		else
			service stop record >/dev/null
		fi

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
<% field_switch "enabled" "Start recording on boot" %>

<%
configured_channel=$(jct "$config_file" get "$domain.channel" 2>/dev/null || echo "0")
ch0_active=""
ch1_active=""
[ -f "/run/prudynt/mp4ctl-ch0.active" ] && ch0_active="yes"
[ -f "/run/prudynt/mp4ctl-ch1.active" ] && ch1_active="yes"

recording_active=""
if [ "$configured_channel" = "0" ] && [ -n "$ch0_active" ]; then
	recording_active="yes"
elif [ "$configured_channel" = "1" ] && [ -n "$ch1_active" ]; then
	recording_active="yes"
fi

if [ -n "$recording_active" ]; then %>
<div class="alert alert-info">
<h3>Recording in progress</h3>
<p class="mb-1">Channel <%= $configured_channel %>: Active</p>
<button type="button" class="btn btn-danger btn-sm" onclick="controlRecording('stop')">Stop Recording</button>
</div>
<% else %>
<div class="alert alert-warning">
<h3>Recording stopped</h3>
<p class="mb-1">Channel <%= $configured_channel %>: Ready</p>
<button type="button" class="btn btn-primary btn-sm" onclick="controlRecording('start')">Start Recording</button>
</div>
<% fi %>

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

function controlRecording(action) {
	const cmd = action === 'start' ? 'record -x' : 'echo "STOP" > /run/prudynt/mp4ctl'
	fetch('/x/run.cgi', {
		method: 'POST',
		headers: {'Content-Type': 'application/x-www-form-urlencoded'},
		body: 'cmd=' + encodeURIComponent(cmd)
	}).then(() => {
		setTimeout(() => location.reload(), 1000)
	}).catch(err => {
		console.error('Recording control failed:', err)
		alert('Failed to ' + action + ' recording')
	})
}
</script>

<%in _footer.cgi %>
