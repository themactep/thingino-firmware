#!/usr/bin/haserl

<%in p/common.cgi %>

<%
	plugin="record"
	plugin_name="Local Recording"
	page_title="Local Recording"
	params="enabled prefix path interval led_enabled led_gpio led_interval"

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
			:>$tmp_file
			for p in $params; do
				echo "${plugin}_${p}=\"$(eval echo \$${plugin}_${p})\"" >>$tmp_file
			done; unset p
			mv $tmp_file $config_file

			# Check if record path exists
			if [ ! -d $record_path ]; then
				echo "Record path $record_path does not exist. Creating" >> /tmp/webui.log
				mkdir -p $record_path >> /tmp/webui.log
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
		[ -z "$record_enabled" ] && record_enabled=false
		[ -z "$record_prefix" ] && record_prefix="thingino-"
		[ -z "$record_path" ] && record_path="/mnt/mmcblk0p1"
		[ -z "$record_interval" ] && record_interval=60
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
			<% field_switch "record_enabled" "Enable Recording" %>
			<% field_text "record_prefix" "Filename Prefix" "e.g. thingino-video-H264-12024-07-11_13-30-00000-00060" %>
			<% field_text "record_path" "Record Path" "Directory will be created if non-existent"%>
			
			<br>NOTE: Record interval currently fixed at 60s<br><br>
			
			<% button_submit %>
		</div>

		<div class="col col-12 col-xl-4">
			<h3>Status LED</h3>
			<% field_switch "record_led_enabled" "Blink LED?" "e.g Flash red status LED when recording"%>
			<% field_number "record_led_gpio" "LED GPIO Pin" "" "Default gpio_led_r" %>
			<% field_range "record_led_interval" "Blink Interval (seconds)" "0,3.0,0.5" "Set to 0 for always on"%>
		</div>
		
		<div class="col">
			<h3>Configuration</h3>
			<% [ -f $config_file ] && ex "cat $config_file" %>
		</div>
	</div>
	
</form>

<%in p/footer.cgi %>
