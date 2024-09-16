#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Illumination Controls"

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
	day_night_max=${POST_day_night_max:-15000}
	day_night_min=${POST_day_night_min:-5000}

	# save values to env
	tmpfile=$(mktemp -u)
	{
		echo "gpio_ir850 $ir850_pin"
		echo "gpio_ir940 $ir940_pin"
		echo "gpio_white $white_pin"
		echo "gpio_ircut $ircut_pin1 $ircut_pin2"
		echo "pwm_ch_ir850 $ir850_pwm"
		echo "pwm_ch_ir940 $ir940_pwm"
		echo "pwm_ch_white $white_pwm"
		echo "day_night_min $day_night_min"
		echo "day_night_max $day_night_max"
	} > $tmpfile
	fw_setenv -s $tmpfile
	rm $tmpfile
fi

# read data from env
#fw_printenv | grep -E '(gpio_(ir|white)|pwm_ch_ir|day_night)' | xargs -i eval '{}'

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

# default values
[ -z "$day_night_min" ] && day_night_min=5000
[ -z "$day_night_max" ] && day_night_max=15000

%>
<%in _header.cgi %>

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
</div>
<div class="col">
	<h5>IR CUT filter</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "ircut_pin1" "GPIO pin 1" %></div>
		<div class="col"><% field_number "ircut_pin2" "GPIO pin 2" %></div>
	</div>

	<h5>Day/Night Trigger Threshold</h5>
	<div class="row mb-3">
		<div class="col"><% field_number "day_night_min" "Min. gain in night mode" %></div>
		<div class="col"><% field_number "day_night_max" "Max. gain in day mode" %></div>
	</div>
</div>
<div class="col">
<h3>Environment Settings</h3>
<% ex "fw_printenv | grep -E '((gpio|pwm_ch)_(ir|white)|day_night)'" %>
</div>
</div>
<% button_submit %>
</form>

<%in _footer.cgi %>
