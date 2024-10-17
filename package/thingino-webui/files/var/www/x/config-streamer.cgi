#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Streamer"

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"
AUDIO_SAMPLING="8000,12000,16000,24000,48000"
AUDIO_BITRATES=$(seq 6 2 256)

WB_MODES="AUTO MANUAL DAY_LIGHT CLOUDY INCANDESCENT FLOURESCENT TWILIGHT SHADE WARM_FLOURESCENT CUSTOM"

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
%>
<%in _header.cgi %>

<p><a href="tool-file-manager.cgi?dl=/etc/prudynt.cfg">Download config file</a></p>

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
<div class="col"><% field_range "audio_input_alc_gain" "<abbr title=\"Automatic Level Control\">ALC</abbr> gain" "0,7,1" %></div>
</div>
<br>
<h6><abbr title="Automatic gain control">AGC</abbr></h6>
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
<div class="col">
<h3>Image correction</h3>

<div class="row g-2">
<div class="col"><% field_range "image_brightness" "Brightness" "0,255,1" %></div>
<div class="col"><% field_range "image_contrast" "Contrast" "0,255,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_saturation" "Saturation" "0,255,1" %></div>
<div class="col"><% field_range "image_hue" "Hue" "0,255,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_sharpness" "Sharpness" "0,255,1" %></div>
<div class="col"><% field_range "image_defog_strength" "Defog" "0,255,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_sinter_strength" "Sinter" "0,255,1" %></div>
<div class="col"><% field_range "image_temper_strength" "Temper" "0,255,1" %></div>
</div>

</div>
<div class="col">

<h3>White balance</h3>

<div class="col"><p class="select" id="image_core_wb_mode_wrap">
<label for="image_core_wb_mode" class="form-label">White balance mode</label>
<select class="form-select" id="image_core_wb_mode" name="image_core_wb_mode">
<option value="">- Select -</option>
<option value="0">AUTO</option>
<option value="1">MANUAL</option>
<option value="2">DAY LIGHT</option>
<option value="3">CLOUDY</option>
<option value="4">INCANDESCENT</option>
<option value="5">FLOURESCENT</option>
<option value="6">TWILIGHT</option>
<option value="7">SHADE</option>
<option value="8">WARM FLOURESCENT</option>
<option value="9">CUSTOM</option>
</select>
</p></div>
<div class="col"><% field_range "image_wb_bgain" "Blue channel gain" "0,1024,1" %></div>
<div class="col"><% field_range "image_wb_rgain" "Red channel gain" "0,1024,1" %></div>
<div class="col"><% field_range "image_ae_compensation" "<abbr title=\"Automatic Exposure\">AE</abbr> compensation" "0,255,1" %></div>

</div>
<div class="col">
<h3>Image autocorrection</h3>

<div class="row g-2">
<div class="col"><% field_range "image_dpc_strength" "<abbr title=\"Dead Pixel Compensation\">DPC</abbr> strength" "0,255,1" %></div>
<div class="col"><% field_range "image_drc_strength" "<abbr title=\"Dynamic Range Compression\">DRC</abbr> strength" "0,255,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_max_again" "Max. analog gain" "0,160,1" %></div>
<div class="col"><% field_range "image_max_dgain" "Max. digital gain" "0,160,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_backlight_compensation" "Backlight comp." "0,10,1" %></div>
<div class="col"><% field_range "image_highlight_depress" "Highlight depress" "0,255,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "image_anti_flicker" "Anti-flicker" "0,2,1" %></div>
<div class="col"><% field_range "image_running_mode" "Running mode" "0,1,1" %></div>
</div>
</div>

</div>

<p class="text-info">NB! Double-clicking on a range element will restore its default value.</p>

<script>
const soc = "<% soc -f | tr -d '\n' %>";

if (soc == "t31") {
    DEFAULT_ENC_MODE_0 = "FIXQP"
    DEFAULT_ENC_MODE_1 = "CAPPED_QUALITY"
    DEFAULT_BUFFERS_0 = 4
    DEFAULT_BUFFERS_1 = 2
    DEFAULT_SINTER = 128
    DEFAULT_TEMPER = 128
} else if (soc == "t23") {
    DEFAULT_ENC_MODE_0 = "SMART"
    DEFAULT_ENC_MODE_1 = "SMART"
    DEFAULT_BUFFERS_0 = 2
    DEFAULT_BUFFERS_1 = 2
    DEFAULT_SINTER = 128
    DEFAULT_TEMPER = 128
} else {
    DEFAULT_ENC_MODE_0 = "SMART"
    DEFAULT_ENC_MODE_1 = "SMART"
    DEFAULT_BUFFERS_0 = 2
    DEFAULT_BUFFERS_1 = 2
    DEFAULT_SINTER = 50
    DEFAULT_TEMPER = 50
}

DEFAULT_VALUES = {
	'audio_input_agc_compression_gain_db': 0,
	'audio_input_agc_target_level_dbfs': 10,
	'audio_input_alc_gain': 0,
	'audio_input_gain': 25,
	'audio_input_noise_suppression': 0,
	'audio_input_sample_rate':  16000,
	'audio_input_vol': 80,
	'image_ae_compensation': 128,
	'image_anti_flicker': 2,
	'image_backlight_compensation': 0,
	'image_brightness': 128,
	'image_contrast': 128,
	'image_core_wb_mode': 0,
	'image_defog_strength': 128,
	'image_dpc_strength': 128,
	'image_drc_strength': 128,
	'image_highlight_depress': 0,
	'image_hue': 128,
	'image_max_again': 160,
	'image_max_dgain': 80,
	'image_running_mode': 0,
	'image_saturation': 128,
	'image_sharpness': 128,
	'image_sinter_strength': DEFAULT_SINTER,
	'image_temper_strength': DEFAULT_TEMPER,
	'image_wb_bgain': 0,
	'image_wb_rgain': 0,
	'image_hflip': false,
	'image_vflip': false,
	'stream0_fps': 25,
	'stream1_fps': 25,
}

