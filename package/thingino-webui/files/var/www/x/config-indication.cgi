#!/usr/bin/haserl
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
	local pin
	local value
	local is_active
	local is_active_low
	local lit_on_boot
	local name=gpio_led_$1
	eval value=\$$name
	local active_suffix=${value:0-1}
	case "$active_suffix" in
		O) pin=${value%?} ;;
	 	o) pin=${value%?}; is_active_low="checked" ;;
		*) pin=${value}; active_suffix="O" ;;
	esac

	pin_status=$(gpio read $pin | awk '{print $3}')
	[ "$pin_status" -eq 1 ] && is_active="checked"

	if echo $DEFAULT_PINS | grep -E "\b${pin}${active_suffix}\b" > /dev/null; then
		lit_on_boot="checked"
	fi
	echo "<div class=\"mb-3\"><label class=\"form-label\" for=\"$name\">$2</label><div class=\"input-group\">
<div class=\"input-group-text\" style=\"background-color:$2\">
<input class=\"form-check-input mt-0 led-status\" type=\"checkbox\" id=\"${name}_on\" name=\"${name}_on\" data-color=\"$1\" value=\"true\" ${is_active}>
</div>
<input type=\"text\" class=\"form-control text-end\" name=\"$name\" pattern=\"[0-9]{1,3}\" title=\"empty or a number\" value=\"$pin\" placeholder=\"GPIO\">
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_inv\" value=\"true\" ${is_active_low}> active low</div>
<div class=\"input-group-text\"><input class=\"form-check-input mt-0 me-2\" type=\"checkbox\" name=\"${name}_lit\" value=\"true\" ${lit_on_boot}> lit on boot</div>
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
		echo "${name} ${pin}${active_suffix}" >> $tmpfile
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
		pin=$(fw_printenv -n ${name})
		[ -n "$pin" ] && DEFAULT_PINS=$(echo $DEFAULT_PINS | sed -E "s/\b($pin[oO])\b/ /")
		# drop individual environment settings for the color
		echo "${name}" >> $tmpfile
	fi
	# sqeeze spacing
	DEFAULT_PINS=$(echo $DEFAULT_PINS | tr -s ' ')
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
<div class="row row-cols-1 row-cols-md-2 row-cols-lg-3 g-4 mb-4">
<div class="col" style="width:30%">
<% field_gpio "r" "Red" %>
<% field_gpio "g" "Green" %>
<% field_gpio "b" "Blue" %>
</div>
<div class="col" style="width:30%">
<% field_gpio "y" "Yellow" %>
<% field_gpio "o" "Orange" %>
<% field_gpio "w" "White" %>
</div>
<div class="col" style="width:40%">
<% ex "fw_printenv | grep -E 'gpio_(led|default=)' | sort" %>
</div>
</div>
<% button_submit %>
</form>

<script>
async function switchIndicator(color, state) {
  await fetch("/x/j/indicator.cgi?c=" + color + "&amp;s=" + state)
  	.then(response => response.json())
  	.then(data => { $('#gpio_led_' + color + '_on').checked = (data.message.status == 1) });
}
$$('.led-status').forEach(el => el.addEventListener('change', ev => switchIndicator(ev.target.dataset['color'], ev.target.checked?1:0)))
</script>

<%in _footer.cgi %>
