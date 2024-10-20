#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Illumination Controls"

field_gpio() {
	local is_active
	local is_active_low
	local is_disabled
	local lit_on_boot
	local pin_off
	local pin_on

	local name=$1

	local var_pin="${name}_pin"
	eval pin=\$$var_pin

	local var_pwm="${name}_pwm"
	eval pwm=\$$var_pwm

	if [ -z "$pin" ]; then
		is_disabled=" disabled"
	else
		[ "$pin" = "${pin//[^0-9]/}" ] && pin="${pin}O"
		active_suffix=${pin:0-1}
		case "$active_suffix" in
			o) pin_on=0; pin_off=1; is_active_low=" checked" ;;
			O) pin_on=1; pin_off=0 ;;
		esac
		pin=${pin:0:-1}

		pin_status=$(gpio read $pin | awk '{print $3}')
		[ "$pin_status" -eq "$pin_on" ] && is_active=" checked"

		echo $DEFAULT_PINS | grep -E "\b$pin$active_suffix\b" > /dev/null && lit_on_boot=" checked"
	fi

	echo "<div class=\"mb-3 led led-$1\"><label class=\"form-label\" for=\"$name\">$2</label><div class=\"input-group\">
<div class=\"input-group-text switch\"><input type=\"checkbox\" class=\"form-check-input mt-0 led-status\" id=\"${name}_on\" name=\"${name}_on\" data-color=\"$name\" value=\"true\"$is_active$is_disabled></div>
<input type=\"text\" class=\"form-control text-end\" id=\"${name}_pin\" name=\"${name}_pin\" data-color=\"$1\" pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pin\" placeholder=\"GPIO\">
<input type=\"text\" class=\"form-control text-end\" id=\"${name}_pwm\" name=\"${name}_pwm\" data-color=\"$1\" pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pwm\" placeholder=\"PWM channel\">
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_inv\" value=\"true\"$is_active_low$is_disabled> active low</div>
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_lit\" value=\"true\"$lit_on_boot$is_disabled> lit on boot</div>
</div></div>"
}

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

	redirect_to $SCRIPT_NAME
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

<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
<div class="col">
<h5 class="mb-3">GPIO control pins</h5>
<%
field_gpio "ir850" "850 nm IR LED"
field_gpio "ir940" "940 nm IR LED"
field_gpio "white" "White LED"
%>
<div class="mb-3 led ircut">
<label class="form-label" for="ircut">IR cut filter</label>
<div class="input-group">
<div class="input-group-text">GPIO pin 1</div>
<input type="text" class="form-control text-end" id="ircut_pin1" name="ircut_pin1" pattern="[0-9]{1,3}" title="empty or a number" value="<%= $ircut_pin1 %>" placeholder="GPIO">
<div class="input-group-text">GPIO pin 2</div>
<input type="text" class="form-control text-end" id="ircut_pin2" name="ircut_pin2" pattern="[0-9]{1,3}" title="empty or a number" value="<%= $ircut_pin2 %>" placeholder="GPIO">
</div>
<p class="hint text-secondary">IR cut filters are typically controlled by a pair of GPIO pins that define the polarity and thus the direction of the filter's movement.</p>
</div>
</div>
<div class="col">
<h5 class="mb-3">Day/Night trigger thresholds</h5>
<p class="hint text-secondary">The day/night mode is controlled by the brightness of the scene.
Changes in illumination affect the gain required to normalise a darkened image - the darker the scene,
the higher the gain value. Switching between modes is triggered by changes in gain beyond the thresholds set below.</p>
<div class="row my-3">
<div class="text-end"><label for="day_night_min">Minimum gain in night mode</label></div>
<div class="col-3"><input type="text" id="day_night_min" name="day_night_min" class="form-control text-end" value="<%= $day_night_min %>" pattern="[0-9]{1,}" title="numeric value" data-min="0" data-max="150000" data-step="1"></div>
<div class="col-9"><span class="arrow arrow-1"></span></div>
</div>
<div class="row my-3">
<label for="day_night_max">Maximum gain in day mode</label>
<div class="col-9"><span class="arrow arrow-2"></span></div>
<div class="col-3"><input type="text" id="day_night_max" name="day_night_max" class="form-control text-end" value="<%= $day_night_max %>" pattern="[0-9]{1,}" title="numeric value" data-min="0" data-max="150000" data-step="1"></div>
</div>
<p class="hint text-secondary">The current gain value is displayed at the top of each page next to the sun emoji.</p>
</div>
<div class="col">
<h3>Environment settings</h3>
<% ex "fw_printenv | grep -E '((gpio|pwm_ch)_(ir|white)|day_night)'" %>
</div>
</div>
<% button_submit %>
</form>

<script>
async function switchIndicator(color, state) {
	await fetch(`/x/json-imp.cgi?cmd=${color}&val=${state}`)
		.then(res => res.json())
		.then(data => { $(`#${color}_on`).checked = (data.message.result == 1) });
}

["ir850", "ir940", "white"].forEach(n => {
	switchIndicator(n, '');
	$(`#${n}_on`).onchange = (ev) => switchIndicator(n, ev.target.checked ? '1' : '0');
});
</script>

<style>
.led-ir850 .input-group-text:first-child { background-color: #a60000; }
.led-ir940 .input-group-text:first-child { background-color: #750000; }
.led-white .input-group-text:first-child { background-color: #eeeeee; }
.arrow-1, .arrow-2 { width: 100%; height: 30px; display: flex; }
.arrow-1 { rotate: 180deg; }
.arrow:before { background: var(--bs-secondary-bg); content: ""; width: 15px; clip-path: polygon(0 10px, calc(100% - 15px) 10px, calc(100% - 15px) 0, 100% 50%, calc(100% - 15px) 100%, calc(100% - 15px) calc(100% - 10px), 0 calc(100% - 10px)); animation: a1 3s normal forwards ease-in-out; }
@keyframes a1 { 90%, 100% {flex-grow: 1} }
</style>

<%in _footer.cgi %>
