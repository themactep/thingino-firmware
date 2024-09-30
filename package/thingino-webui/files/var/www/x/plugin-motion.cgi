#!/bin/haserl
<%in _common.cgi %>
<%
plugin="motion"
plugin_name="Motion guard"
page_title="Motion guard"
params="send2email send2ftp send2mqtt send2telegram send2webhook send2yadisk"

config_file="$ui_config_dir/$plugin.conf"
[ -f "$config_file" ] || touch $config_file

if [ "POST" = "$REQUEST_METHOD" ]; then
	# parse values from parameters
	for p in $params; do
		eval ${plugin}_$p=\$POST_${plugin}_$p
		sanitize "${plugin}_$p"
	done; unset p

	if [ -z "$error" ]; then
		tmp_file=$(mktemp)
		for p in $params; do
			echo "${plugin}_$p=\"$(eval echo \$${plugin}_$p)\"" >>$tmp_file
		done; unset p
		mv $tmp_file $config_file

		/etc/init.d/S95prudynt restart >/dev/null

		update_caminfo
		redirect_to $SCRIPT_NAME
	fi
else
	include $config_file
fi
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "enabled" "Enable motion guard" %>
<div class="row g-4 mb-4">
<div class="col col-12 col-xl-4">
<% field_range "sensitivity" "Sensitivity" "1,8,1" %>
<% field_range "cooldown_time" "Delay between alerts, sec." "5,30,1" %>
</div>
<div class="col col-12 col-xl-4">
<h3>Actions</h3>
<ul class="list-group mb-3">
<li class="list-group-item"><% field_checkbox "motion_send2email" "Send to email" "<a href=\"plugin-send2email.cgi\">Configure sending to email</a>" %></li>
<li class="list-group-item"><% field_checkbox "motion_send2ftp" "Upload to FTP" "<a href=\"plugin-send2ftp.cgi\">Configure uploading to FTP</a>" %></li>
<li class="list-group-item"><% field_checkbox "motion_send2mqtt" "Send to MQTT" "<a href=\"plugin-send2mqtt.cgi\">Configure sending to MQTT</a>" %></li>
<li class="list-group-item"><% field_checkbox "motion_send2telegram" "Send to Telegram" "<a href=\"plugin-send2telegram.cgi\">Configure sending to Telegram</a>" %></li>
<li class="list-group-item"><% field_checkbox "motion_send2webhook" "Send to webhook" "<a href=\"plugin-send2webhook.cgi\">Configure sending to a webhook</a>" %></li>
<li class="list-group-item"><% field_checkbox "motion_send2yadisk" "Upload to Yandex Disk" "<a href=\"plugin-send2yadisk.cgi\">Configure sending to Yandex Disk</a>" %></li>
</ul>
</div>
<div class="col col-12 col-xl-4">
<% [ -f $config_file ] && ex "cat $config_file" %>
</div>
</div>
<% button_submit %>
</form>
<script>
<% [ "true" != "$email_enabled" ] && echo "\$('#motion_send2email').disabled = true;" %>
<% [ "true" != "$ftp_enabled" ] && echo "\$('#motion_send2ftp').disabled = true;" %>
<% [ "true" != "$mqtt_enabled" ] && echo "\$('#motion_send2mqtt').disabled = true;" %>
<% [ "true" != "$telegram_enabled" ] && echo "\$('#motion_send2telegram').disabled = true;" %>
<% [ "true" != "$webhook_enabled" ] && echo "\$('#motion_send2webhook').disabled = true;" %>
<% [ "true" != "$yadisk_enabled" ] && echo "\$('#motion_send2yadisk').disabled = true;" %>

//const andSave = ',"action":{"save_config":null,"restart_thread":1}'
const andSave = ',"action":{"save_config":null}'

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	payload = '{"motion":{'+
		'"enabled":null,'+
		'"sensitivity":null,'+
		'"cooldown_time":null,'+
		'"z":null}}';
	console.log(payload);
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (error) => { console.error('WebSocket error', error); }
ws.onmessage = (event) => {
	console.log(event.data);
	if (event.data == '') return;
	console.log(ts(), '<===', event.data);
	const msg = JSON.parse(event.data);
	console.log(msg);
	if (msg.motion) {
		if (typeof(msg.motion.enabled) !== 'undefined') {
			$('#enabled').checked = msg.motion.enabled;
		}
		if (typeof(msg.motion.sensitivity) !== 'undefined') {
			$('#sensitivity').value = msg.motion.sensitivity;
			$('#sensitivity-show').value = msg.motion.sensitivity;
		}
		if (typeof(msg.motion.cooldown_time) !== 'undefined') {
			$('#cooldown_time').value = msg.motion.cooldown_time;
			$('#cooldown_time-show').value = msg.motion.cooldown_time;
		}
	}
}

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function saveValue(el) {
	let id = el.id;
	if (el.type == "checkbox") {
		value = el.checked ? 'true' : 'false';
	} else {
		value = el.value;
		if (el.id == "input_format")
			value = `"${el.value}"`;
	}
	sendToWs(`{"motion":{"${id}":${value}}}`);
}

$$('#enabled, #sensitivity, #cooldown_time').forEach(el => {
	el.onchange = (ev) => saveValue(ev.target);
});
</script>

<%in _footer.cgi %>
