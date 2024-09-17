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
<div class="row g-4 mb-4">
<div class="col col-lg-4">
<% field_select "input_format" "Audio codec" "$AUDIO_FORMATS" %>
<% field_select "input_sample_rate" "Input audio sampling, Hz" "8000,16000,24000,44100,48000" %>
<% field_range "input_bitrate" "Input audio bitrate, kbps" "6,256,1" %>
<% field_checkbox "input_high_pass_filter" "High pass filter (HPF)" %>
<% field_checkbox "input_agc_enabled" "Automatic gain control (AGC)" %>
</div>
<div class="col col-lg-4">
<% field_range "input_vol" "Input volume" "-30,120,1" %>
<% field_range "input_gain" "Input gain" "0,31,1" %>
<% field_range "input_alc_gain" "ALC gain" "0,7,1" %>
</div>
<div class="col col-lg-4">
<% field_range "input_agc_target_level_dbfs" "AGC target level, dBFS" "0,31,1" %>
<% field_range "input_agc_compression_gain_db" "AGC compression gain, dB" "0,90,1" %>
<% field_range "input_noise_suppression" "Noise suppression level" "0,3,1" %>
</div>
</div>
</form>

<script>
const AUDIO = 4;

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
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
	console.log(msg);

	const time = new Date(msg.date);
	const timeStr = time.toLocaleTimeString();
	if (msg.audio) {
		if (typeof(msg.audio.input_enabled) !== 'undefined') {
			console.log('msg.audio.input_enabled', msg.audio.input_enabled);
			$('#input_enabled').checked = msg.audio.input_enabled;
		}
		if (typeof(msg.audio.input_format) !== 'undefined') {
			console.log('msg.audio.input_format', msg.audio.input_format);
			$('#input_format').value = msg.audio.input_format;
		}
		if (typeof(msg.audio.input_sample_rate) !== 'undefined') {
			console.log('msg.audio.input_sample_rate', msg.audio.input_sample_rate);
			$('#input_sample_rate').value = msg.audio.input_sample_rate;
		}
		if (typeof(msg.audio.input_bitrate) !== 'undefined') {
			console.log('msg.audio.input_bitrate', msg.audio.input_bitrate);
			$('#input_bitrate-show').value = msg.audio.input_bitrate;
			$('#input_bitrate').value = msg.audio.input_bitrate;
		}
		if (typeof(msg.audio.input_high_pass_filter) !== 'undefined') {
			console.log('msg.audio.input_high_pass_filter', msg.audio.input_high_pass_filter);
			$('#input_high_pass_filter').checked = msg.audio.input_high_pass_filter;
		}
		if (typeof(msg.audio.input_agc_enabled) !== 'undefined') {
			console.log('msg.audio.input_agc_enabled', msg.audio.input_agc_enabled);
			$('#input_agc_enabled').checked = msg.audio.input_agc_enabled;
		}
		if (typeof(msg.audio.input_vol) !== 'undefined') {
			console.log('msg.audio.input_vol', msg.audio.input_vol);
			$('#input_vol-show').value = msg.audio.input_vol;
			$('#input_vol').value = msg.audio.input_vol;
		}
		if (typeof(msg.audio.input_gain) !== 'undefined') {
			console.log('msg.audio.input_gain', msg.audio.input_gain);
			$('#input_gain-show').value = msg.audio.input_gain;
			$('#input_gain').value = msg.audio.input_gain;
		}
		if (typeof(msg.audio.input_alc_gain) !== 'undefined') {
			console.log('msg.audio.input_alc_gain', msg.audio.input_alc_gain);
			$('#input_alc_gain-show').value = msg.audio.input_alc_gain;
			$('#input_alc_gain').value = msg.audio.input_alc_gain;
		}
		if (typeof(msg.audio.input_agc_target_level_dbfs) !== 'undefined') {
			console.log('msg.audio.input_agc_target_level_dbfs',  msg.audio.input_agc_target_level_dbfs);
			$('#input_agc_target_level_dbfs-show').value = msg.audio.input_agc_target_level_dbfs;
			$('#input_agc_target_level_dbfs').value = msg.audio.input_agc_target_level_dbfs;
		}
		if (typeof(msg.audio.input_agc_compression_gain_db) !== 'undefined') {
			console.log('msg.audio.input_agc_compression_gain_db', msg.audio.input_agc_compression_gain_db);
			$('#input_agc_compression_gain_db-show').value = msg.audio.input_agc_compression_gain_db;
			$('#input_agc_compression_gain_db').value = msg.audio.input_agc_compression_gain_db;
		}
		if (typeof(msg.audio.input_noise_suppression) !== 'undefined') {
			console.log('msg.audio.input_noise_suppression', msg.audio.input_noise_suppression);
			$('#input_noise_suppression-show').value = msg.audio.input_noise_suppression;
			$('#input_noise_suppression').value = msg.audio.input_noise_suppression;
		}
	}
}

const andSave = ',"action":{"save_config":null,"restart_thread":'+AUDIO+'}'

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function saveValue(el) {
	let id = el.id;
	if (el.type == "checkbox") {
		value = el.checked ? 'true' : 'false';
//	} else if (el.type == "range") {
//		value = el.value;
	} else {
		value = el.value;
		if (el.id == "input_format")
			value = '"' + el.value + '"';
	}
	sendToWs('{"audio":{"' + id + '":' + value + '}}');
}

$$('#input_enabled, \
	#input_format, \
	#input_sample_rate, \
	#input_high_pass_filter, \
	#input_agc_enabled, \
	#input_bitrate, \
	#input_vol, \
	#input_gain, \
	#input_alc_gain, \
	#input_agc_target_level_dbfs, \
	#input_noise_suppression').forEach(
	el => el.addEventListener('change', ev => saveValue(ev.target))
);
</script>

<%in _footer.cgi %>
