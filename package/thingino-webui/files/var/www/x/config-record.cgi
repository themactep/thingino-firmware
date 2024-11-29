#!/bin/haserl
<%in _common.cgi %>
<%
plugin="record"
page_title="Video Recording"
params="blink debug diskusage duration enabled filename led loop mount videoformat"

# constants
MOUNTS=$(awk '/nfs|fat/{print $2}' /etc/mtab)
RECORD_CTL="/etc/init.d/S96record"
RECORD_FILENAME_FB="thingino/%F/%FT%H%M"
config_file="$ui_config_dir/$plugin.conf"
include $config_file

# defaults
default_for record_blink 1
default_for record_debug true
default_for record_diskusage 85
default_for record_duration 60
default_for record_enabled "false"
default_for record_led $(fw_printenv | awk -F= '/^gpio_led/{print $1;exit}')
default_for record_loop "true"
default_for record_videoformat "mp4"
default_for record_filename "$RECORD_FILENAME_FB"
[ "/" = "${record_filename:0-1}" ] && record_filename="$RECORD_FILENAME_FB"

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "$plugin" "$params"

	# normalize
	[ "/" = "${record_filename:0:1}" ] && record_filename="${record_filename:1}"

	# validate
	error_if_empty "$record_mount" "Record mount cannot be empty."
	error_if_empty "$record_filename" "Record filename cannot be empty."

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		if [ -f "$RECORD_CTL" ]; then
			if [ "true" = "$record_enabled" ]; then
				$RECORD_CTL start > /dev/null
			else
				$RECORD_CTL stop > /dev/null
			fi
		fi

		update_caminfo
		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<% field_switch "record_enabled" "Enable Recording" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_select "record_mount" "Record storage directory" "$MOUNTS" %>
<div class="row g-1">
<div class="col-9"><% field_text "record_filename" "File name template" "$STR_SUPPORTS_STRFTIME" %></div>
<div class="col-3"><% field_select "record_videoformat" "Format" "mov, mp4" "also extention" %></div>
</div>
<% field_checkbox "record_loop" "Loop Recording" "Delete older files as needed." %>
</div>
<div class="col">
<% field_range "record_diskusage" "Total disk space usage limit, %" "5,95,5" %>
<% field_number "record_duration" "Recording duration per file, seconds" %>
</div>
<div class="col">
<% field_select "record_led" "Indicator LED" "$(fw_printenv | awk -F= '/^gpio_led/{print $1}')" %>
<% field_range "record_blink" "Blink interval, seconds" "0,3.0,0.5" "Set to 0 for always on" %>
</div>
</div>
<% button_submit %>
</form>

<% if pidof record > /dev/null; then %>
<h3 class="alert alert-info">Recording in progress.</h3>
<% else %>
<div class="alert alert-danger">
<h3>Recording stopped.</h3>
<p class="mb-0">Please note. The last active recording will continue until the end of the recording time!</p>
</div>
<% fi %>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "cat $config_file" %>
</div>

<%in _footer.cgi %>
