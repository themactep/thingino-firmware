#!/bin/haserl
<%in _common.cgi %>
<%
plugin="motion"
plugin_name="Motion guard"
page_title="Motion guard"
params="send2email send2ftp send2mqtt send2telegram send2webhook send2yadisk"

config_file="$ui_config_dir/$plugin.conf"
include $config_file
%>
<%in _header.cgi %>

<% field_switch "motion_enabled" "Enable motion guard" %>
<div class="row">
<div class="col">
<p>A motion event triggers the <code>/sbin/motion</code> script, which in turn sends alerts through the selected and preconfigured notification methods.</p>
<p>You must configure at least one notification method for the motion monitor to work.</p>
</div>
<div class="col">
<% field_checkbox "motion_send2email" "Send to email" "<a href=\"plugin-send2email.cgi\">Configure sending to email</a>" %>
<% field_checkbox "motion_send2telegram" "Send to Telegram" "<a href=\"plugin-send2telegram.cgi\">Configure sending to Telegram</a>" %>
<% field_checkbox "motion_send2mqtt" "Send to MQTT" "<a href=\"plugin-send2mqtt.cgi\">Configure sending to MQTT</a>" %>
</div>
<div class="col">
<% field_checkbox "motion_send2webhook" "Send to webhook" "<a href=\"plugin-send2webhook.cgi\">Configure sending to a webhook</a>" %>
<% field_checkbox "motion_send2ftp" "Upload to FTP" "<a href=\"plugin-send2ftp.cgi\">Configure uploading to FTP</a>" %>
<% field_checkbox "motion_send2yadisk" "Upload to Yandex Disk" "<a href=\"plugin-send2yadisk.cgi\">Configure sending to Yandex Disk</a>" %>
</div>
<div class="col">
<% field_range "motion_sensitivity" "Sensitivity" "1,8,1" %>
<% field_range "motion_cooldown_time" "Delay between alerts, sec." "5,30,1" %>
</div>
</div>
<script>
<% [ "true" != "$email_enabled" ] && echo "\$('#motion_send2email').disabled = true;" %>
<% [ "true" != "$ftp_enabled" ] && echo "\$('#motion_send2ftp').disabled = true;" %>
<% [ "true" != "$mqtt_enabled" ] && echo "\$('#motion_send2mqtt').disabled = true;" %>
<% [ "true" != "$telegram_enabled" ] && echo "\$('#motion_send2telegram').disabled = true;" %>
<% [ "true" != "$webhook_enabled" ] && echo "\$('#motion_send2webhook').disabled = true;" %>
<% [ "true" != "$yadisk_enabled" ] && echo "\$('#motion_send2yadisk').disabled = true;" %>

const motion_params = ['enabled', 'sensitivity', 'cooldown_time'];
const send2_targets = ['email', 'ftp', 'mqtt', 'telegram', 'webhook', 'yadisk'];

let ws = new WebSocket('//' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	const payload = '{"motion":{' + motion_params.map((x) => `"${x}":null`).join() + '}}';
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (err) => { console.error('WebSocket error', err); }
ws.onmessage = (ev) => {
	if (ev.data == '') return;
	const msg = JSON.parse(ev.data);
	console.log(ts(), '<===', ev.data);
	let data;
	data = msg.motion;
	if (data) {
		if (data.enabled)
			$('#motion_enabled').checked = data.enabled;
		if (data.sensitivity) {
			$('#motion_sensitivity').value = data.sensitivity;
			$('#motion_sensitivity-show').textContent = data.sensitivity;
		}
		if (data.cooldown_time) {
			$('#motion_cooldown_time').value = data.cooldown_time;
			$('#motion_cooldown_time-show').textContent = data.cooldown_time;
		}
	}
}

function sendToWs(payload) {
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function saveValue(domain, name) {
	const el = $(`#${domain}_${name}`);
	if (!el) {
		console.error(`Element #${domain}_${name} not found`);
		return;
	}
	let value;
	if (el.type == "checkbox") {
		value = el.checked ? 'true' : 'false';
	} else {
		value = el.value;
	}
	sendToWs(`{"${domain}":{"${name}":${value}},"action":{"save_config":null,"restart_thread":2}}`);
}

motion_params.forEach((x) => {
	$(`#motion_${x}`).onchange = (_) => saveValue('motion', x);
});

async function switchSend2Target(target, state) {
	await fetch('/x/json-motion.cgi?' + new URLSearchParams({ "target": target, "state": state }).toString())
		.then(res => res.json())
		.then(data => { $(`#motion_send2${data.message.target}`).checked = (data.message.status == 1) });
}

send2_targets.forEach((x) => {
	$(`#motion_send2${x}`).onchange = (ev) => switchSend2Target(x, ev.target.checked);
});
</script>

<%in _footer.cgi %>
