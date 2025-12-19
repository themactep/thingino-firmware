#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motors"

[ -f /bin/motors ] || redirect_to "/" "danger" "Your camera does not seem to support motors"

domain="motors"
config_file="/etc/motors.json"
temp_config_file="/tmp/$domain.json"

defaults() {
	default_for homing "true"
	default_for gpio_invert "false"
	default_for gpio_switch "false"
	default_for speed_pan "900"
	default_for speed_tilt "900"
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

	gpio_pan=$(get_value gpio_pan)
	gpio_tilt=$(get_value gpio_tilt)
	gpio_switch=$(get_value gpio_switch)
	gpio_invert=$(get_value gpio_invert)
	steps_pan=$(get_value steps_pan)
	steps_tilt=$(get_value steps_tilt)
	speed_pan=$(get_value speed_pan)
	speed_tilt=$(get_value speed_tilt)
	homing=$(get_value homing)
	pos_0=$(get_value pos_0)
	is_spi=$(get_value is_spi)
}

read_config

# normalize
gpio_pan_1=$(echo $gpio_motor_h | awk '{print $1}')
gpio_pan_2=$(echo $gpio_motor_h | awk '{print $2}')
gpio_pan_3=$(echo $gpio_motor_h | awk '{print $3}')
gpio_pan_4=$(echo $gpio_motor_h | awk '{print $4}')
gpio_tilt_1=$(echo $gpio_motor_v | awk '{print $1}')
gpio_tilt_2=$(echo $gpio_motor_v | awk '{print $2}')
gpio_tilt_3=$(echo $gpio_motor_v | awk '{print $3}')
gpio_tilt_4=$(echo $gpio_motor_v | awk '{print $4}')
pos_0_x=$(echo $pos_0 | awk -F',' '{print $1}')
pos_0_y=$(echo $pos_0 | awk -F',' '{print $2}')

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# Read data from the form
	gpio_pan_1=$POST_gpio_pan_1
	gpio_pan_2=$POST_gpio_pan_2
	gpio_pan_3=$POST_gpio_pan_3
	gpio_pan_4=$POST_gpio_pan_4
	gpio_tilt_1=$POST_gpio_tilt_1
	gpio_tilt_2=$POST_gpio_tilt_2
	gpio_tilt_3=$POST_gpio_tilt_3
	gpio_tilt_4=$POST_gpio_tilt_4
	homing=$POST_homing
	pos_0_x=$POST_pos_0_x
	pos_0_y=$POST_pos_0_y
	speed_pan=$POST_speed_pan
	speed_tilt=$POST_speed_tilt
	steps_pan=$POST_steps_pan
	steps_tilt=$POST_steps_tilt

	defaults

	# validate
	if [ "true" != "$is_spi" ]; then
		if [ -z "$gpio_pan_1" ] || [ -z "$gpio_pan_2" ] || [ -z "$gpio_pan_3" ] || [ -z "$gpio_pan_4" ] || \
		   [ -z "$gpio_tilt_1" ] || [ -z "$gpio_tilt_2" ] || [ -z "$gpio_tilt_3" ] || [ -z "$gpio_tilt_4" ]; then
			set_error_flag "All pins are required"
		fi
	fi

	if [ "0$steps_pan" -le 0 ] || [ "0$steps_tilt" -le 0 ]; then
		set_error_flag "Motor max steps aren't set"
	fi

	if [ -z "$error" ]; then
		# construct
		gpio_pan="$gpio_pan_1 $gpio_pan_2 $gpio_pan_3 $gpio_pan_4"
		gpio_tilt="$gpio_tilt_1 $gpio_tilt_2 $gpio_tilt_3 $gpio_tilt_4"

		if [ -n "$pos_0_x" ] && [ -n "$pos_0_y" ]; then
			pos_0="$pos_0_x,$pos_0_y"
		else
			pos_0=""
		fi

		tmpfile="$(mktemp -u).json"
		echo '{}' > $tmpfile
		set_value gpio_pan "$gpio_pan"
		set_value gpio_tilt "$gpio_tilt"
		set_value steps_pan "$steps_pan"
		set_value steps_tilt "$steps_tilt"
		set_value speed_pan "$speed_pan"
		set_value speed_tilt "$speed_tilt"
		set_value gpio_switch "$gpio_switch"
		set_value gpio_invert "$gpio_invert"
		set_value homing "$homing"
		set_value pos_0 "$pos_0"

		jct "$config_file" import "$temp_config_file"
		rm "$temp_config_file"

		redirect_to $SCRIPT_NAME "success" "Data updated."
	else
		redirect_to $SCRIPT_NAME "danger" "Error: $error"
	fi
