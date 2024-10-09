#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Prudynt"

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"
AUDIO_SAMPLING="8000,16000,24000,44100,48000"
AUDIO_BITRATES=$(seq 16 16 256)

stream0_name="Main stream"
stream1_name="Substream"

soc_family=$(soc -f)
soc_model=$(soc -m)

if [ "t30" = "$soc_family" ] || [ "t31" = "$soc_family" -a "t31lc" != "$soc_model" ]; then
	FORMATS="H264,H265"
else
	FORMATS="H264"
fi

modes="CBR VBR FIXQP"
case "$soc_family" in
	t31) modes="$modes CAPPED_VBR CAPPED_QUALITY" ;;
	  *) modes="$modes SMART" ;;
esac

prudynt_config=/etc/prudynt.cfg
onvif_config=/etc/onvif.conf
onvif_discovery=/etc/init.d/S96onvif_discovery
onvif_notify=/etc/init.d/S97onvif_notify

rtsp_username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
[ -z "$rtsp_username" ] && rtsp_username=$(awk -F'"' '/username/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password=$(awk -F'"' '/password/{print $2}' $prudynt_config)
[ -z "$rtsp_password" ] && rtsp_password="thingino"

if [ "POST" = "$REQUEST_METHOD" ]; then
	rtsp_password=$POST_rtsp_password
	sanitize rtsp_password

	if [ -z "$error" ]; then
		tmpfile=$(mktemp)
		cat $onvif_config > $tmpfile
		#sed -i "/^user=/cuser=$rtsp_username" $tmpfile
		sed -i "/^password=/cpassword=$rtsp_password" $tmpfile
		mv $tmpfile $onvif_config

		prudyntcfg set rtsp.password "\"$rtsp_password\""

		echo "$rtsp_username:$rtsp_password" | chpasswd -c sha512

		if [ -f "$onvif_discovery" ]; then
			$onvif_discovery restart >> /tmp/webui.log
		else
			echo "$onvif_discovery not found" >> /tmp/webui.log
		fi

		if [ -f "$onvif_notify" ]; then
			$onvif_notify restart >> /tmp/webui.log
		else
			echo "$onvif_notify not found" >> /tmp/webui.log
		fi

		update_caminfo
		redirect_to $SCRIPT_NAME
	fi
fi
%>
<%in _header.cgi %>

<div class="row row-cols-1 row-cols-xl-3 g-4">
<%
for i in 0 1; do
	domain="stream$i"
%>
<div class="col">
<h3><% eval echo \$${domain}_name %></h3>
<% field_switch "${domain}_enabled" "Enabled" %>
<div class="row g-2">
<div class="col-3"><% field_text "${domain}_width" "Width" %></div>
<div class="col-3"><% field_text "${domain}_height" "Height" %></div>
<div class="col-6"><% field_range "${domain}_fps" "FPS" "5,30,1" %></div>
</div>
<div class="row g-2">
<div class="col-3"><% field_select "${domain}_format" "Format" $FORMATS %></div>
<div class="col-3"><% field_text "${domain}_bitrate" "Bitrate" %></div>
<div class="col-6"><% field_select "${domain}_mode" "Mode" "$modes" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_text "${domain}_buffers" "Buffers" %></div>
<div class="col"><% field_text "${domain}_gop" "GOP" %></div>
<div class="col"><% field_text "${domain}_max_gop" "Max. GOP" %></div>
<div class="col"><% field_text "${domain}_profile" "Profile" %></div>
</div>
<div class="row g-2">
<div class="col-9"><% field_text "${domain}_rtsp_endpoint" "Endpoint" "rtsp://$rtsp_username:$rtsp_password@$network_address/ch$i" %></div>
<div class="col-3"><% field_text "${domain}_rotation" "Rotation" %></div>
</div>
<% field_switch "${domain}_audio_enabled" "Audio" %>
</div>
<% done %>
<div class="col">
<h3>Audio</h3>
<% field_switch "audio_input_enabled" "Enabled" %>
<div class="row g-2">
<div class="col"><% field_select "audio_input_format" "Codec" "$AUDIO_FORMATS" %></div>
<div class="col"><% field_select "audio_input_sample_rate" "Sampling, Hz" "$AUDIO_SAMPLING" %></div>
<div class="col"><% field_select "audio_input_bitrate" "Bitrate, kbps" "$AUDIO_BITRATES" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_input_vol" "Input volume" "-30,120,1" %></div>
<div class="col"><% field_range "audio_input_gain" "Input gain" "0,31,1" %></div>
<div class="col"><% field_range "audio_input_alc_gain" "ALC gain" "0,7,1" %></div>
</div>
<br>
<h6>Automatic gain control (AGC)</h6>
<div class="row g-2">
<div class="col"><% field_switch "audio_input_agc_enabled" "Enabled" %></div>
<div class="col"><% field_switch "audio_input_high_pass_filter" "High pass filter" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_input_noise_suppression" "Noise suppression level" "0,3,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_input_agc_compression_gain_db" "Compression gain, dB" "0,90,1" %></div>
<div class="col"><% field_range "audio_input_agc_target_level_dbfs" "Target level, dBfs" "0,31,1" %></div>
</div>
</div>
</div>

<script>
// stream0, stream1
const stream_params = ['bitrate', 'buffers', 'enabled', 'format', 'fps', 'gop', 'height', 'max_gop', 'mode',
	'profile', 'rotation', 'rtsp_endpoint', 'width'];

// audio
const audio_params = ['input_agc_compression_gain_db', 'input_agc_enabled', 'input_agc_target_level_dbfs',
	'input_alc_gain', 'input_bitrate', 'input_enabled', 'input_format', 'input_gain', 'input_high_pass_filter',
	'input_noise_suppression', 'input_sample_rate', 'input_vol'];

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	const stream_rq = '{' + stream_params.map((x) => `"${x}":null`).join() + '}';
	const payload = '{"stream0":' + stream_rq + ',"stream1":' + stream_rq + ',"audio":{' + audio_params.map((x) => `"${x}":null`).join() + '}}';
	console.log('===>', payload);
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (err) => { console.error('WebSocket error', err); }
ws.onmessage = (ev) => {
	if (ev.data == '') return;
	const msg = JSON.parse(ev.data);
	console.log(ts(), '<===', ev.data);

	// Video
	for (const i in [0, 1]) {
    const domain = `stream${i}`;
		const data = msg[domain];
		if (data) {
			stream_params.forEach((x) => {
				if (typeof(data[x]) !== 'undefined') setValue(data, domain, x);
			});
		}
	}
	// Audio
	{
		const data = msg.audio;
		if (data) {
			audio_params.forEach((x) => {
				if (typeof(data[x]) !== 'undefined') setValue(data, 'audio', x);
			});
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
		value = el.checked;
	} else {
		value = el.value;
		if (name == "height" || name == "width") {
			value = value &~ 15;
		} else if (name == "format") {
			value = `"${value}"`;
		}
	}

	let thread;
	if (domain == 'stream0' || domain == 'stream1') {
		thread = ThreadRtsp + ThreadVideo; //
	} else if (domain == 'audio') {
		thread = ThreadAudio;
	}

	sendToWs(`{"${domain}":{"${name}":${value}}},"action":{"save_config":null,"restart_thread":${thread}}`);
}

for (const i in [0, 1]) {
	stream_params.forEach((x) => {
		$(`#stream${i}_${x}`).onchange = (_) => saveValue(`stream${i}`, x);
	});
}
audio_params.forEach((x) => {
	$(`#audio_${x}`).onchange = (_) => saveValue('audio', x);
});
</script>

<%in _footer.cgi %>
