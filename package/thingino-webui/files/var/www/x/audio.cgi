#!/usr/bin/haserl

<%in p/common.cgi %>

<%
	plugin="audio"
	plugin_name="Audio"
	page_title="Audio"
	params="debug iad_net_audio_enabled iad_net_audio_port"

	tmp_file=/tmp/$plugin

	config_file="${ui_config_dir}/${plugin}.conf"
	[ ! -f "$config_file" ] && touch $config_file

	audio_control=/etc/init.d/S96iad

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
			else
				if [[ $record_path != "/mnt/*" ]]; then
					echo "Record path does not seem to be in sd card location. Disabling" >> /tmp/webui.log
					record_enable=false
					record_path="/mnt/mmcblk0p1/"
				fi
				if [[ $record_path != "/mnt/*/" ]]; then
					echo "record path does not end with "/". Adding" >> /tmp/webui.log
					record_path="$record_path/"
				fi
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

<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
	<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
		<div class="col">
			<h3>Recording</h3>
			<% field_switch "iad_net_enabled" "Enable Incoming Audio" "Live stream audio to the camera over the network" %>
			<% field_number "record_interval" "Incoming Audio Port" "" "Which port to listen on" %>
			<br>
			<% button_submit %>
		</div>

		<div class="col">
		</div>
		
		<div class="col">
			<% field_switch "record_debug" "Enable Debugging" %>
			<h3>Configuration</h3>
			<% [ -f $config_file ] && ex "cat $config_file" %>
		</div>
	</div>
	
</form>

<% fi %>
<%in p/footer.cgi %>
