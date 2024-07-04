#!/usr/bin/haserl
<%in p/common.cgi %>
<%
page_title="Motors"

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""

	gpio_motor_h_1=$POST_gpio_motor_h_1
	gpio_motor_h_2=$POST_gpio_motor_h_2
	gpio_motor_h_3=$POST_gpio_motor_h_3
	gpio_motor_h_4=$POST_gpio_motor_h_4

	gpio_motor_v_1=$POST_gpio_motor_v_1
	gpio_motor_v_2=$POST_gpio_motor_v_2
	gpio_motor_v_3=$POST_gpio_motor_v_3
	gpio_motor_v_4=$POST_gpio_motor_v_4

	# values from the form
	gpio_motor_h="$POST_gpio_motor_h_1 $POST_gpio_motor_h_2 $POST_gpio_motor_h_3 $POST_gpio_motor_h_4"
	gpio_motor_v="$POST_gpio_motor_v_1 $POST_gpio_motor_v_2 $POST_gpio_motor_v_3 $POST_gpio_motor_v_4"
	motor_maxstep_h=$POST_motor_maxstep_h
	motor_maxstep_v=$POST_motor_maxstep_v
	disable_homing=$POST_disable_homing

	# default values
	[ -z "$disable_homing" ] && disable_homing=false

	# save values to env
	tmpfile=$(mktemp)
	echo "gpio_motor_h $gpio_motor_h" >> $tmpfile
	echo "gpio_motor_v $gpio_motor_v" >> $tmpfile
	echo "motor_maxstep_h $motor_maxstep_h" >> $tmpfile
	echo "motor_maxstep_v $motor_maxstep_v" >> $tmpfile
	echo "disable_homing $disable_homing" >> $tmpfile
	fw_setenv -s $tmpfile
	rm $tmpfile
fi

# read data from env
gpio_motor_h=$(get gpio_motor_h)
gpio_motor_v=$(get gpio_motor_v)
motor_maxstep_h=$(get motor_maxstep_h)
motor_maxstep_v=$(get motor_maxstep_v)
disable_homing=$(get disable_homing)

gpio_motor_h_1=$(echo $gpio_motor_h | awk '{print $1}')
gpio_motor_h_2=$(echo $gpio_motor_h | awk '{print $2}')
gpio_motor_h_3=$(echo $gpio_motor_h | awk '{print $3}')
gpio_motor_h_4=$(echo $gpio_motor_h | awk '{print $4}')

gpio_motor_v_1=$(echo $gpio_motor_v | awk '{print $1}')
gpio_motor_v_2=$(echo $gpio_motor_v | awk '{print $2}')
gpio_motor_v_3=$(echo $gpio_motor_v | awk '{print $3}')
gpio_motor_v_4=$(echo $gpio_motor_v | awk '{print $4}')

# default values
[ -z "$disable_homing" ] && disable_homing=false
%>
<%in p/header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col">
	<h5>Pan Motor GPIO</h5>
	<div class="row mb-4">
		<div class="col"><% field_number "gpio_motor_h_1" "pin 1" %></div>
		<div class="col"><% field_number "gpio_motor_h_2" "pin 2" %></div>
		<div class="col"><% field_number "gpio_motor_h_3" "pin 3" %></div>
		<div class="col"><% field_number "gpio_motor_h_4" "pin 4" %></div>
	</div>
	<h5>Tilt Motor GPIO</h5>
	<div class="row mb-4">
		<div class="col"><% field_number "gpio_motor_v_1" "pin 1"%></div>
		<div class="col"><% field_number "gpio_motor_v_2" "pin 2"%></div>
		<div class="col"><% field_number "gpio_motor_v_3" "pin 3"%></div>
		<div class="col"><% field_number "gpio_motor_v_4" "pin 4"%></div>
	</div>
</div>
<div class="col">
	<h5>Motor max. steps</h5>
	<div class="row mb-4">
		<div class="col"><% field_number "motor_maxstep_h" "Pan motor steps" %></div>
		<div class="col"><% field_number "motor_maxstep_v" "Tilt motor steps" %></div>
	</div>
	<h5>Homing<sup>*</sup> on boot</h5>
	<p class="small">* camera rotates to its minimum limits to set zero positions on both axis on boot.</p>
	<% field_switch "disable_homing" "Disable homing" %>
</div>
<div class="col">

<h3>Environment Settings</h3>
<pre>
gpio_motor_h: <%= $gpio_motor_h %>
gpio_motor_v: <%= $gpio_motor_v %>
motor_maxstep_v: <%= $motor_maxstep_v %>
motor_maxstep_v: <%= $motor_maxstep_h %>
disable_homing: <%= $disable_homing %>
</pre>
</div>
<div class="col">
<% button_webui_log %>
</div>
</div>
<% button_submit %>
</form>

<%in p/footer.cgi %>