fi

defaults
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">

<div class="col">
<h5>Pan motor</h5>
<% if [ "true" != "$is_spi" ]; then %>
<div class="row g-1">
<div class="col"><% field_number "gpio_pan_1" "GPIO pin 1" %></div>
<div class="col"><% field_number "gpio_pan_2" "GPIO pin 2" %></div>
<div class="col"><% field_number "gpio_pan_3" "GPIO pin 3" %></div>
<div class="col"><% field_number "gpio_pan_4" "GPIO pin 4" %></div>
<a href="#" class="mb-4 flip_motor" data-direction="pan">Flip direction</a>
</div>
<% fi %>
<div class="row g-1">
<div class="col"><% field_number "speed_pan" "Max. speed"%></div>
<div class="col"><% field_number "steps_pan" "Max. steps" %></div>
<div class="col"><% field_number_int "pos_0_x" "Position on boot" %></div>
<a href="#" class="mb-4 read-motors">Pick up the recent position</a>
</div>
</div>
<div class="col">
<h5>Tilt motor</h5>
<% if [ "true" != "$is_spi" ]; then %>
<div class="row g-1">
<div class="col"><% field_number "gpio_tilt_1" "GPIO pin 1" %></div>
<div class="col"><% field_number "gpio_tilt_2" "GPIO pin 2" %></div>
<div class="col"><% field_number "gpio_tilt_3" "GPIO pin 3" %></div>
<div class="col"><% field_number "gpio_tilt_4" "GPIO pin 4" %></div>
<a href="#" class="mb-4 flip_motor" data-direction="tilt">Flip direction</a>
</div>
<% fi %>
<div class="row g-1">
<div class="col"><% field_number "speed_tilt" "Max. speed"%></div>
<div class="col"><% field_number "steps_tilt" "Max. steps" %></div>
<div class="col"><% field_number_int "pos_0_y" "Position on boot" %></div>
<a href="#" class="mb-4 read-motors">Pick up the recent position</a>
</div>
</div>
<div class="col">
<h5>Homing</h5>
<p class="alert alert-info">During boot, the camera rotates to its minimum limits and zeroes both axes.
 If you want to use the camera permanently pointed at a scene, you can disable this behavior.</p>
<% field_switch "homing" "Homing on boot" %>
</div>
</div>

<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<script>
function checkHoming() {
	const state = $('#homing').checked;
	$('#pos_0_x').disabled = !state;
	$('#pos_0_y').disabled = !state;
}

async function readMotors() {
	await fetch('/x/json-motor.cgi?' + new URLSearchParams({ "d": "j" }).toString())
		.then(res => res.json())
		.then(({message:{xpos, ypos}}) => {
			$('#pos_0_x').value = xpos;
			$('#pos_0_y').value = ypos;
		});
	$('#homing').checked = true;
}

$$('.read-motors').forEach(el => {
	el.onclick = (ev) => {
		ev.preventDefault();
		readMotors();
	}
});

$$('.flip_motor').forEach(el => {
	el.onclick = (ev) => {
		let pins = [];
		const name = '#gpio_' + ev.target.dataset.direction;
		[1,2,3,4].forEach((i) => { pins.push($(name + '_' + i).value) });
		pins = pins.reverse();
		[1,2,3,4].forEach((i) => { $(name + '_' + i).value = pins[i - 1] });
	}
});

$('#homing').onchange = () => { checkHoming() }

checkHoming();
</script>

<%in _footer.cgi %>
