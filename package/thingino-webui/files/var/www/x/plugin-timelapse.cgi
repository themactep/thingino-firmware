#!/bin/haserl
<%in _common.cgi %>
<%
plugin="timelapse"
plugin_name="Timelapse"
page_title="Timelapse"
params="enabled interval storage filename"

CRONTABS="/etc/cron/crontabs/root"
MOUNTS=$(awk '/nfs|fat/{print $2}' /etc/mtab)

config_file="$ui_config_dir/timelapse.conf"
include $config_file

defaults() {
	default_for timelapse_enabled "false"
	default_for timelapse_filename "%Y%m%d/%Y%m%dT%H%M.jpg"
	default_for timelapse_interval 1
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "timelapse" "$params"
	defaults

	[ "/" = "${timelapse_filename:0:1}" ] && timelapse_filename="${timelapse_filename:1}"

	error_if_empty "$timelapse_storage" "Timelapse storage cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "timelapse_$p=\"$(eval echo \$timelapse_$p)\"" >>$tmp_file
		done; unset p
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
		redirect_back "success" "$plugin_name config updated."
	fi
	redirect_to $SCRIPT_NAME
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "timelapse_enabled" "Enable timelapse" %>
<div class="row">
<div class="col col-xl-4">
<% field_select "timelapse_storage" "Storage directory" "$MOUNTS" %>
<p><a href="tool-file-manager.cgi?cd=/mnt" id="link-fm">Open in File Manager</a></p>
<div class="row g-1">
<div class="col-9"><% field_text "timelapse_filename" "Filename template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-3"><% field_text "timelapse_interval" "Interval" "minutes" %></div>
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
	ev.target.href = 'tool-file-manager.cgi?cd=' + $('#timelapse_storage').value
})
</script>

<%in _footer.cgi %>
