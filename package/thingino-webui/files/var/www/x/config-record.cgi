#!/bin/haserl
<%in _common.cgi %>
<%
plugin="record"
plugin_name="Local Recording"
page_title="Local Recording"
params="debug enabled prefix path format interval loop diskusage led_enabled led_gpio led_interval"

tmp_file=/tmp/$plugin
config_file="${ui_config_dir}/${plugin}.conf"
[ ! -f "$config_file" ] && touch $config_file

record_control=/etc/init.d/S96record

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_${p}=\$POST_${plugin}_${p}
		sanitize "${plugin}_${p}"
	done; unset p

	# validation

	if [ -z "$error" ]; then
		# Check if record path starts and ends with "/"
		if [ -z $record_path ]; then
			echo "Record path cannot be empty. Disabling." >> /tmp/webui.log
			record_enable=false
			record_path="/mnt/mmcblk0p1/"
		elif [ "${record_path: -1}" != '/' ]; then
				echo "record path does not end with "/". Adding" >> /tmp/webui.log
				record_path="$record_path/"
		fi

		# Checking if LED GPIO is defined, otherwise disable
		if [ -z "$record_led_gpio" ]; then
			record_led_enabled=false
			echo "LED GPIO PIN not defined. Disabling blink" >> /tmp/webui.log
		fi

		# Check if max disk usage is defined, otherwise default to 85%
		if [ -z "$record_diskusage" ]; then
			record_diskusage=85
			echo "Max Disk Usage not defined. Defaulting to 85%" >> /tmp/webui.log
		fi

		:>$tmp_file
		for p in $params; do
			echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		# Check if record path exists
		if [ ! -d "$record_path" ]; then
			echo "Record path $record_path does not exist. Creating" >> /tmp/webui.log
			mkdir -p "$record_path" >> /tmp/webui.log
		fi

		if [ -f "$record_control" ]; then
			$record_control restart >> /tmp/webui.log
		else
			echo "$record_control not found" >> /tmp/webui.log
		fi

		update_caminfo
		redirect_to "$SCRIPT_NAME"
	fi
else
	include $config_file

	# default values
	[ -z "$record_debug" ] && record_debug=true
	[ -z "$record_enabled" ] && record_enabled=false
	[ -z "$record_prefix" ] && record_prefix="thingino-"
	[ -z "$record_path" ] && record_path="/mnt/mmcblk0p1/"
	[ -z "$record_format" ] && record_format="avi"
	[ -z "$record_interval" ] && record_interval=60
	[ -z "$record_loop" ] && record_loop=true
	[ -z "$record_diskusage" ] && record_diskusage=85
	[ -z "$record_led_enabled" ] && record_led_enabled=false
	[ -z "$record_led_gpio" ] && record_led_gpio=$(get gpio_led_r)
	[ -z "$record_led_interval" ] && record_led_interval=1
fi
%>
<%in _header.cgi %>

<%
case "$record_path" in
	*/mnt/mmcblk0p*)	dir_sd="true" 
	;;
	*/mnt*) 			dir_mnt=true
	;;
	*)
		dir_mnt=false
		dir_sd=false
	;;
esac

if [ $dir_mnt != "true" ]; then %>
	<div class="alert alert-danger">
		<h4>Caution: Is your save path correct?</h4>
		<p>The record path is set outside of <b>/mnt/</b>.  Ignore this message if you know what you are doing</p>
	</div>
<% elif [ $dir_sd = "true" ]; then
	if ! ls /dev/mmc* >/dev/null 2>&1; then %>
		<div class="alert alert-danger">
			<h4>SD Card not detected</h4>
			<p>An SD Card is not inserted or mounted at this record directory</p>
			<p>Insert an SD card if your camera supports it. Alternatively, set up a file sharing mount</p>
		</div>
	<% fi %>
<% fi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h3>Recording</h3>
<% field_switch "record_enabled" "Enable Recording" %>
<% field_text "record_prefix" "Filename Prefix" "e.g. thingino-yyyy-mm-dd_HH-MM-SS.mp4" "thingino-" %>
<% field_text "record_path" "Record Directory" "Directory will be created if non-existent" "/"%>
<% field_select "record_format" "Output File Format" "mov, mp4, avi" %>
<% field_number "record_interval" "Recording Interval (seconds)" "" "How long to record in each file" %>
<% field_checkbox "record_loop" "Loop Recording" "Delete oldest file to make space for newer recordings"%>
<% field_number "record_diskusage" "Max disk space usage %" "" "How much disk space to use before stopping/ deleting old files" %>
<p><% button_submit %></p>
</div>

<div class="col col-12 col-xl-4">
<h3>Status LED</h3>
<% field_switch "record_led_enabled" "Blink LED" "Flash a status LED when recording"%>
<% field_number "record_led_gpio" "LED GPIO Pin" "" "Default: gpio_led_r" %>
<% field_range "record_led_interval" "Blink Interval (seconds)" "0,3.0,0.5" "Set to 0 for always on"%>
</div>

<div class="col">
<% field_switch "record_debug" "Enable Debugging" %>
<h3>Configuration</h3>
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>
</div>
</form>
<%in _footer.cgi %>
