#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Timelapse Recorder"

MOUNTS=$(awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab)

domain="timelapse"
config_file="/etc/timelapse.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for filepath "$(hostname)/timelapses"
	default_for filename "%Y%m%d/%Y%m%dT%H%M%S.jpg"
	default_for interval 1
	default_for keep_days 7
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

	enabled=$(get_value enabled)
	mount=$(get_value mount)
	filepath=$(get_value filepath)
	filename=$(get_value filename)
	interval=$(get_value interval)
	keep_days=$(get_value keep_days)
}

read_config

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	enabled="$POST_enabled"
	mount="$POST_mount"
	filepath="$POST_filepath"
	filename="$POST_filename"
	interval="$POST_interval"
	keep_days="$POST_keep_days"

	defaults

	# normalize
	[ "/" = "${filename:0:1}" ] && filename="${filename:1}"

	# validate
	if [ "true" = "$enabled" ]; then
		error_if_empty "$mount" "Timelapse mount cannot be empty."
		error_if_empty "$filename" "Timelapse filename cannot be empty."
	fi

	if [ -z "$error" ]; then
		set_value enabled "$enabled"
		set_value mount "$mount"
		set_value filepath "$filepath"
		set_value filename "$filename"
		set_value interval "$interval"
		set_value keep_days "$keep_days"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		# update crontab
		tmpfile=$(mktemp -u)
		cat $CRONTABS > $tmpfile
		sed -i '/timelapse/d' $tmpfile
		echo "# run timelapse every $interval minutes" >> $tmpfile
		[ "true" = "$enabled" ] || echo -n "#" >> $tmpfile
		echo "*/$interval * * * * timelapse" >> $tmpfile
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

<div class="row">
<div class="col col-xl-4">
<% field_switch "enabled" "Launch timelapse recorder on boot" %>
<% field_select "mount" "Storage mountpoint" "$MOUNTS" "SD card or a network share" %>
<% field_text "filepath" "Device-specific path in the storage" "Helps to deal with multiple devices" %>
<% field_text "filename" "Individual image filename template" "$STR_SUPPORTS_STRFTIME" %>
</div>
<div class="col col-xl-4">
<div class="mb-2 string" id="interval_wrap">
<label for="interval" class="form-label">Save a snapshot every <input type="text" id="interval" name="interval"
class="form-control" style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $interval %>"> minutes</label>
</div>
<div class="mb-2 string" id="keep_days_wrap">
<label for="keep_days" class="form-label">Keep timelapses of the last <input type="text" id="keep_days" name="keep_days"
class="form-control" style="max-width:4rem;display:inline-block;margin:0 0.25rem" value="<%= $keep_days %>"> days</label>
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
<% ex "jct $config_file get $domain" %>
<% ex "crontab -l" %>
</div>

<script>
$('#link-fm').addEventListener('click', ev => {
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#mount').value + '/' + $('#filepath').value
})
</script>

<%in _footer.cgi %>
