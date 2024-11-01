#!/bin/haserl
<%in _common.cgi %>
<%
plugin="timelapse"
plugin_name="Timelapse"
page_title="Timelapse"
params="enabled interval storage filename"

# constants
CRONTABS="/etc/crontabs/root"
MOUNTS=$(awk '/nfs|fat/{print $2}' /etc/mtab)

config_file="$ui_config_dir/$plugin.conf"
include $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	# defaults
	[ -z "$timelapse_enabled"  ] && timelapse_enabled="false"
	[ -z "$timelapse_filename" ] && timelapse_filename="%Y%m%d%H%M.jpg"
	[ -z "$timelapse_interval" ] && timelapse_interval=1

	# normalize
	[ "/" = "${timelapse_filename:0:1}" ] && timelapse_filename="${timelapse_filename:1}"

	# validate
	[ -z "$timelapse_storage" ] && set_error_flag "Timelapse storage cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
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
else
	[ -z "$timelapse_enabled"  ] && timelapse_enabled="false"
	[ -z "$timelapse_filename" ] && timelapse_filename="%Y%m%d%H%M.jpg"
	[ -z "$timelapse_interval" ] && timelapse_interval=1
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "${plugin}_enabled" "Enable $plugin" %>
<div class="row g-4 mb-4">
<div class="col">
<% field_select "${plugin}_storage" "Storage directory" "$MOUNTS" %>
<div class="row g-1">
<div class="col-9"><% field_text "${plugin}_filename" "Filename template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-3"><% field_text "${plugin}_interval" "Interval" "minutes" %></div>
</div>

<div class="alert alert-info">
<p>Use the following command to combine separate still images in the storage directory into one video file:</p>
<pre class="cb">ffmpeg -r 10 -f image2 -pattern_type glob -i '*.jpg' \
	-vcodec libx264 -an timelapse.mp4</pre>
</div>
</div>
<div class="col">
<% ex "cat $config_file" %>
<% ex "crontab -l" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
