#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Illumination"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# values from the form
	ir850_pin=$POST_ir850_pin
	ir850_pwm=$POST_ir850_pwn
	ir940_pin=$POST_ir940_pin
	ir940_pwm=$POST_ir940_pwn
	white_pin=$POST_white_pin
	white_pwm=$POST_white_pwn
	ircut_pin1=$POST_ircut_pin1
	ircut_pin2=$POST_ircut_pin2
	day_night_max=$POST_day_night_max
	day_night_min=$POST_day_night_min

	# default values
	[ -z "$day_night_min" ] && day_night_min=400
	[ -z "$day_night_max" ] && day_night_max=600

	# save values to env
	tmpfile=$(mktemp)
	echo "day_night_min $day_night_min" >> $tmpfile
	echo "day_night_max $day_night_max" >> $tmpfile
	echo "gpio_ir850 $ir850_pin" >> $tmpfile
	echo "pwm_ch_ir850 $ir850_pwm" >> $tmpfile
	echo "gpio_ir940 $ir940_pin" >> $tmpfile
	echo "pwm_ch_ir940 $ir940_pwm" >> $tmpfile
	echo "gpio_white $white_pin" >> $tmpfile
	echo "pwm_ch_white $white_pwm" >> $tmpfile
	echo "gpio_ircut $ircut_pin1 $ircut_pin2" >> $tmpfile
	fw_setenv -s $tmpfile
	rm $tmpfile
fi

# read data from env
ir850_pin=$(get gpio_ir850)
ir850_pwn=$(get pwm_ch_ir850)
ir940_pin=$(get gpio_ir940)
ir940_pwn=$(get pwm_ch_ir940)
white_pin=$(get gpio_white)
white_pwn=$(get pwm_ch_white)
day_night_min=$(get day_night_min)
day_night_max=$(get day_night_max)

ircut_pins=$(get gpio_ircut)
ircut_pin1=$(echo $ircut_pins | awk '{print $1}')
ircut_pin2=$(echo $ircut_pins | awk '{print $2}')

# read data from cron
cron_line=$(sed -n /daynight/p /etc/crontabs/root)

#[[ "$cron_line" =~ "^#" ]] && cron_enable="false" || cron_enable="true"

# default values
[ -z "$day_night_min" ] && day_night_min=400
[ -z "$day_night_max" ] && day_night_max=600

%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
	<h5>850 nm IR LED</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "ir850_pin" "GPIO pin" %></div>
		<div class="col"><% field_number "ir850_pwn" "PWM channel" %></div>
	</div>
	<h5>940 nm IR LED</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "ir940_pin" "GPIO pin" %></div>
		<div class="col"><% field_number "ir940_pwn" "PWM channel" %></div>
	</div>
	<h5>White Light</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "white_pin" "GPIO pin" %></div>
		<div class="col"><% field_number "white_pwn" "PWM channel" %></div>
	</div>
	<h5>IR CUT filter</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "ircut_pin1" "GPIO pin 1" %></div>
		<div class="col"><% field_number "ircut_pin2" "GPIO pin 2" %></div>
	</div>
</div>
<div class="col">
	<h5>Day/Night Switching</h5>
	<% field_switch "cron_enable" "Run by cron" %>
	<p class="string" id="cron_line_wrap">
		<label for="cron_line" class="form-label">cron line</label>
		<input type="text" id="cron_line" name="cron_line" class="form-control" value="<%= "$cron_line" %>">
        </p>

	<h6>Day/Night Trigger Threshold</h6>
	<div class="row mb-3">
		<div class="col"><% field_number "day_night_min" "Min. gain in night mode" %></div>
		<div class="col"><% field_number "day_night_max" "Max. gain in day mode" %></div>
	</div>
</div>
<div class="col">

<h3>Environment Settings</h3>
<pre>
gpio_ir850: <%= $ir850_pin %>
pwm_ch_ir850: <%= $ir850_pwm %>
gpio_ir940: <%= $ir940_pin %>
pwm_ch_ir940: <%= $ir940_pwm %>
gpio_white: <%= $white_pin %>
pwm_ch_white: <%= $white_pwm %>
gpio_ircut: <%= $ircut_pins %>
day_night_min: <%= $day_night_min %>
day_night_max: <%= $day_night_max %>
</pre>

<% ex "sed -n /daynight/p /etc/crontabs/root" %>
</div>
<div class="col">
<% button_webui_log %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
