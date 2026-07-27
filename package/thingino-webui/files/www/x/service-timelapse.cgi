#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Timelapse Recorder"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)
TIMELAPSE_CONFIG_FILE="/etc/timelapse.json"

defaults() {
	default_for tl_filepath "$(hostname)/timelapses"
	default_for tl_filename "%Y%m%d/%Y%m%dT%H%M%S.jpg"
	default_for tl_interval 1
	default_for tl_keep_days 7
}

tl_enabled=$(jct $TIMELAPSE_CONFIG_FILE get enabled)
tl_mount=$(jct $TIMELAPSE_CONFIG_FILE get mount)
tl_filepath=$(jct $TIMELAPSE_CONFIG_FILE get filepath)
tl_filename=$(jct $TIMELAPSE_CONFIG_FILE get filename)
tl_interval=$(jct $TIMELAPSE_CONFIG_FILE get interval)
tl_keep_days=$(jct $TIMELAPSE_CONFIG_FILE get keep_days)

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	tl_enabled="$POST_tl_enabled"
	tl_mount="$POST_tl_mount"
	tl_filepath="$POST_tl_filepath"
	tl_filename="$POST_tl_filename"
	tl_interval="$POST_tl_interval"
	tl_keep_days="$POST_tl_keep_days"

	defaults

	# normalize
	[ "/" = "${tl_filename:0:1}" ] && tl_filename="${tl_filename:1}"

	# validate
	if [ "true" = "$tl_enabled" ]; then
		error_if_empty "$tl_mount" "Timelapse mount cannot be empty."
		error_if_empty "$tl_filename" "Timelapse filename cannot be empty."
	fi

	if [ -z "$error" ]; then
		tmpfile="$(mktemp -u).json"
		jct $tmpfile set enabled "$tl_enabled"
		jct $tmpfile set mount "$tl_mount"
		jct $tmpfile set filepath "$tl_filepath"
		jct $tmpfile set filename "$tl_filename"
		jct $tmpfile set interval "$tl_interval"
		jct $tmpfile set keep_days "$tl_keep_days"
		mv "$tmpfile" "$TIMELAPSE_CONFIG_FILE"

		# update crontab
		tmpfile=$(mktemp -u)
		cat $CRONTABS > $tmpfile
		sed -i '/timelapse/d' $tmpfile
		echo "# run timelapse every $tl_interval minutes" >> $tmpfile
		[ "true" = "$tl_enabled" ] || echo -n "#" >> $tmpfile
		echo "*/$tl_interval * * * * timelapse" >> $tmpfile
		mv $tmpfile $CRONTABS

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "tl_enabled" "Enable timelapse recorder" %>

<div class="row">

<div class="col col-xl-4">
<% field_select "tl_mount" "Storage mountpoint" "$MOUNTS" "SD card or a network share" %>
<% field_text "tl_filepath" "Device-specific path in the storage" "Helps to deal with multiple devices" %>
<% field_text "tl_filename" "Individual image filename template" "$STR_SUPPORTS_STRFTIME" %>
</div>

<div class="col col-xl-4">
<div class="mb-2 string" id="tl_interval_wrap">
<label for="tl_interval" class="form-label">Save a snaphot every
 <input type="text" id="tl_interval" name="tl_interval" class="form-control"
 style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $tl_interval %>">
 minutes</label>
</div>
<div class="mb-2 string" id="tl_keep_days_wrap">
<label for="tl_keep_days" class="form-label">Keep timelapses of the last
 <input type="text" id="tl_keep_days" name="tl_keep_days" class="form-control"
 style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $tl_keep_days %>">
 days</label>
</div>
<p><a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a></p>
</div>

<div class="col col-xl-4">
<div class="alert alert-info">
<p>Modify <code>/sbin/timelapse</code> file if you need to enforce any special timelapse snapshot conditions: IR Cut/IR LED state, color/monochrome mode, etc.</p>
</div>
</div>

</div>
<% button_submit %>
</form>

<div class="alert alert-info">
<p>Use this command on your PC to combine separate still images from the storage directory into a single video file:</p>
<pre class="cb mb-0">ffmpeg -r 10 -f image2 -pattern_type glob -i '*.jpg' -vcodec libx264 -an timelapse.mp4</pre>
</div>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $TIMELAPSE_CONFIG_FILE print" %>
<% ex "crontab -l" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#tl_mount').value + '/' + $('#tl_filepath').value
})
</script>

<%in _footer.cgi %>
