#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motion Guard"
%>
<%in _header.cgi %>

<% field_switch "motion_enabled" "Enable motion guard" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_range "motion_sensitivity" "Sensitivity" "1,8,1" %>
<% field_range "motion_cooldown_time" "Delay between alerts, sec." "5,30,1" %>
</div>
<div class="col">
<% field_checkbox "motion_send2email" "Send to email address" "<a href=\"tool-send2email.cgi\">Configure sending to email</a>" %>
<% field_checkbox "motion_send2telegram" "Send to Telegram" "<a href=\"tool-send2telegram.cgi\">Configure sending to Telegram</a>" %>
<% field_checkbox "motion_send2mqtt" "Send to MQTT" "<a href=\"tool-send2mqtt.cgi\">Configure sending to MQTT</a>" %>
<% field_checkbox "motion_send2webhook" "Send to webhook" "<a href=\"tool-send2webhook.cgi\">Configure sending to a webhook</a>" %>
<% field_checkbox "motion_send2ftp" "Upload to FTP" "<a href=\"tool-send2ftp.cgi\">Configure uploading to FTP</a>" %>
<% field_checkbox "motion_send2yadisk" "Upload to Yandex Disk" "<a href=\"tool-send2yadisk.cgi\">Configure sending to Yandex Disk</a>" %>
</div>
<div class="col">
<div class="alert alert-info">
<p>A motion event is detected by the streamer which triggers the <code>/sbin/motion</code> script,
which sends alerts through the selected and preconfigured notification methods.</p>
<p>You must configure at least one notification method for the motion monitor to work.</p>
<% wiki_page "Plugin:-Motion-Guard" %>
</div>
</div>
</div>

<script>
const motion_params = ['enabled', 'sensitivity', 'cooldown_time'];
const send2_targets = ['email', 'ftp', 'mqtt', 'telegram', 'webhook', 'yadisk'];

const wsPort = location.protocol === "https:" ? 8090 : 8089;
let ws = new WebSocket('//' + document.location.hostname + ':' + wsPort + '?token=<%= $ws_token %>');

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

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "grep ^motion_ $CONFIG_FILE" %>
</div>

<%in _footer.cgi %>
