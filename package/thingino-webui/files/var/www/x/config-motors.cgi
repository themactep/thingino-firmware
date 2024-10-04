#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motors"

[ -f /bin/motors ] || redirect_to "/" "danger" "Your camera does not seem to support motors"

# read data from env
# fw_printenv | grep -E '(motor|homing)' | xargs -i eval '{}'
disable_homing=$(get disable_homing)
gpio_motor_h=$(get gpio_motor_h)
gpio_motor_v=$(get gpio_motor_v)
motor_maxstep_h=$(get motor_maxstep_h)
motor_maxstep_v=$(get motor_maxstep_v)
motor_pos_0=$(get motor_pos_0)
motor_speed=$(get motor_speed)

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
[ -z "$disable_homing" ] && disable_homing=false

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
	motor_speed=$POST_motor_speed

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

		[ -z "$motor_speed" ] && motor_speed=900

		# save to env
		tmpfile=$(mktemp -u)
		{
			echo "gpio_motor_h $gpio_motor_h"
			echo "gpio_motor_v $gpio_motor_v"
			echo "motor_maxstep_h $motor_maxstep_h"
			echo "motor_maxstep_v $motor_maxstep_v"
			echo "disable_homing $disable_homing"
			echo "motor_pos_0 $motor_pos_0"
			echo "motor_speed $motor_speed"
		} > $tmpfile
		fw_setenv -s $tmpfile
		rm $tmpfile

		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h5>Pan Motor GPIO</h5>
<div class="row g-1">
<div class="col"><% field_number "gpio_motor_h_1" "pin 1" %></div>
<div class="col"><% field_number "gpio_motor_h_2" "pin 2" %></div>
<div class="col"><% field_number "gpio_motor_h_3" "pin 3" %></div>
<div class="col"><% field_number "gpio_motor_h_4" "pin 4" %></div>
</div>
<h5>Tilt Motor GPIO</h5>
<div class="row g-1">
<div class="col"><% field_number "gpio_motor_v_1" "pin 1" %></div>
<div class="col"><% field_number "gpio_motor_v_2" "pin 2" %></div>
<div class="col"><% field_number "gpio_motor_v_3" "pin 3" %></div>
<div class="col"><% field_number "gpio_motor_v_4" "pin 4" %></div>
</div>

</div>
<div class="col">

<h5>Motor max. steps</h5>
<div class="row g-1">
<div class="col"><% field_number "motor_maxstep_h" "Pan motor steps" %></div>
<div class="col"><% field_number "motor_maxstep_v" "Tilt motor steps" %></div>
<div class="col"><% field_number "motor_speed" "Max motor speed"%></div>
</div>

<h5>Homing<sup>*</sup> on boot</h5>
<p class="small">* camera rotates to its minimum limits to set zero positions on both axis on boot.</p>
<% field_switch "disable_homing" "Disable homing" %>

<h5>Starting position</h5>
<div class="row g-1">
<div class="col"><% field_number "motor_pos_0_x" "Pan position" %></div>
<div class="col"><% field_number "motor_pos_0_y" "Tilt position" %></div>
</div>
<a href="#" class="mb-4" id="read-motors">Pick up the recent position</a>

</div>
<div class="col">

<h3>Environment Settings</h3>
<pre>
gpio_motor_h: <%= $gpio_motor_h %>
gpio_motor_v: <%= $gpio_motor_v %>
motor_maxstep_h: <%= $motor_maxstep_h %>
motor_maxstep_v: <%= $motor_maxstep_v %>
disable_homing: <%= $disable_homing %>
motor_pos_0: <%= $motor_pos_0 %>
motor_speed: <%= $motor_speed %>
</pre>
</div>
</div>
<% button_submit %>
</form>

<script>
function checkHoming() {
	const state = $('#disable_homing').checked;
	$('#motor_pos_0_x').disabled = state;
	$('#motor_pos_0_y').disabled = state;
}

function readMotors() {
	fetch("/x/json-motor.cgi?d=j")
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

$('#disable_homing').onchange = () => { checkHoming() }

checkHoming();
</script>

<%in _footer.cgi %>
