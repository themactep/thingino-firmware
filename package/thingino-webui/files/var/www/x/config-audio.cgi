#!/bin/haserl
<%in _common.cgi %>
<%
token="$(cat /run/prudynt_websocket_token)"
plugin="audio"
plugin_name="Audio"
page_title="Audio"

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"
%>
<%in _header.cgi %>

<form action="<%= $SCRIPT_NAME %>" method="post">
<% field_switch "audio_input_enabled" "Enabled" %>
<div class="row g-4 mb-4">
<div class="col col-lg-4">
<% field_select "audio_input_format" "Audio codec" "$AUDIO_FORMATS" %>
<% field_select "audio_input_sample_rate" "Input audio sampling, Hz" "8000,16000,24000,44100,48000" %>
<% field_range "audio_input_bitrate" "Input audio bitrate, kbps" "6,256,1" %>
<% field_checkbox "audio_input_high_pass_filter" "High pass filter (HPF)" %>
<% field_checkbox "audio_input_agc_enabled" "Automatic gain control (AGC)" %>
</div>
<div class="col col-lg-4">
<% field_range "audio_input_vol" "Input volume" "-30,120,1" %>
<% field_range "audio_input_gain" "Input gain" "0,31,1" %>
<% field_range "audio_input_alc_gain" "ALC gain" "0,7,1" %>
</div>
<div class="col col-lg-4">
<% field_range "audio_input_agc_target_level_dbfs" "AGC target level, dBFS" "0,31,1" %>
<% field_range "audio_input_agc_compression_gain_db" "AGC compression gain, dB" "0,90,1" %>
<% field_range "audio_input_noise_suppression" "Noise suppression level" "0,3,1" %>
</div>
</div>
</form>

<script>
const AUDIO = 4;

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	payload = '{"audio":{'+
		'"input_enabled":null,'+
		'"input_format":null,'+
		'"input_sample_rate":null,'+
		'"input_bitrate":null,'+
		'"input_high_pass_filter":null,'+
		'"input_agc_enabled":null,'+
		'"input_vol":null,'+
		'"input_gain":null,'+
		'"input_alc_gain":null,'+
		'"input_agc_target_level_dbfs":null,'+
		'"input_agc_compression_gain_db":null,'+
		'"input_noise_suppression":null,'+
		'"z":null}}';
	console.log(payload);
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (error) => { console.error('WebSocket error', error); }
ws.onmessage = (event) => {
	console.log(event.data);
	const msg = JSON.parse(event.data);
	const time = new Date(msg.date);
	const timeStr = time.toLocaleTimeString();
	if (msg.audio)
		if (msg.audio.input_enabled)
			$('#audio_input_enabled').checked = msg.audio.input_enabled;
		if (msg.audio.input_format)
			$('#audio_input_format').value = msg.audio.input_format;
		if (msg.audio.input_sample_rate)
			$('#audio_input_sample_rate').value = msg.audio.input_sample_rate;
		if (msg.audio.input_bitrate) {
			$('#audio_input_bitrate').value = msg.audio.input_bitrate;
			$('#audio_input_bitrate-range').value = msg.audio.input_bitrate;
			$('#audio_input_bitrate-show').textContent = msg.audio.input_bitrate;
		}
		if (msg.audio.input_high_pass_filter) {
			$('#audio_input_high_pass_filter').checked = msg.audio.input_high_pass_filter;
		}
		if (msg.audio.input_agc_enabled) {
			$('#audio_input_agc_enabled').checked = msg.audio.input_agc_enabled;
		}
		if (msg.audio.input_vol) {
			$('#audio_input_vol').value = msg.audio.input_vol;
			$('#audio_input_vol-range').value = msg.audio.input_vol;
			$('#audio_input_vol-show').textContent = msg.audio.input_vol;
		}
		if (msg.audio.input_gain) {
			$('#audio_input_gain').value = msg.audio.input_gain;
			$('#audio_input_gain-range').value = msg.audio.input_gain;
			$('#audio_input_gain-show').textContent = msg.audio.input_gain;
		}
		if (msg.audio.input_alc_gain) {
			$('#audio_input_alc_gain').value = msg.audio.input_alc_gain;
			$('#audio_input_alc_gain-range').value = msg.audio.input_alc_gain;
			$('#audio_input_alc_gain-show').textContent = msg.audio.input_alc_gain;
		}
		if (msg.audio.input_agc_target_level_dbfs) {
			$('#audio_input_agc_target_level_dbfs').value = msg.audio.input_agc_target_level_dbfs;
			$('#audio_input_agc_target_level_dbfs-range').value = msg.audio.input_agc_target_level_dbfs;
			$('#audio_input_agc_target_level_dbfs-show').value = msg.audio.input_agc_target_level_dbfs;
		}
		if (msg.audio.input_agc_compression_gain_db) {
			$('#audio_input_agc_compression_gain_db').value = msg.audio.input_agc_compression_gain_db;
			$('#audio_input_agc_compression_gain_db-range').value = msg.audio.input_agc_compression_gain_db;
			$('#audio_input_agc_compression_gain_db-show').value = msg.audio.input_agc_compression_gain_db;
		}
		if (msg.audio.input_noise_suppression) {
			$('#audio_input_noise_suppression').value = msg.audio.input_noise_suppression;
			$('#audio_input_noise_suppression-range').value = msg.audio.input_noise_suppression;
			$('#audio_input_noise_suppression-show').value = msg.audio.input_noise_suppression;
		}
}

const andSave = ',"action":{"save_config":null,"restart_thread":'+AUDIO+'}'

function ts() {
	return Math.floor(Date.now());
}

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function saveValue(el) {
	let id = el.id.replace('audio_', '');
	if (el.type == "checkbox") {
		value = el.checked ? 'true' : 'false';
	} else if (el.type == "range") {
		value = el.value;
		id = id.replace(/-range/, '');
	} else {
		value = el.value;
		if (el.id == "audio_input_format")
			value = '"' + el.value + '"';
	}
	sendToWs('{"audio":{"' + id + '":' + value + '}}');
}

$('#audio_input_enabled').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_format').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_sample_rate').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_high_pass_filter').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_agc_enabled').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_bitrate-range').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_vol-range').addEventListener('change', ev => saveValue(ev.target));
$('#audio_input_gain-range').addEventListener('change', ev => saveValue(ev.target))
$('#audio_input_alc_gain-range').addEventListener('change', ev => saveValue(ev.target))
$('#audio_input_agc_target_level_dbfs-range').addEventListener('change', ev => saveValue(ev.target))
$('#audio_input_agc_compression_gain_db-range').addEventListener('change', ev => saveValue(ev.target))
$('#audio_input_noise_suppression-range').addEventListener('change', ev => saveValue(ev.target))
</script>

<%in _footer.cgi %>
