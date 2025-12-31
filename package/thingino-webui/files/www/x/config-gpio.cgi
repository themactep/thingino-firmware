#!/bin/haserl
<%in _common.cgi %>
<%
page_title="LED/IRcut GPIO"

domain="gpio"
temp_file="/tmp/gpio.json"

set_value() {
[ -f "$temp_file" ] || echo '{}' > "$temp_file"
jct "$temp_file" set "$1" "$2" 2>/dev/null
}

save_gpio_pin() {
local name=$1
eval local pin=\$POST_${name}_pin
eval local inv=\$POST_${name}_inv
eval local lit=\$POST_${name}_lit
eval local ch=\$POST_${name}_ch
eval local lvl=\$POST_${name}_lvl

[ -z "$pin" ] && return

set_value "$domain.$name.pin" "$pin"
[ "$inv" = "true" ] && set_value "$domain.$name.active_low" "true" || set_value "$domain.$name.active_low" "false"
[ "$lit" = "true" ] && set_value "$domain.$name.active_on_boot" "true" || set_value "$domain.$name.active_on_boot" "false"
[ -n "$ch" ] && set_value "$domain.$name.pwm_channel" "$ch"
[ -n "$lvl" ] && set_value "$domain.$name.pwm_level" "$lvl"
}

if [ "POST" = "$REQUEST_METHOD" ]; then
	save_gpio_pin "led_r"
	save_gpio_pin "led_g"
	save_gpio_pin "led_b"
	save_gpio_pin "led_y"
	save_gpio_pin "led_o"
	save_gpio_pin "led_w"
	save_gpio_pin "ir850"
	save_gpio_pin "ir940"
	save_gpio_pin "white"
	
	ircut_pin1="$POST_ircut_pin1"
	ircut_pin2="$POST_ircut_pin2"
	if [ -n "$ircut_pin1" ] && [ -n "$ircut_pin2" ]; then
		set_value "$domain.ircut" "$ircut_pin1 $ircut_pin2"
	fi

	jct /etc/thingino.json import "$temp_file"
	rm -f "$temp_file"

	redirect_back "success" "Data updated"
fi

# Load GPIO data as JSON
gpio_json=$(jct /etc/thingino.json get gpio 2>/dev/null || echo '{}')

# Get PWM-capable pins
pwm_pins=$(pwm-ctrl -l 2>/dev/null | grep '^GPIO' | awk '{print $2}' | tr '\n' ',' | sed 's/,$//')
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4">
<div class="row row-cols-1 row-cols-sm-2 row-cols-xl-4 g-2" id="gpio-container">
</div>
<% button_submit %>
</form>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "fw_printenv | grep -E ^\(gpio\|pwm_ch\)_" %>
<% ex "jct /etc/thingino.json get gpio" %>
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
const gpioData = <%= $gpio_json %> || {};
const pwmPins = '<%= $pwm_pins %>'.split(',').map(p => parseInt(p)).filter(p => !isNaN(p));

const gpioConfigs = [
{ name: 'led_r', label: 'Red LED' },
{ name: 'led_g', label: 'Green LED' },
{ name: 'led_b', label: 'Blue LED' },
{ name: 'led_y', label: 'Yellow LED' },
{ name: 'led_o', label: 'Orange LED' },
{ name: 'led_w', label: 'White LED' },
{ name: 'ir850', label: '850 nm IR LED' },
{ name: 'ir940', label: '940 nm IR LED' },
{ name: 'white', label: 'White LED' }
];

function isPWMPin(pin) {
return pwmPins.includes(parseInt(pin));
}

