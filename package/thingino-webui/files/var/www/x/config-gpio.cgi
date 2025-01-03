#!/bin/haserl
<%in _common.cgi %>
<%
page_title="LED/IRcut GPIO"

COLORS="r b g y o w"

read_from_env "gpio"
read_from_env "pwm"

DEFAULT_PINS="$gpio_default"

update_config() {
	local name=gpio_led_$1

	eval local pin=\$POST_${name}_pin
	if [ -n "$pin" ]; then
		eval local pin_inv=\$POST_${name}_inv
		eval local pin_lit=\$POST_${name}_lit

		local active_suffix
		if [ "true" = "$pin_inv" ]; then
			active_suffix="o"
		else
			active_suffix="O"
		fi
		payload=$(echo -e "$payload\n$name $pin$active_suffix")

		# remove the pin from defaults
		DEFAULT_PINS=$(echo $DEFAULT_PINS | sed -E "s/\b($pin[oO])\b//")

		# add it as needed
		if [ "true" = "$pin_lit" ]; then
			DEFAULT_PINS="$DEFAULT_PINS $pin$active_suffix"
		fi
	fi

#	# read the existing pin for the color from environment and remove it from defaults
#	pin=$(fw_printenv -n $name)
#	[ -n "$pin" ] && DEFAULT_PINS=$(echo $DEFAULT_PINS | sed -E "s/\b($pin[oO])\b/ /")
#	# drop individual environment settings for the color
#	payload=$(echo -e "$payload\n$name")

	# sqeeze spacing
	DEFAULT_PINS=$(echo $DEFAULT_PINS | tr -s " ")
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	read_from_post "gpio" "ir850_pin ir850_inv ir850_lit ir940_pin ir940_inv ir940_lit white_pin white_inv white_lit ircut_pin1 ircut_pin2"

	payload="
#POST_gpio_led_r_pin    $POST_gpio_led_r_pin
#POST_gpio_led_r_inv    $POST_gpio_led_r_inv
#POST_gpio_led_r_lit    $POST_gpio_led_b_lit

#POST_gpio_led_b_pin    $POST_gpio_led_b_pin
#POST_gpio_led_b_inv    $POST_gpio_led_b_inv
#POST_gpio_led_b_lit    $POST_gpio_led_b_lit

#POST_gpio_ir850_pin    $POST_gpio_ir850_pin
#POST_gpio_ir850_ch     $POST_gpio_ir850_ch
#POST_gpio_ir850_lvl    $POST_gpio_ir850_lvl

#POST_gpio_ir940_pin    $POST_gpio_ir940_pin
#POST_gpio_ir940_ch     $POST_gpio_ir940_ch
#POST_gpio_ir940_lvl    $POST_gpio_ir940_lvl

#POST_gpio_white_pin    $POST_gpio_white_pin
#POST_gpio_white_ch     $POST_gpio_white_ch
#POST_gpio_white_lvl    $POST_gpio_white_lvl

#POST_gpio_ircut_pin1   $POST_gpio_ircut_pin1
#POST_gpio_ircut_pin2   $POST_gpio_ircut_pin2
#-------------------------------------------

gpio_ir850    $gpio_ir850_pin
pwm_ch_ir850  $gpio_ir850_pwm_ch
pwm_lvl_ir850 $gpio_ir850_pwm_lvl
gpio_ir940    $gpio_ir940_pin
pwm_ch_ir940  $gpio_ir940_pwm
pwm_lvl_ir940 $gpio_ir850_pwm_lvl
gpio_white    $gpio_white_pin
pwm_ch_white  $gpio_white_pwm
pwm_lvl_ir940 $gpio_ir850_pwm_lvl
gpio_ircut    $gpio_ircut_pin1 $gpio_ircut_pin2
"

	for c in $COLORS; do
		update_config "$c"
	done

	payload=$(echo -e "$payload\ngpio_default  $DEFAULT_PINS")
#	echo "$payload"

	save2env "$payload"

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

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-sm-2 row-cols-xl-4 g-2">
<% field_gpio "gpio_led_r" "Red LED" %>
<% field_gpio "gpio_led_g" "Green LED" %>
<% field_gpio "gpio_led_b" "Blue LED" %>
<% field_gpio "gpio_led_y" "Yellow LED" %>
<% field_gpio "gpio_led_o" "Orange LED" %>
<% field_gpio "gpio_led_w" "White LED" %>
<% field_gpio "gpio_ir850" "850 nm IR LED" %>
<% field_gpio "gpio_ir940" "940 nm IR LED" %>
<% field_gpio "gpio_white" "White LED" %>

<div class="col">
<div class="card h-100">
<div class="card-header">
IR cut filter
<div class="switch float-end"><img src="/a/help.svg" alt="Help" class="img-fluid" type="button"
 data-bs-toggle="modal" data-bs-target="#helpModal" style="max-height:1.5rem"></div>
</div>
<div class="card-body">
<div class="row mb-2">
<label class="form-label col-9" for="gpio_ircut_pin1">GPIO pin 1 #</label>
<div class="col">
<input type="text" class="form-control text-end" id="gpio_ircut_pin1" name="gpio_ircut_pin1" pattern="[0-9]{1,3}"
 title="empty or a number" value="<%= $gpio_ircut_pin1 %>" placeholder="GPIO">
</div>
</div>
<div class="row mb-2">
<label class="form-label col-9" for="gpio_ircut_pin2">GPIO pin 2 #</label>
<div class="col">
<input type="text" class="form-control text-end" id="gpio_ircut_pin2" name="gpio_ircut_pin2" pattern="[0-9]{1,3}"
 title="empty or a number" value="<%= $gpio_ircut_pin2 %>" placeholder="GPIO">
</div>
</div>
</div>
</div>
</div>

</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep -E ^\(gpio\|pwm_ch\)_" %>
<% ex "pwm-ctrl -l | grep ^GPIO" %>
</div>

<div class="modal fade" id="helpModal" tabindex="-1">
<div class="modal-dialog">
<div class="modal-content">
<div class="modal-header">
<h5 class="modal-title">IR cut GPIO</h5>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body">
<p>The IR cut filter is typically controlled by a combination of two GPIO pins that define the voltage polarity and direction of movement.</p>
<% wiki_page "Configuration:-Night-Mode#infrared-cut-filter" %>
</div>
<div class="modal-footer">
<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
</div>
</div>
</div>
</div>

<script>
['gpio_led_r', 'gpio_led_g', 'gpio_led_b',
 'gpio_led_y', 'gpio_led_o', 'gpio_led_w',
 'gpio_ir850', 'gpio_ir940', 'gpio_white'].forEach(n => {
	$('#' + n + '_toggle')?.addEventListener('click', ev => {
		fetch('/x/json-gpio.cgi?' + new URLSearchParams({'n': n, 's': '~'}).toString())
			.then(res => res.json())
			.then(data => console.log(data.message));
	});
});
</script>

<%in _footer.cgi %>
