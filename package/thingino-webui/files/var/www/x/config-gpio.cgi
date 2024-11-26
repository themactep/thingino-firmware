#!/bin/haserl
<%in _common.cgi %>
<%
page_title="LED/IRcut GPIO"

COLORS="r b g y o w"

read_from_env "gpio"
read_from_env "pwm_ch"

DEFAULT_PINS="$gpio_default"

update_config() {
	local pin
	local pin_inv
	local pin_lit
	local active_suffix
	local name=gpio_led_$1
	eval pin=\$POST_${name}
	if [ -n "$pin" ]; then
		eval pin_inv=\$POST_${name}_inv
		eval pin_lit=\$POST_${name}_lit
		if [ "true" = "$pin_inv" ]; then
			active_suffix="o"
		else
			active_suffix="O"
		fi
		echo "$name $pin$active_suffix" >> $tmpfile
		# remove the pin from defaults
		DEFAULT_PINS=$(echo $DEFAULT_PINS | sed -E "s/\b($pin[oO])\b//")
		if [ "true" != "$pin_lit" ]; then
			case "$active_suffix" in
			 	o) active_suffix="O" ;;
				O) active_suffix="o" ;;
			esac
		fi
		DEFAULT_PINS="$DEFAULT_PINS $pin$active_suffix"
	else
		# read the existing pin for the color from environment and remove it from defaults
		pin=$(fw_printenv -n $name)
		[ -n "$pin" ] && DEFAULT_PINS=$(echo $DEFAULT_PINS | sed -E "s/\b($pin[oO])\b/ /")
		# drop individual environment settings for the color
		echo "$name" >> $tmpfile
	fi
	# sqeeze spacing
	DEFAULT_PINS=$(echo $DEFAULT_PINS | tr -s " ")
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "gpio" "ir850_pin ir850_pwm ir940_pin ir940_pwm white_pin white_pwm ircut_pin1 ircut_pin2"

	for c in $COLORS; do
		update_config "$c"
	done

	save2env "gpio_ir850 $gpio_ir850_pin\n" \
		"gpio_ir940 $gpio_ir940_pin\n" \
		"gpio_white $gpio_white_pin\n" \
		"gpio_ircut $gpio_ircut_pin1 $gpio_ircut_pin2\n" \
		"pwm_ch_ir850 $gpio_ir850_pwm\n" \
		"pwm_ch_ir940 $gpio_ir940_pwm\n" \
		"pwm_ch_white $gpio_white_pwm\n" \
		"gpio_default $DEFAULT_PINS"

	redirect_back "success" "Data updated"
fi

# split pin data to pin number and active status
gpio_led_r_pin="$gpio_led_r"
gpio_led_g_pin="$gpio_led_g"
gpio_led_b_pin="$gpio_led_b"
gpio_led_y_pin="$gpio_led_y"
gpio_led_o_pin="$gpio_led_o"
gpio_led_w_pin="$gpio_led_w"
gpio_ir850_pin="$gpio_ir850"
gpio_ir940_pin="$gpio_ir940"
gpio_white_pin="$gpio_white"

gpio_ir940_pwm="$pwm_ch_ir940"
gpio_ir850_pwm="$pwm_ch_ir850"
gpio_white_pwm="$pwm_ch_white"

gpio_ircut_pin1="$(echo "$gpio_ircut" | awk '{print $1}')"
gpio_ircut_pin2="$(echo "$gpio_ircut" | awk '{print $2}')"
%>
<%in _header.cgi %>

<h5 class="mb-3">GPIO control pins</h5>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-lg-2 row-cols-xxl-3">
<div class="col">
<% field_gpio "gpio_led_r" "Red LED" %>
<% field_gpio "gpio_led_g" "Green LED" %>
<% field_gpio "gpio_led_b" "Blue LED" %>
<% field_gpio "gpio_led_y" "Yellow LED" %>
<% field_gpio "gpio_led_o" "Orange LED" %>
<% field_gpio "gpio_led_w" "White LED" %>
</div>
<div class="col">
<% field_gpio "gpio_ir850" "850 nm IR LED" %>
<% field_gpio "gpio_ir940" "940 nm IR LED" %>
<% field_gpio "gpio_white" "White LED" %>
</div>
<div class="col">
<div class="gpio ircut mb-3">
<label class="form-label" for="gpio_ircut_pin1">IR cut filter</label>
<div class="input-group">
<span class="input-group-text">Pin 1</span>
<input type="text" class="form-control text-end" id="gpio_ircut_pin1" name="gpio_ircut_pin1" pattern="[0-9]{1,3}" title="empty or a number" value="<%= $gpio_ircut_pin1 %>" placeholder="GPIO">
<span class="input-group-text">Pin 2</span>
<input type="text" class="form-control text-end" id="gpio_ircut_pin2" name="gpio_ircut_pin2" pattern="[0-9]{1,3}" title="empty or a number" value="<%= $gpio_ircut_pin2 %>" placeholder="GPIO">
</div>
</div>
<div class="alert alert-info">
<p>IR cut filter is typically controlled by a pair of GPIO pins combination of which defines the voltage polarity and the direction of the movement.</p>
<% wiki_page "Configration:-Night-Mode#infrared-cut-filter" %>
</div>
</div>
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep -E ^\(gpio\|pwm_ch\)_" %>
</div>

<script>
async function setGpio(n, s) {
	if ($('#' + n + '_inv').checked) { s = (s == 1) ? 0 : 1 }
	await fetch('/x/json-gpio.cgi?' + new URLSearchParams({'n': n, 's': s}).toString())
		.then(res => res.json())
		.then(data => {
			console.log(data.message)
			s = data.message.status == '1' ? true : false
			if ($('#' + n + '_inv').checked) s = !s
			$('#' + n + '_on').checked = s
		});
}

['gpio_led_r', 'gpio_led_g', 'gpio_led_b', 'gpio_led_y', 'gpio_led_o', 'gpio_led_w', 'gpio_ir850', 'gpio_ir940', 'gpio_white'].forEach(n => {
	if ($('#' + n + '_pin')) {
		$('#' + n + '_on').addEventListener('change', ev => {
			setGpio(n, ev.target.checked ? 1 : 0)
		});
	}
});
</script>

<%in _footer.cgi %>