function createGPIOCard(config) {
const { name, label } = config;
const pinData = gpioData[name];

if (!pinData) return '';

// Support both old format (string/number) and new format (object)
let pin, isActiveLow, activeOnBoot, pwmCh, pwmLvl;

if (typeof pinData === 'object' && pinData.pin !== undefined) {
// New nested object format
pin = pinData.pin;
isActiveLow = pinData.active_low === true || pinData.active_low === 'true';
activeOnBoot = pinData.active_on_boot === true || pinData.active_on_boot === 'true';
pwmCh = pinData.pwm_channel || '';
pwmLvl = pinData.pwm_level || '';
} else {
// Old format: "8O" or "7o" or just number
let pinValue = String(pinData);
let activeSuffix = 'O';

if (!/^\d+$/.test(pinValue)) {
activeSuffix = pinValue.slice(-1);
pin = pinValue.slice(0, -1);
} else {
pin = pinValue;
}

isActiveLow = activeSuffix === 'o';
activeOnBoot = false;
pwmCh = '';
pwmLvl = '';
}

const card = document.createElement('div');
card.className = 'col';
card.innerHTML = `
<div class="card h-100 gpio ${name}">
<div class="card-header">${label}
<div class="switch float-end">
<button class="btn btn-sm btn-outline-secondary m-0 led-status" type="button" id="${name}_toggle">Test</button>
</div>
</div>
<div class="card-body">
<div class="row">
<label class="form-label col-9" for="${name}_pin">GPIO pin #</label>
<div class="col">
<input type="text" class="form-control text-end" id="${name}_pin" name="${name}_pin" pattern="[0-9]{1,3}" title="a number" value="${pin}" required>
</div>
</div>
${isPWMPin(pin) ? `
<div class="row">
<label class="form-label col-9" for="${name}_ch">GPIO PWM channel</label>
<div class="col">
<input type="text" class="form-control text-end" id="${name}_ch" name="${name}_ch" pattern="[0-9]{1,3}" title="empty or a number" value="${pwmCh}">
</div>
</div>
<div class="row">
<label class="form-label col-9" for="${name}_lvl">GPIO PWM level</label>
<div class="col">
<input type="text" class="form-control text-end" id="${name}_lvl" name="${name}_lvl" pattern="[0-9]{1,3}" title="empty or a number" value="${pwmLvl}">
</div>
</div>
` : '<div class="text-warning">NOT A PWM PIN</div>'}
<div class="row">
<label class="form-label col-9" for="${name}_inv">Active low</label>
<div class="col">
<input class="form-check-input" type="checkbox" id="${name}_inv" name="${name}_inv" value="true"${isActiveLow ? ' checked' : ''}>
</div>
</div>
<div class="row mb-0">
<label class="form-label col-9" for="${name}_lit">Active on boot</label>
<div class="col">
<input class="form-check-input" type="checkbox" id="${name}_lit" name="${name}_lit" value="true"${activeOnBoot ? ' checked' : ''}>
</div>
</div>
</div>
</div>
`;

return card;
}

function createIRCutCard() {
const ircut = gpioData.ircut || [];
const pin1 = Array.isArray(ircut) ? ircut[0] : (ircut.split ? ircut.split(' ')[0] : '');
const pin2 = Array.isArray(ircut) ? ircut[1] : (ircut.split ? ircut.split(' ')[1] : '');

const card = document.createElement('div');
card.className = 'col';
card.innerHTML = `
<div class="card h-100">
<div class="card-header">IR cut filter
<div class="switch float-end">
<img src="/a/help.svg" alt="Help" class="img-fluid" type="button" data-bs-toggle="modal" data-bs-target="#helpModal" style="max-height:1.5rem">
</div>
</div>
<div class="card-body">
<div class="row mb-2">
<label class="form-label col-9" for="ircut_pin1">GPIO pin 1 #</label>
<div class="col">
<input type="text" class="form-control text-end" id="ircut_pin1" name="ircut_pin1" pattern="[0-9]{1,3}" value="${pin1 || ''}">
</div>
</div>
<div class="row mb-2">
<label class="form-label col-9" for="ircut_pin2">GPIO pin 2 #</label>
<div class="col">
<input type="text" class="form-control text-end" id="ircut_pin2" name="ircut_pin2" pattern="[0-9]{1,3}" value="${pin2 || ''}">
</div>
</div>
</div>
</div>
`;

return card;
}

const container = document.getElementById('gpio-container');
gpioConfigs.forEach(config => {
const card = createGPIOCard(config);
if (card) container.appendChild(card);
});
container.appendChild(createIRCutCard());

gpioConfigs.forEach(({ name }) => {
const toggle = document.getElementById(name + '_toggle');
if (toggle) {
toggle.addEventListener('click', () => {
fetch('/x/json-gpio.cgi?' + new URLSearchParams({ 'n': name, 's': '~' }).toString())
.then(res => res.json())
.then(data => console.log(data.message));
});
}
});
</script>

<%in _footer.cgi %>