// audio
const audio_params = ['input_agc_compression_gain_db', 'input_agc_enabled', 'input_agc_target_level_dbfs',
	'input_alc_gain', 'input_bitrate', 'input_enabled', 'input_format', 'input_gain', 'input_high_pass_filter',
	'input_noise_suppression', 'input_sample_rate', 'input_vol'];

// image
const image_params = ['ae_compensation', 'anti_flicker', 'backlight_compensation', 'brightness', 'contrast',
	'core_wb_mode', 'defog_strength', 'dpc_strength', 'drc_strength', 'highlight_depress', 'hue', 'max_again',
	'max_dgain', 'running_mode', 'saturation', 'sharpness', 'sinter_strength', 'temper_strength', 'wb_bgain',
	 'wb_rgain'];

// motion
const motion_params = ['debounce_time', 'post_time', 'ivs_polling_timeout', 'cooldown_time', 'init_time', 'min_time',
	'sensitivity', 'skip_frame_count', 'frame_width', 'frame_height', 'monitor_stream', 'roi_0_x', 'roi_0_y',
	'roi_1_x', 'roi_1_y', 'roi_count'];

// stream [0, 1]
const stream_params = ['audio_enabled', 'bitrate', 'buffers', 'enabled', 'format', 'fps', 'gop', 'height', 'max_gop',
 	'mode', 'profile', 'rotation', 'rtsp_endpoint', 'width'];

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	const stream_rq = '{' + stream_params.map((x) => `"${x}":null`).join() + '}';
	const payload = '{' +
		'"stream0":' + stream_rq +
		',"stream1":' + stream_rq +
		',"audio":{' + audio_params.map((x) => `"${x}":null`).join() + '}' +
		',"image":{' + image_params.map((x) => `"${x}":null`).join() + '}' +
		'}';
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
				if (typeof(data[x]) !== 'undefined')
					setValue(data, domain, x);
			});
		}
	}
	// Audio
	{
		const data = msg.audio;
		if (data) {
			audio_params.forEach((x) => {
				if (typeof(data[x]) !== 'undefined')
					setValue(data, 'audio', x);
			});
		}
	}
	// Image
	{
		const data = msg.image;
		if (data) {
			image_params.forEach((x) => {
				if (typeof(data[x]) !== 'undefined')
					setValue(data, 'image', x);
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
		// console.error(`Element #${domain}_${name} not found`);
		return;
	}
	let value;
	if (el.type == "checkbox") {
		value = el.checked;
	} else {
		value = el.value;
		if (name == "height" || name == "width") {
			value = value &~ 15;
		} else if (["format", "input_format", "mode", "rtsp_endpoint"].includes(name)) {
			value = `"${value}"`;
		}
	}
	let payload = `"${name}":${value}`
	let thread = 0;
	if (domain == 'stream0' || domain == 'stream1') {
		thread += ThreadRtsp;
		thread += ThreadVideo;
	} else if (domain == 'audio') {
		thread += ThreadAudio;
		console.log(name, value);
		if (name == 'input_format') {
			if (value == '"G711A"' || value == '"G711U"') {
				payload += `,"input_sample_rate":8000`
			} else if (value == '"G726"') {
				payload += `,"input_sample_rate":16000`
			} else if (value == '"OPUS"') {
                        	payload += `,"input_sample_rate":48000`
			}
		}
	}
	let json_actions = '"action":{';
	// save changes to config file
	json_actions += '"save_config":null';
	// restart threads if needed
	if (thread > 0)
		 json_actions += `,"restart_thread":${thread}`;
	json_actions += '}';

	sendToWs(`{"${domain}":{${payload}},${json_actions}}`);
}

for (const i in [0, 1]) {
	stream_params.forEach((x) => {
		const el = $(`#stream${i}_${x}`);
		if (!el) {
			console.debug(`element #stream${i}_${x} not found`);
			return;
		}
		el.addEventListener('change', (_) => {
			saveValue(`stream${i}`, x);
		});
		el.addEventListener('dblclick', (_) => {
			const v = DEFAULT_VALUES[`stream${i}_${x}`];
			el.value = v;
			$(`#stream${i}_${x}-show`).textContent = v;
			saveValue(`stream${i}`, x);
		});
	});
}

audio_params.forEach((x) => {
	const el = $(`#audio_${x}`);
	if (!el) {
		console.debug(`element #image_${x} not found`);
		return;
	}
	el.addEventListener('change', (_) => {
		saveValue('audio', x);
	});
	el.addEventListener('dblclick', (_) => {
		const v = DEFAULT_VALUES[`audio_${x}`];
		el.value = v;
		$(`#audio_${x}-show`).textContent = v;
		saveValue('audio', x);
	});
});

image_params.forEach((x) => {
	const el = $(`#image_${x}`);
	if (!el) {
		console.debug(`element #image_${x} not found`);
		return;
	}
	el.addEventListener('change', (_) => {
		saveValue('image', x);
	});
	el.addEventListener('dblclick', (_) => {
		const v = DEFAULT_VALUES[`image_${x}`];
		el.value = v;
		$(`#image_${x}-show`).textContent = v;
		saveValue('image', x);
	});
});
</script>

<%in _footer.cgi %>
