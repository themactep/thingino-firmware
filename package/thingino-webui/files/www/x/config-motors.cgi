#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motors"

[ -f /bin/motors ] || redirect_to "/" "danger" "Your camera does not seem to support motors"

defaults() {
	default_for homing "true"
	default_for gpio_invert "false"
	default_for gpio_switch "false"
	default_for speed_pan "900"
	default_for speed_tilt "900"
}

read_config() {
	local CONFIG_FILE=/etc/motors.json
	[ -f "$CONFIG_FILE" ] || return

	   gpio_pan=$(jct $CONFIG_FILE get motors.gpio_pan)
	  gpio_tilt=$(jct $CONFIG_FILE get motors.gpio_tilt)
	gpio_switch=$(jct $CONFIG_FILE get motors.gpio_switch)
	gpio_invert=$(jct $CONFIG_FILE get motors.gpio_invert)
	  steps_pan=$(jct $CONFIG_FILE get motors.steps_pan)
	 steps_tilt=$(jct $CONFIG_FILE get motors.steps_tilt)
	  speed_pan=$(jct $CONFIG_FILE get motors.speed_pan)
	 speed_tilt=$(jct $CONFIG_FILE get motors.speed_tilt)
	     homing=$(jct $CONFIG_FILE get motors.homing)
	      pos_0=$(jct $CONFIG_FILE get motors.pos_0)
	      is_spi=$(jct $CONFIG_FILE get motors.is_spi)
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
		jct $tmpfile set motors.gpio_pan "$gpio_pan"
		jct $tmpfile set motors.gpio_tilt "$gpio_tilt"
		jct $tmpfile set motors.steps_pan "$steps_pan"
		jct $tmpfile set motors.steps_tilt "$steps_tilt"
		jct $tmpfile set motors.speed_pan "$speed_pan"
		jct $tmpfile set motors.speed_tilt "$speed_tilt"
		jct $tmpfile set motors.gpio_switch "$gpio_switch"
		jct $tmpfile set motors.gpio_invert "$gpio_invert"
		jct $tmpfile set motors.homing "$homing"
		jct $tmpfile set motors.pos_0 "$pos_0"
		jct /etc/motors.json import $tmpfile
		rm $tmpfile

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
<% ex "jct /etc/motors.json print" %>
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
