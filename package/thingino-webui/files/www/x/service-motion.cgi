#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Motion Guard"

domain="motion"
config_file="/etc/prudynt.json"
temp_config_file="/tmp/$domain.json"

get_value() {
	jct $config_file get "$domain.$1"
}

read_config() {
	[ -f "$config_file" ] || return

	enabled=$(get_value enabled)
	send2email=$(get_value send2email)
	send2ftp=$(get_value send2ftp)
	send2mqtt=$(get_value send2mqtt)
	send2ntfy=$(get_value send2ntfy)
	send2telegram=$(get_value send2telegram)
	send2webhook=$(get_value send2webhook)
	playonspeaker=$(get_value playonspeaker)
	sensitivity=$(get_value sensitivity)
	cooldown_time=$(get_value cooldown_time)
}

read_config
%>
<%in _header.cgi %>

<% field_switch "enabled" "Enable motion guard" %>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-3">
<div class="col">
<% field_range "sensitivity" "Sensitivity" "1,8,1" %>
<% field_range "cooldown_time" "Delay between alerts, sec." "5,60,1" %>
</div>
<div class="col">
<% field_checkbox "send2email" "Send to email address" "<a href=\"tool-send2email.cgi\">Configure sending to email</a>" %>
<% field_checkbox "send2ftp" "Upload to FTP" "<a href=\"tool-send2ftp.cgi\">Configure uploading to FTP</a>" %>
<% field_checkbox "send2mqtt" "Send to MQTT" "<a href=\"tool-send2mqtt.cgi\">Configure sending to MQTT</a>" %>
<% field_checkbox "send2ntfy" "Send to Ntfy" "<a href=\"tool-send2ntfy.cgi\">Configure sending to Ntfy</a>" %>
<% field_checkbox "send2telegram" "Send to Telegram" "<a href=\"tool-send2telegram.cgi\">Configure sending to Telegram</a>" %>
<% field_checkbox "send2webhook" "Send to webhook" "<a href=\"tool-send2webhook.cgi\">Configure sending to a webhook</a>" %>
<% field_checkbox "playonspeaker" "Play on speaker" "<a href=\"tool-send2speaker.cgi\">Configure playing</a>" %>
</div>
<div class="col">
<div class="alert alert-info">
<p>A motion event is detected by the streamer which triggers the <code>/sbin/motion</code> script,
which sends alerts through the selected and preconfigured notification methods.</p>
<% wiki_page "Plugin:-Motion-Guard" %>
</div>
</div>
</div>

<script>
const endpoint = '/x/json-motion.cgi';

function handleMessage(msg) {
	if (msg.action && msg.action.capture == 'initiated') return;

	let data;

	data = msg.motion;
	if (data) {
		if (data.enabled)
			$('#enabled').checked = data.enabled;
		if (data.sensitivity) {
			$('#sensitivity').value = data.sensitivity;
			$('#sensitivity-show').textContent = data.sensitivity;
		}
		if (data.cooldown_time) {
			$('#cooldown_time').value = data.cooldown_time;
			$('#cooldown_time-show').textContent = data.cooldown_time;
		}
	}
}

async function sendToEndpoint(payload) {
	console.log(ts(), '===>', payload);
	try {
		const response = await fetch(endpoint + '?' + payload);
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		const contentType = response.headers.get('content-type');
		if (contentType?.includes('application/json')) {
			const msg = await response.json();
			console.log(ts(), '<===', JSON.stringify(msg));
			handleMessage(msg);
		}
	} catch (err) {
		console.error('Send error', err);
	}
}

function saveValue(name) {
	const el = $(`#${name}`);
	if (!el) {
		console.error(`Element #${name} not found`);
		return;
	}
	let value;
	if (el.type == "checkbox") {
		value = el.checked ? 'true' : 'false';
	} else {
		value = el.value;
	}
	payload = new URLSearchParams({ "target": name, "state": value }).toString()
	sendToEndpoint(payload);
}

$$('#enabled, #send2email, #send2ftp, #send2mqtt, #send2ntfy, #send2telegram, #send2webhook, #playonspeaker, #sensitivity, #cooldown_time').forEach((x) => {
	x.onchange = (_) => saveValue(x.id);
});

/*
async function switchSend2Target(target, state) {
	await fetch('/x/json-motion.cgi?' + new URLSearchParams({ "target": target, "state": state }).toString())
		.then(res => res.json())
		.then(data => { $(`#${data.message.target}`).checked = (data.message.status == 1) });
}

// range
$$('#sensitivity, #cooldown_time').forEach((el) => {
	el.onchange = (ev) => {
		fetch('/x/json-motion.cgi?' + new URLSearchParams({ "target": el.id, "state": el.value }).toString())
			.then(res => res.json())
			.then(data => { $(`#${data.message.target}`).value = (data.message.state) });
	}
});

// boolean
$$('#enabled, #send2email, #send2ftp, #send2mqtt, #send2ntfy, #send2telegram, #send2webhook').forEach((el) => {
	el.onchange = (ev) => switchSend2Target(el.id, ev.target.checked);
});
*/
</script>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
<% ex "jct $config_file get $domain" %>
</div>

<%in _footer.cgi %>
