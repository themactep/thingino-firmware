#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Video Recorder"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
RECORD_FILENAME_FB="%Y%m%d/%H/%Y%m%dT%H%M%S"

defaults() {
	default_for record_enabled "false"
	default_for record_device_path "$(hostname)/records"
	default_for record_filename "$RECORD_FILENAME_FB"
	[ "/" = "${record_filename:0-1}" ] && record_filename="$RECORD_FILENAME_FB"
	default_for $record_videofmt "mp4"
	default_for record_duration 60
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	read_from_post "record" "device_path duration enabled filename limit mount videofmt"

	defaults

	# normalize
	[ "/" = "${record_filename:0:1}" ] && record_filename="${record_filename:1}"

	# validate
	if [ "true" = "$record_enabled" ]; then
		error_if_empty "$record_mount" "Record mount cannot be empty."
		error_if_empty "$record_filename" "Record filename cannot be empty."
	fi

	if [ -z "$error" ]; then
		save2config "
record_device_path=\"$record_device_path\"
record_duration=\"$record_duration\"
record_enabled=\"$record_enabled\"
record_filename=\"$record_filename\"
record_limit=\"$record_limit\"
record_mount=\"$record_mount\"
record_videofmt=\"$record_videofmt\"
"
		if [ "true" = "$record_enabled" ]; then
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
<% field_switch "record_enabled" "Enable Recorder" %>
<div class="row row-cols-1 row-cols-md-2">

<div class="col">

<% field_select "record_mount" "Storage mount" "$MOUNTS" "SD card or a network share" %>
<div class="row g-1">
<div class="col-8"><% field_text "record_device_path" "Device-specific path" "Helps to deal with multiple devices" %></div>
<div class="col-4"><% field_number "record_limit" "Storage limit" "" "gigabytes" %></div>
</div>
<a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a>

<div class="row g-1">
<div class="col-8"><% field_text "record_filename" "File name template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-2"><% field_number "record_duration" "Duration" "" "seconds" %></div>
<div class="col-2"><% field_select "record_videofmt" "Format" "mp4,mkv,mov" "also extension" %></div>
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
<% ex "grep ^record_ $CONFIG_FILE" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#record_mount').value
})
</script>

<%in _footer.cgi %>
