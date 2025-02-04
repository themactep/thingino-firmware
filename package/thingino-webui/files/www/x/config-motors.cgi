#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motors"

[ -f /bin/motors ] || redirect_to "/" "danger" "Your camera does not seem to support motors"

# read data from env
# fw_printenv | grep -E '(motor|homing)' | xargs -i eval '{}'
gpio_motor_h=$(fw_printenv -n gpio_motor_h)
gpio_motor_v=$(fw_printenv -n gpio_motor_v)
motor_maxstep_h=$(fw_printenv -n motor_maxstep_h)
motor_maxstep_v=$(fw_printenv -n motor_maxstep_v)
motor_speed_h=$(fw_printenv -n motor_speed_h)
motor_speed_v=$(fw_printenv -n motor_speed_v)
motor_pos_0=$(fw_printenv -n motor_pos_0)
disable_homing=$(fw_printenv -n disable_homing)

# FIXME: deprecate after splitting to per-motor
motor_speed=$(fw_printenv -n motor_speed)
default_for motor_speed_h $motor_speed
default_for motor_speed_v $motor_speed

# parse
gpio_motor_h_1=$(echo $gpio_motor_h | awk '{print $1}')
gpio_motor_h_2=$(echo $gpio_motor_h | awk '{print $2}')
gpio_motor_h_3=$(echo $gpio_motor_h | awk '{print $3}')
gpio_motor_h_4=$(echo $gpio_motor_h | awk '{print $4}')
gpio_motor_v_1=$(echo $gpio_motor_v | awk '{print $1}')
gpio_motor_v_2=$(echo $gpio_motor_v | awk '{print $2}')
gpio_motor_v_3=$(echo $gpio_motor_v | awk '{print $3}')
gpio_motor_v_4=$(echo $gpio_motor_v | awk '{print $4}')
motor_pos_0_x=$(echo $motor_pos_0 | awk -F',' '{print $1}')
motor_pos_0_y=$(echo $motor_pos_0 | awk -F',' '{print $2}')

# normalize
default_for disable_homing "false"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	# Read data from the form
	gpio_motor_h_1=$POST_gpio_motor_h_1
	gpio_motor_h_2=$POST_gpio_motor_h_2
	gpio_motor_h_3=$POST_gpio_motor_h_3
	gpio_motor_h_4=$POST_gpio_motor_h_4
	gpio_motor_v_1=$POST_gpio_motor_v_1
	gpio_motor_v_2=$POST_gpio_motor_v_2
	gpio_motor_v_3=$POST_gpio_motor_v_3
	gpio_motor_v_4=$POST_gpio_motor_v_4
	motor_maxstep_h=$POST_motor_maxstep_h
	motor_maxstep_v=$POST_motor_maxstep_v
	disable_homing=$POST_disable_homing
	motor_pos_0_x=$POST_motor_pos_0_x
	motor_pos_0_y=$POST_motor_pos_0_y
	motor_speed_h=$POST_motor_speed_h
	motor_speed_v=$POST_motor_speed_v

	# validate
	if [ -z "$gpio_motor_h_1" ] || [ -z "$gpio_motor_h_2" ] || \
	   [ -z "$gpio_motor_h_3" ] || [ -z "$gpio_motor_h_4" ] || \
	   [ -z "$gpio_motor_v_1" ] || [ -z "$gpio_motor_v_2" ] || \
	   [ -z "$gpio_motor_v_3" ] || [ -z "$gpio_motor_v_4" ]; then
		set_error_flag "All pins are required"
	fi

	if [ "0$motor_maxstep_h" -le 0 ] || \
	   [ "0$motor_maxstep_v" -le 0 ]; then
		set_error_flag "Motor max steps aren't set"
	fi

	if [ -z "$error" ]; then
		# construct
		gpio_motor_h="$POST_gpio_motor_h_1 $POST_gpio_motor_h_2 $POST_gpio_motor_h_3 $POST_gpio_motor_h_4"
		gpio_motor_v="$POST_gpio_motor_v_1 $POST_gpio_motor_v_2 $POST_gpio_motor_v_3 $POST_gpio_motor_v_4"

		if [ -n "$motor_pos_0_x" ] && [ -n "$motor_pos_0_y" ]; then
			motor_pos_0="$motor_pos_0_x,$motor_pos_0_y"
		else
			motor_pos_0=""
		fi

		[ -z "$motor_speed_h" ] && motor_speed_h=900
		[ -z "$motor_speed_v" ] && motor_speed_v=900

		# FIXME: deprecate after splitting to per-motor
		[ -z "$motor_speed" ] && motor_speed=$motor_speed_h

		# save to env
		tmpfile=$(mktemp -u)
		{
			echo "gpio_motor_h $gpio_motor_h"
			echo "gpio_motor_v $gpio_motor_v"
			echo "motor_maxstep_h $motor_maxstep_h"
			echo "motor_maxstep_v $motor_maxstep_v"
			echo "motor_speed_h $motor_speed_h"
			echo "motor_speed_v $motor_speed_v"
			echo "disable_homing $disable_homing"
			echo "motor_pos_0 $motor_pos_0"
			# FIXME: deprecate after splitting to per-motor
			echo "motor_speed $motor_speed"
		} > $tmpfile
		fw_setenv -s $tmpfile
		rm $tmpfile

		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<h5>Pan motor</h5>
