#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Video Recorder"

RECORDER_CONFIG_FILE=/etc/prudynt.json

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

defaults() {
	default_for channel 0
	default_for device_path "$(hostname)/records"
	default_for filename "$RECORD_FILENAME_FB"
	[ "/" = "${filename:0-1}" ] && filename="$RECORD_FILENAME_FB"
	default_for duration 60
	default_for limit 15
}

read_config() {
	[ -f "$RECORDER_CONFIG_FILE" ] || return

	    channel=$(jct $RECORDER_CONFIG_FILE get recorder.channel)
	device_path=$(jct $RECORDER_CONFIG_FILE get recorder.device_path)
	   duration=$(jct $RECORDER_CONFIG_FILE get recorder.duration)
	   filename=$(jct $RECORDER_CONFIG_FILE get recorder.filename)
	      limit=$(jct $RECORDER_CONFIG_FILE get recorder.limit)
	      mount=$(jct $RECORDER_CONFIG_FILE get recorder.mount)
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
		tmpfile="$(mktemp -u).json"
		jct $tmpfile set recorder.channel "$channel"
		jct $tmpfile set recorder.device_path "$device_path"
		jct $tmpfile set recorder.duration "$duration"
		jct $tmpfile set recorder.filename "$filename"
		jct $tmpfile set recorder.limit "$limit"
		jct $tmpfile set recorder.mount "$mount"
		jct "$RECORDER_CONFIG_FILE" import "$tmpfile"
		rm -f "$tmpfile"

		if [ "true" = "$enabled" ]; then
			service start record >/dev/null
		else
			service stop record >/dev/null
		fi

		update_caminfo
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "enabled" "Enable Recorder" %>
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
<% if pidof record > /dev/null; then %>
<h3 class="alert alert-info">Recording in progress.</h3>
<% else %>
<div class="alert alert-danger">
<h3>Recording stopped.</h3>
<p class="mb-0">Please note. The last active recording will continue until the end of the recording time!</p>
</div>
<% fi %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $RECORDER_CONFIG_FILE get recorder" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#mount').value
})
</script>

<%in _footer.cgi %>
