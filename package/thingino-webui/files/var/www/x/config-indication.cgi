#!/bin/haserl
<%in _common.cgi %>
<%
page_title="LED Indicators"

COLORS="r b g y o w"
DEFAULT_PINS=$(fw_printenv -n gpio_default)

read_data_from_env() {
	# fast evaluate with source
	local tmpfile=$(mktemp)
	fw_printenv | grep gpio_led_ > $tmpfile
	. $tmpfile
	rm $tmpfile
}

field_gpio() {
	local active_suffix
	local is_active
	local is_active_low
	local is_disabled
	local lit_on_boot
	local pin_off
	local pin_on

	local name=gpio_led_$1

	local var_pin="$name"
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

		pin_status=$(gpio read $pin)
		[ "$pin_status" -eq "$pin_on" ] && is_active=" checked"

		echo $DEFAULT_PINS | grep -E "\b$pin$active_suffix\b" > /dev/null && lit_on_boot=" checked"
	fi

	echo "<div class=\"mb-3 led led-$1\"><label class=\"form-label\" for=\"$name\">$2</label><div class=\"input-group\">
<div class=\"input-group-text switch\" style=\"background-color:$2\"><input type=\"checkbox\" class=\"form-check-input mt-0 led-status\" id=\"${name}_on\" name=\"${name}_on\" data-color=\"$1\" value=\"true\"$is_active$is_disabled></div>
<input type=\"text\" class=\"form-control text-end\" id=\"$name\" name=\"$name\" data-color=\"$1\" pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pin\" placeholder=\"GPIO\">
<input type=\"text\" class=\"form-control text-end\" id=\"${name}_pwm\" name=\"${name}_pwm\" data-color=\"$1\" pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pwm\" placeholder=\"PWM channel\">
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_inv\" value=\"true\"$is_active_low$is_disabled> active low</div>
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_lit\" value=\"true\"$lit_on_boot$is_disabled> lit on boot</div>
</div></div>"
}

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
		DEFAULT_PINS="$DEFAULT_PINS ${pin}${active_suffix}"
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
	tmpfile=$(mktemp)
	for c in $COLORS; do
		update_config "$c"
	done
	echo "gpio_default=$DEFAULT_PINS" >> $tmpfile
	fw_setenv -s $tmpfile
	rm $tmpfile
	redirect_to "$SCRIPT_NAME"
else
	read_data_from_env
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">

<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
<div class="col">
<%
field_gpio "r" "Red"
field_gpio "g" "Green"
field_gpio "b" "Blue"
%>
</div>
<div class="col">
<%
field_gpio "y" "Yellow"
field_gpio "o" "Orange"
field_gpio "w" "White"
%>
</div>
<div class="col">
<% ex "fw_printenv gpio_default" %>
<% ex "fw_printenv | grep gpio_led" %>
</div>
</div>

<% button_submit %>
</form>

<script>
async function switchIndicator(color, state) {
	await fetch(`/x/json-indicator.cgi?c=${color}&amp;s=${state}`)
		.then(res => res.json())
		.then(data => { $(`#gpio_led_${color}_on`).checked = (data.message.status == 1) });
}

$$('.led input[type="text"]').forEach(it => {
	it.onchange = (ev) => {
		const el = ev.target;
		const c = el.dataset.color;
		const s = (el.value == '');
		$$(`div.led-${c} input[type="checkbox"]`).forEach(z => {
			if (s) z.checked = false;
			z.disabled = s;
		});
	}
});

$$('.led-status').forEach(el => {
	el.onchange = (ev) => {
		switchIndicator(ev.target.dataset.color, ev.target.checked ? 1 : 0)
	}
});
</script>

<%in _footer.cgi %>
