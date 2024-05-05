#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Illumination"
if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	if [ -n "$POST_day_night_threshold" ]; then
		if [ -n "$POST_day_night_tolerance" ]; then
			day_night_max=$(( $POST_day_night_threshold + $POST_day_night_tolerance ))
			day_night_min=$(( $POST_day_night_threshold - $POST_day_night_tolerance ))
		fi
	fi

	[ -z "$day_night_min" ] && day_night_min=400
	[ -z "$day_night_max" ] && day_night_max=600

	# save values to env
	update_uboot_env day_night_min $day_night_min
	update_uboot_env day_night_max $day_night_max
	update_uboot_env gpio_ir850 $POST_ir850_pin
	update_uboot_env pwm_ch_ir850 $POST_ir850_channel
	update_uboot_env gpio_ir940 $POST_ir940_pin
	update_uboot_env pwm_ch_ir940 $POST_ir940_channel
	update_uboot_env gpio_white $POST_white_pin
	update_uboot_env pwm_ch_white $POST_white_channel
	update_uboot_env gpio_ircut "$POST_ircut_pin1 $POST_ircut_pin2"
fi

# read data from env
day_night_min=$(fw_printenv -n day_night_min)
day_night_max=$(fw_printenv -n day_night_max)
ir850_pin=$(fw_printenv -n gpio_ir850)
ir850_channel=$(fw_printenv -n pwm_ch_ir850)
ir940_pin=$(fw_printenv -n gpio_ir940)
ir940_channel=$(fw_printenv -n pwm_ch_ir940)
white_pin=$(fw_printenv -n gpio_white)
white_channel=$(fw_printenv -n pwm_ch_white)
ircut_pins=$(fw_printenv -n gpio_ircut)
ircut_pin1=$(echo $ircut_pins | awk '{print $1}')
ircut_pin2=$(echo $ircut_pins | awk '{print $2}')

# calculate threshold and tolerance from min and max limits
if [ -n "$day_night_min" ]; then
	if [ -n "$day_night_max" ]; then
		day_night_tolerance=$(( ($day_night_max - $day_night_min) / 2 ))
		day_night_threshold=$(( $day_night_min + $day_night_tolerance ))
	fi
fi

[ -z "$day_night_threshold" ] && day_night_threshold=500
[ -z "$day_night_tolerance" ] && day_night_tolerance=100
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_number "ir850_pin" "850 nm IR LED GPIO pin" %>
<% field_number "ir850_channel" "850 nm IR LED PWM channel" %>
<% field_number "ir940_pin" "940 nm IR LED GPIO pin" %>
<% field_number "ir940_channel" "940 nm IR LED PWM channel" %>
<% field_number "white_pin" "White Light LED GPIO pin" %>
<% field_number "white_channel" "White Light LED PWM channel" %>
</div>
<div class="col">
<% field_number "ircut_pin1" "IR CUT filter GPIO pin 1" %>
<% field_number "ircut_pin2" "IR CUT filter GPIO pin 2" %>
<% field_number "day_night_threshold" "Day/Night Trigger Threshold" %>
<% field_number "day_night_tolerance" "Day/Night Tolerance" %>
</div>
<div class="col">
<h3>Environment Settings</h3>
<pre>
gpio_ir850: <%= $ir850_pin %>
pwm_ch_ir850: <%= $ir850_channel %>
gpio_ir940: <%= $ir940_pin %>
pwm_ch_ir940: <%= $ir940_channel %>
gpio_white: <%= $white_pin %>
pwm_ch_white: <%= $white_channel %>
gpio_ircut: <%= $ircut_pins %>
day_night_min: <%= $day_night_min %>
day_night_max: <%= $day_night_max %>
</pre>
</div>
<div class="col">
<% button_webui_log %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