<div class="row g-1">
<div class="col"><% field_number "gpio_motor_h_1" "GPIO pin 1" %></div>
<div class="col"><% field_number "gpio_motor_h_2" "GPIO pin 2" %></div>
<div class="col"><% field_number "gpio_motor_h_3" "GPIO pin 3" %></div>
<div class="col"><% field_number "gpio_motor_h_4" "GPIO pin 4" %></div>
<a href="#" class="mb-4 flip_motor" data-direction="h">Flip direction</a>
</div>
<div class="row g-1">
<div class="col"><% field_number "motor_speed_h" "Max. speed"%></div>
<div class="col"><% field_number "motor_maxstep_h" "Max. steps" %></div>
<div class="col"><% field_number "motor_pos_0_x" "Position on boot" %></div>
<a href="#" class="mb-4" id="read-motors">Pick up the recent position</a>
</div>
</div>
<div class="col">
<h5>Tilt motor</h5>
<div class="row g-1">
<div class="col"><% field_number "gpio_motor_v_1" "GPIO pin 1" %></div>
<div class="col"><% field_number "gpio_motor_v_2" "GPIO pin 2" %></div>
<div class="col"><% field_number "gpio_motor_v_3" "GPIO pin 3" %></div>
<div class="col"><% field_number "gpio_motor_v_4" "GPIO pin 4" %></div>
<a href="#" class="mb-4 flip_motor" data-direction="v">Flip direction</a>
</div>
<div class="row g-1">
<div class="col"><% field_number "motor_speed_v" "Max. speed"%></div>
<div class="col"><% field_number "motor_maxstep_v" "Max. steps" %></div>
<div class="col"><% field_number "motor_pos_0_y" "Position on boot" %></div>
<a href="#" class="mb-4" id="read-motors">Pick up the recent position</a>
</div>
</div>
<div class="col">
<h5>Homing</h5>
<p class="alert alert-info">During boot, the camera rotates to its minimum limits and zeroes both axes.
 If you want to use the camera permanently pointed at a scene, you can disable this behavior.</p>
<% field_switch "disable_homing" "Disable homing on boot" %>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<pre>
gpio_motor_h: <%= $gpio_motor_h %>
motor_maxstep_h: <%= $motor_maxstep_h %>
motor_speed_h: <%= $motor_speed_h %>
gpio_motor_v: <%= $gpio_motor_v %>
motor_maxstep_v: <%= $motor_maxstep_v %>
motor_speed_v: <%= $motor_speed_v %>
motor_pos_0: <%= $motor_pos_0 %>
disable_homing: <%= $disable_homing %>
</pre>
</div>

<script>
function checkHoming() {
	const state = $('#disable_homing').checked;
	$('#motor_pos_0_x').disabled = state;
	$('#motor_pos_0_y').disabled = state;
}

async function readMotors() {
	await fetch('/x/json-motor.cgi?' + new URLSearchParams({ "d": "j" }).toString())
		.then(res => res.json())
		.then(({message:{xpos, ypos}}) => {
			$('#motor_pos_0_x').value = xpos;
			$('#motor_pos_0_y').value = ypos;
		});
	$('#disable_homing').checked = false;
}

$('#read-motors').onclick = (ev) => {
	ev.preventDefault();
	readMotors();
}

$$('.flip_motor').forEach(el => {
	el.onclick = (ev) => {
		let pins = [];
		const name = `#gpio_motor_${ev.target.dataset.direction}`;
		[1,2,3,4].forEach((i) => { pins.push($(`${name}_${i}`).value) });
		pins = pins.reverse();
		[1,2,3,4].forEach((i) => { $(`${name}_${i}`).value = pins[i - 1] });
	}
});

$('#disable_homing').onchange = () => { checkHoming() }

checkHoming();
</script>

<%in _footer.cgi %>
