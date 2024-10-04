#!/bin/haserl
<%in _common.cgi %>
<%
plugin="audio"
plugin_name="Audio"
page_title="Audio"

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "input_enabled" "Enabled" %>
<div class="row row-cols-1 row-cols-lg-3 g-4 mb-4">
<div class="col">
<% field_select "input_format" "Audio codec" "$AUDIO_FORMATS" %>
<% field_select "input_sample_rate" "Input audio sampling, Hz" "8000,16000,24000,44100,48000" %>
<% field_range "input_bitrate" "Input audio bitrate, kbps" "6,256,1" %>
<% field_checkbox "input_high_pass_filter" "High pass filter (HPF)" %>
<% field_checkbox "input_agc_enabled" "Automatic gain control (AGC)" %>
</div>
<div class="col">
<% field_range "input_vol" "Input volume" "-30,120,1" %>
<% field_range "input_gain" "Input gain" "0,31,1" %>
<% field_range "input_alc_gain" "ALC gain" "0,7,1" %>
</div>
<div class="col">
<% field_range "input_agc_target_level_dbfs" "AGC target level, dBFS" "0,31,1" %>
<% field_range "input_agc_compression_gain_db" "AGC compression gain, dB" "0,90,1" %>
<% field_range "input_noise_suppression" "Noise suppression level" "0,3,1" %>
</div>
</div>
</form>

<script>
const params= ['input_agc_compression_gain_db', 'input_agc_enabled',
	'input_agc_target_level_dbfs', 'input_alc_gain', 'input_bitrate',
	'input_enabled', 'input_format', 'input_gain', 'input_high_pass_filter',
	'input_noise_suppression', 'input_sample_rate', 'input_vol'];

let ws = new WebSocket(`ws://${document.location.hostname}:8089?token=<%= $ws_token %>`);
ws.onopen = () => {
	console.log('WebSocket connection opened');
	payload = '{"audio":{' + params.map((x) => `"${x}":null`).join() + '}}';
	console.log(payload);
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (err) => { console.error('WebSocket error', err); }
ws.onmessage = (ev) => {
	if (ev.data == '') return;
	const msg = JSON.parse(ev.data);
	console.log(ts(), '<===', ev.data);
	let data = msg.audio;
	if (data) {
		if (data.input_enabled) $('#input_enabled').checked = data.input_enabled;
		if (data.input_format) $('#input_format').value = data.input_format;
		if (data.input_sample_rate) $('#input_sample_rate').value = data.input_sample_rate;
		if (data.input_bitrate) {
			$('#input_bitrate-show').value = data.input_bitrate;
			$('#input_bitrate').value = data.input_bitrate;
		}
		if (data.input_high_pass_filter) $('#input_high_pass_filter').checked = data.input_high_pass_filter;
		if (data.input_agc_enabled) $('#input_agc_enabled').checked = data.input_agc_enabled;
		if (data.input_vol) {
			$('#input_vol-show').value = data.input_vol;
			$('#input_vol').value = data.input_vol;
		}
		if (data.input_gain) {
			$('#input_gain-show').value = data.input_gain;
			$('#input_gain').value = data.input_gain;
		}
		if (data.input_alc_gain) {
			$('#input_alc_gain-show').value = data.input_alc_gain;
			$('#input_alc_gain').value = data.input_alc_gain;
		}
		if (data.input_agc_target_level_dbfs) {
			$('#input_agc_target_level_dbfs-show').value = data.input_agc_target_level_dbfs;
			$('#input_agc_target_level_dbfs').value = data.input_agc_target_level_dbfs;
		}
		if (data.input_agc_compression_gain_db) {
			$('#input_agc_compression_gain_db-show').value = data.input_agc_compression_gain_db;
			$('#input_agc_compression_gain_db').value = data.input_agc_compression_gain_db;
		}
		if (data.input_noise_suppression) {
			$('#input_noise_suppression-show').value = data.input_noise_suppression;
			$('#input_noise_suppression').value = data.input_noise_suppression;
		}
	}
}

const andSave = ',"action":{"save_config":null,"restart_thread":4}'

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function saveValue(domain, name) {
	const el = $(`#${name}`);
	if (!el) {
		console.error(`Element #${name} not found`);
		return;
	}
	let value;
	if (el.type == "checkbox") {
		value = el.checked;
	} else {
		value = el.value;
		if (el.id == "input_format")
			value = `"${value}"`;
	}
	sendToWs(`{"${domain}":{"${name}":${value}}}`);
}

params.forEach((x) => {
	$(`#${x}`).onchange = (ev) => saveValue("audio", x);
});
</script>

<%in _footer.cgi %>
