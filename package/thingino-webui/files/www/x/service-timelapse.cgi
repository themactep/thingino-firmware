#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Timelapse Recorder"
params="depth device_path enabled filename interval mount"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
TIMELAPSE_FILENAME_FB="%Y%m%d/%Y%m%dT%H%M%S.jpg"
config_file="$ui_config_dir/timelapse.conf"
include $config_file

# defaults
defaults() {
	default_for timelapse_device_path "$(hostname)/timelapses"
	default_for timelapse_filename "$TIMELAPSE_FILENAME_FB"
	default_for timelapse_interval 1
	default_for timelapse_depth 7
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "timelapse" "$params"
	defaults

	# normalize
	[ "/" = "${timelapse_filename:0:1}" ] && timelapse_filename="${timelapse_filename:1}"

	# validate
	error_if_empty "$timelapse_mount" "Timelapse mount cannot be empty."
	error_if_empty "$timelapse_filename" "Timelapse filename cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp -u)
		[ -f "$config_file" ] && cp "$config_file" "$tmp_file"
		for p in $params; do
			sed -i -r "/^timelapse_$p=/d" "$tmp_file"
			echo "timelapse_$p=\"$(eval echo \$timelapse_$p)\"" >> "$tmp_file"
		done
		mv $tmp_file $config_file

		# update crontab
		tmpfile=$(mktemp -u)
		cat $CRONTABS > $tmpfile
		sed -i '/timelapse/d' $tmpfile
		echo "# run timelapse every $timelapse_interval minutes" >> $tmpfile
		[ "true" = "$timelapse_enabled" ] || echo -n "#" >> $tmpfile
		echo "*/$timelapse_interval * * * * timelapse" >> $tmpfile
		mv $tmpfile $CRONTABS

		update_caminfo
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "timelapse_enabled" "Enable Recorder" %>
<div class="row">

<div class="col col-xl-4">
<% field_select "timelapse_mount" "Storage mount" "$MOUNTS" "SD card or a network share" %>
<% field_text "timelapse_device_path" "Device-specific path" "Helps to deal with multiple devices" %>

<p><a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a></p>
<div class="row g-1">
<div class="col-9"><% field_text "timelapse_filename" "Filename template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-3"><% field_text "timelapse_interval" "Interval" "minutes" %></div>
</div>
<div class="mb-2 string" id="timelapse_depth_wrap">
<label for="timelapse_depth" class="form-label">Keep timelaps of the last <input type="text" id="timelapse_depth"
 name="timelapse_depth" class="form-control" style="max-width:4rem;display:inline-block;margin:0 0.25rem"
  value="<%= $timelapse_depth %>"> days</label>
</div>
</div>
<div class="col col-xl-8">
<div class="alert alert-info">
<p>Use this command to combine separate still images in the storage directory into a video file:</p>
<pre class="cb mb-0">ffmpeg -r 10 -f image2 -pattern_type glob -i '*.jpg' -vcodec libx264 -an timelapse.mp4</pre>
</div>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
<% ex "crontab -l" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#timelapse_mount').value + '/' + $('#timelapse_devicepath').value
})
</script>

<%in _footer.cgi %>
