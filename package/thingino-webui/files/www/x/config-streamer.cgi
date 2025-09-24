#!/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="Streamer/OSD"

if [ "restart" = "$GET_do" ]; then
	service restart prudynt >/dev/null
	sleep 3
	redirect_to $SCRIPT_NAME
fi

OSD_FONT_PATH="/usr/share/fonts"
if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""
	if [ -z "$HASERL_fontfile_path" ]; then
		set_error_flag "File upload failed. No font selected?"
	elif [ $(stat -c%s $HASERL_fontfile_path) -eq 0 ]; then
		set_error_flag "File upload failed. Empty file?"
	else
		mv "$HASERL_fontfile_path" "$OSD_FONT_PATH/uploaded.ttf"
	fi
	redirect_to $SCRIPT_NAME
fi

AUDIO_FORMATS="AAC G711A G711U G726 OPUS PCM"

AUDIO_SAMPLING="8000,12000,16000,24000,48000"

AUDIO_BITRATES=$(seq 6 2 256)

FONTS=$(ls -1 $OSD_FONT_PATH)

ts=$(date +%s)

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

prudynt_config=/etc/prudynt.json

rtsp_username=$(awk -F: '/Streaming Service/{print $1}' /etc/passwd)
default_for rtsp_username $(jct $prudynt_config get rtsp.username)
default_for rtsp_password $(jct $prudynt_config get rtsp.password)
default_for rtsp_password "thingino"
%>
<%in _header.cgi %>

<nav class="navbar navbar-expand-lg mb-4 p-1">
<button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nbStreamer"
 aria-controls="nbStreamer" aria-label="Toggle navigation"><span class="navbar-toggler-icon"></span></button>
<div class="collapse navbar-collapse" id="nbStreamer">
<ul class="navbar-nav nav-underline" role="tablist">
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab1-pane" class="nav-link active" aria-current="page">Common</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab2-pane" class="nav-link">Main stream</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab2osd-pane" class="nav-link">Main OSD</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab3-pane" class="nav-link">Substream</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab3osd-pane" class="nav-link">Sub OSD</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab4-pane" class="nav-link">Audio</a></li>
<li class="nav-item"><a href="#" data-bs-toggle="tab" data-bs-target="#tab5-pane" class="nav-link">Image correction</a></li>
</ul>
</div>
</nav>

<div class="row row-cols-1 row-cols-lg-2">
<div class="col mb-3">

<div class="btn-toolbar" role="toolbar">
<div class="btn-group mb-3" role="group">
<button type="button" class="btn btn-secondary" data-bs-toggle="modal" data-bs-target="#mdPreview"
title="Full-screen"><img src="/a/zoom.svg" alt="Zoom" class="img-fluid icon-sm"></button>
<input type="radio" class="btn-check" name="stream2_jpeg_channel" id="stream2_jpeg_channel_0" value="0" checked>
<label class="btn btn-outline-primary" for="stream2_jpeg_channel_0">Main stream</label>
<input type="radio" class="btn-check" name="stream2_jpeg_channel" id="stream2_jpeg_channel_1" value="1">
<label class="btn btn-outline-primary" for="stream2_jpeg_channel_1">Substream</label>
</div>
</div>

<p><img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Stream Preview"></p>

<div class="d-flex flex-wrap align-content-around gap-1">
<a class="btn btn-secondary" href="<%= $SCRIPT_NAME %>?do=restart">Restart streamer</a>
<button type="button" class="btn btn-secondary" id="save-prudynt-config">Save config</button>
<a class="btn btn-secondary" href="tool-file-manager.cgi?dl=/etc/prudynt.json">Download config</a>
</div>
</div>
<div class="col mb-3">
<p class="small">Double-click on a range element will restore its default value.</p>

<div class="tab-content" id="streamer-tabs">
<div class="tab-pane fade show active" id="tab1-pane" role="tabpanel" aria-labelledby="tab1">
<div class="mb-2 select" id="image_core_wb_mode_wrap">
<label for="image_core_wb_mode" class="form-label">White balance mode</label>
<select class="form-select" id="image_core_wb_mode" name="image_core_wb_mode">
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
</div>
<% field_range "image_wb_bgain" "Blue channel gain" "0,1024,1" %>
<% field_range "image_wb_rgain" "Red channel gain" "0,1024,1" %>
<% field_range "image_ae_compensation" "<abbr title=\"Automatic Exposure\">AE</abbr> compensation" "0,255,1" %>
<% field_switch "image_hflip" "Flip image horizontally" %>
<% field_switch "image_vflip" "Flip image vertically" %>
</div>

<% for i in 0 1; do domain="stream$i" %>
<div class="tab-pane fade" id="tab<%= $((i+2)) %>-pane" role="tabpanel" aria-labelledby="tab<%= $((i+2)) %>">
<% field_switch "${domain}_enabled" "Enabled" %>
<div class="row g-2">
<div class="col-3"><% field_text "${domain}_width" "Width" %></div>
<div class="col-3"><% field_text "${domain}_height" "Height" %></div>
<div class="col-6"><% field_range "${domain}_fps" "FPS" "$sensor_fps_min,$sensor_fps_max,1" %></div>
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
<div class="col-9"><% field_text "${domain}_rtsp_endpoint" "Endpoint" %></div>
<div class="col-3"><% field_text "${domain}_rotation" "Rotation" %></div>
</div>
<% field_switch "${domain}_audio_enabled" "Audio in the stream" %>
<div class="alert alert-dark">RTSP stream URL:
<div class="cb">rtsp://<%= $rtsp_username %>:<%= $rtsp_password %>@<%= $network_address %>/ch<%= $i %></div>
</div>
</div>

<div class="tab-pane fade" id="tab<%= $((i+2)) %>osd-pane" role="tabpanel" aria-labelledby="tab<%= $((i+2)) %>osd">
<% field_switch "osd${i}_enabled" "OSD enabled" %>
<div class="row g-1">
<div class="col-6">
<label class="form-label" for="fontname<%= $i %>">Font</label>
<div class="input-group mb-3">
<button class="btn btn-secondary" type="button" data-bs-toggle="modal" data-bs-target="#mdFont" title="Upload a font">
<img src="/a/upload.svg" alt="Upload" class="img-fluid icon-sm">
</button>
<select class="form-select" id="fontname<%= $i %>">
<% for f in $FONTS; do %><option><%= $f %></option><% done %></select></div></div>
<div class="col-3"><% field_range "fontsize${i}" "Font size" "10,80,1" %></div>
<div class="col-3"><% field_range "fontstrokesize${i}" "Shadow size" "0,5,1" %></div>
</div>
<div class="d-flex gap-1">
<% field_switch "osd${i}_logo_enabled" "Logo" %>
</div>
<div class="row g-1">
<div class="col col-2"><% field_switch "osd${i}_time_enabled" "Time" %></div>
<div class="col col-3"><% field_color "osd${i}_time_fontcolor" "Color" %></div>
<div class="col col-3"><% field_color "osd${i}_time_fontstrokecolor" "Shadow" %></div>
<div class="col col-4"><% field_text "osd${i}_time_format" "Time format" "$STR_SUPPORTS_STRFTIME" %></div>
</div>
<div class="row g-1">
<div class="col col-2"><% field_switch "osd${i}_uptime_enabled" "Uptime" %></div>
<div class="col col-3"><% field_color "osd${i}_uptime_fontcolor" "Color" %></div>
<div class="col col-3"><% field_color "osd${i}_uptime_fontstrokecolor" "Shadow" %></div>
</div>
<div class="row g-1">
<div class="col col-2"><% field_switch "osd${i}_usertext_enabled" "User text" %></div>
<div class="col col-3"><% field_color "osd${i}_usertext_fontcolor" "Color" %></div>
<div class="col col-3"><% field_color "osd${i}_usertext_fontstrokecolor" "Shadow" %></div>
<div class="col col-4"><% field_text "osd${i}_usertext_format" "User text format" "$STR_usertext_FMT" %></div>
</div>
</div>
<% done %>

<div class="tab-pane fade" id="tab4-pane" role="tabpanel" aria-labelledby="tab4">
<% field_switch "audio_input_enabled" "Input Enabled" %>
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
<div class="row g-2">
<div class="col"><% field_switch "audio_input_agc_enabled" "<abbr title=\"Automatic gain control\">AGC</abbr> Enabled" %></div>
<div class="col"><% field_switch "audio_input_high_pass_filter" "High pass filter" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_input_noise_suppression" "Noise suppression level" "0,3,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_input_agc_compression_gain_db" "Compression gain, dB" "0,90,1" %></div>
<div class="col"><% field_range "audio_input_agc_target_level_dbfs" "Target level, dBfs" "0,31,1" %></div>
</div>

<% field_switch "audio_output_enabled" "Output Enabled" %>

<button type="button" class="btn btn-secondary" id="restart-audio">Restart Audio</button>
</div>

<div class="tab-pane fade" id="tab5-pane" role="tabpanel" aria-labelledby="tab5">
<% field_switch "image_running_mode" "Black-and-white mode" %>
<div class="row row-cols-1 row-cols-lg-3 g-2">
<div class="col"><% field_range "image_brightness" "Brightness" "0,255,1" %></div>
<div class="col"><% field_range "image_contrast" "Contrast" "0,255,1" %></div>
<div class="col"><% field_range "image_saturation" "Saturation" "0,255,1" %></div>
<div class="col"><% field_range "image_hue" "Hue" "0,255,1" %></div>
<div class="col"><% field_range "image_sharpness" "Sharpness" "0,255,1" %></div>
<div class="col"><% field_range "image_defog_strength" "Defog" "0,255,1" %></div>
<div class="col"><% field_range "image_sinter_strength" "Sinter" "0,255,1" %></div>
<div class="col"><% field_range "image_temper_strength" "Temper" "0,255,1" %></div>
<div class="col"><% field_range "image_dpc_strength" "<abbr title=\"Dead Pixel Compensation\">DPC</abbr> strength" "0,255,1" %></div>
<div class="col"><% field_range "image_drc_strength" "<abbr title=\"Dynamic Range Compression\">DRC</abbr> strength" "0,255,1" %></div>
<div class="col"><% field_range "image_max_again" "Max. analog gain" "0,160,1" %></div>
<div class="col"><% field_range "image_max_dgain" "Max. digital gain" "0,160,1" %></div>
<div class="col"><% field_range "image_backlight_compensation" "Backlight comp." "0,10,1" %></div>
<div class="col"><% field_range "image_highlight_depress" "Highlight depress" "0,255,1" %></div>
<div class="col"><% field_range "image_anti_flicker" "Anti-flicker" "0,2,1" %></div>
</div>
</div>

</div>
</div>
</div>

<div class="modal fade" id="mdFont" tabindex="-1" aria-labelledby="mdlFont" aria-hidden="true">
<div class="modal-dialog"><div class="modal-content"><div class="modal-header">
<h1 class="modal-title fs-4" id="mdlFont">Upload font file</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div><div class="modal-body text-center">

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4" enctype="multipart/form-data">
<% field_file "fontfile" "Upload a TTF file" %>
<% button_submit %></form></div></div></div></div>

<%in _preview.cgi %>

<script>
const soc = "<%= $soc_family %>";
const preview = $("#preview");
preview.onload = function() { URL.revokeObjectURL(this.src) }

function ts() {
	return Math.floor(Date.now());
}

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
	'input_noise_suppression', 'input_sample_rate', 'input_vol', 'output_enabled'];

// image
const image_params = ['ae_compensation', 'anti_flicker', 'backlight_compensation', 'brightness', 'contrast',
	'core_wb_mode', 'defog_strength', 'dpc_strength', 'drc_strength', 'hflip', 'highlight_depress', 'hue',
	'max_again', 'max_dgain', 'running_mode', 'saturation', 'sharpness', 'sinter_strength', 'temper_strength',
	'vflip', 'wb_bgain', 'wb_rgain'];

// motion
const motion_params = ['debounce_time', 'post_time', 'ivs_polling_timeout', 'cooldown_time', 'init_time', 'min_time',
	'sensitivity', 'skip_frame_count', 'frame_width', 'frame_height', 'monitor_stream', 'roi_0_x', 'roi_0_y',
	'roi_1_x', 'roi_1_y', 'roi_count'];

// stream [0, 1]
const stream_params = ['audio_enabled', 'bitrate', 'buffers', 'enabled', 'format', 'fps', 'gop', 'height', 'max_gop',
 	'mode', 'profile', 'rotation', 'rtsp_endpoint', 'width'];

// stream 2
const stream2_params = ['jpeg_channel'];

// OSD
const osd_params = ['enabled', 'font_path', 'font_size',
	'logo_enabled',
	'time_enabled', 'time_font_color', 'time_font_stroke_color', 'time_format',
	'uptime_enabled', 'uptime_font_color', 'uptime_font_stroke_color',
	'usertext_enabled', 'usertext_font_color', 'usertext_stroke_color', 'usertext_format'
];

let sts;

const wsPort = location.protocol === "https:" ? 8090 : 8089;
const wsProto = location.protocol === "https:" ? "wss:" : "ws:";
let ws = new WebSocket(`${wsProto}//${document.location.hostname}:${wsPort}?token=<%= $ws_token %>`);

ws.onopen = () => {
	console.log('WebSocket connection opened');
	const stream_rq = '{' +
		stream_params.map((x) => `"${x}":null`).join() +
		',"osd":{' + osd_params.map((x) => `"${x}":null`).join() + '}' +
		'}';
	const payload = '{' +
		'"stream0":' + stream_rq +
		',"stream1":' + stream_rq +
		',"stream2":{' + stream2_params.map((x) => `"${x}":null`).join() + '}' +
		',"audio":{' + audio_params.map((x) => `"${x}":null`).join() + '}' +
		',"image":{' + image_params.map((x) => `"${x}":null`).join() + '}' +
		'}';
	console.log('===>', payload);
	ws.send(payload);
	sts = setTimeout(getSnapshot, 1000);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (err) => { console.error('WebSocket error', err); }
ws.onmessage = (ev) => {
	if (typeof ev.data === 'string') {
		if (ev.data == '') return;
		const msg = JSON.parse(ev.data);
		if (msg.action && msg.action.capture == 'initiated') return;
		console.log(ts(), '<===', ev.data);

		let data;

		// Video
		for (const i in [0, 1]) {
			const domain = `stream${i}`;
			data = msg[domain];
			if (data) {
				stream_params.forEach((x) => {
					if (typeof(data[x]) !== 'undefined')
						setValue(data, domain, x);
				});
				if (data.osd) {
					if (data.osd.enabled) {
						$(`#osd${i}_enabled`).checked = data.osd.enabled;
						toggleWrappers(i);
					}
					if (data.osd.font_path)
						$(`#fontname${i}`).value = data.osd.font_path.split('/').reverse()[0];
					if (data.osd.font_size) {
						$(`#fontsize${i}`).value = data.osd.font_size;
						$(`#fontsize${i}-show`).textContent = data.osd.font_size;
					}
					if (data.osd.font_stroke_color)
						$(`#osd${i}_fontstrokecolor`).value = data.osd.font_stroke_color.replace(/^0x../, '#');
					if (data.osd.font_stroke) {
						$(`#fontstrokesize${i}`).value = data.osd.font_stroke;
						$(`#fontstrokesize${i}-show`).textContent = data.osd.font_stroke;
					}

					if (data.osd.logo_enabled)
						$(`#osd${i}_logo_enabled`).checked = data.osd.logo_enabled;

					if (data.osd.time_enabled)
						$(`#osd${i}_time_enabled`).checked = data.osd.time_enabled;
					if (data.osd.time_format)
						$(`#osd${i}_time_format`).value = data.osd.time_format;
					if (data.osd.time_font_color)
						$(`#osd${i}_time_fontcolor`).value = data.osd.time_font_color.replace(/^0x../, '#');
					if (data.osd.time_font_stroke_color)
						$(`#osd${i}_time_fontstrokecolor`).value = data.osd.time_font_stroke_color.replace(/^0x../, '#');

					if (data.osd.uptime_enabled)
						$(`#osd${i}_uptime_enabled`).checked = data.osd.uptime_enabled;
					if (data.osd.uptime_font_color)
						$(`#osd${i}_uptime_fontcolor`).value = data.osd.uptime_font_color.replace(/^0x../, '#');
					if (data.osd.uptime_font_stroke_color)
						$(`#osd${i}_uptime_fontstrokecolor`).value = data.osd.uptime_font_stroke_color.replace(/^0x../, '#');

					if (data.osd.usertext_enabled)
						$(`#osd${i}_usertext_enabled`).checked = data.osd.usertext_enabled;
					if (data.osd.usertext_font_color)
						$(`#osd${i}_usertext_fontcolor`).value = data.osd.usertext_font_color.replace(/^0x../, '#');
					if (data.osd.usertext_font_stroke_color)
						$(`#osd${i}_usertext_fontstrokecolor`).value = data.osd.usertext_font_stroke_color.replace(/^0x../, '#');
					if (data.osd.usertext_format)
						$(`#osd${i}_usertext_format`).value = data.osd.usertext_format;
				}
			}
		}

		// Stream 2
		{
			data = msg.stream2;
			if (data) {
				$('#stream2_jpeg_channel_0').checked = (data.jpeg_channel == 0);
				$('#stream2_jpeg_channel_1').checked = (data.jpeg_channel == 1);
			}
		}

		// Audio
		{
			data = msg.audio;
			if (data) {
				audio_params.forEach((x) => {
					if (typeof(data[x]) !== 'undefined')
						setValue(data, 'audio', x);
				});
			}
		}

		// Image
		{
			data = msg.image;
			if (data) {
				image_params.forEach((x) => {
					if (typeof(data[x]) !== 'undefined')
						setValue(data, 'image', x);
				});
			}
		}
	} else if (ev.data instanceof ArrayBuffer) {
		// console.log(ts(), '<===', ev.data);

		const blob = new Blob([ev.data], {type: 'image/jpeg'});
		const url = URL.createObjectURL(blob);
		preview.src = url;
		$("#preview_fullsize").src = url;
	}
}

function sendToWs(payload) {
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function getSnapshot() {
	clearTimeout(sts);
	ws.binaryType = 'arraybuffer';
	const payload = '{"action":{"capture":null}}';
	ws.send(payload);
	sts = setTimeout(getSnapshot, 500);
}

// n - stream #
function setFont(n) {
	const fontname = $(`#fontname${n}`).value;
	const fontsize = $(`#fontsize${n}`).value;
	const fontstrokesize = $(`#fontstrokesize${n}`).value;

	if (fontname == '' || fontsize == '') return;
	sendToWs('{"stream'+n+'":{"osd":{'+
		'"font_path":"/usr/share/fonts/'+fontname+'",'+
		'"font_size":'+fontsize+','+
		'"font_stroke_size":'+fontstrokesize+
		'}},"action":{"restart_thread":10}}');
}

// n - stream #,
// el - osd element
function setFontColor(n, el) {
	const fontcolor = $(`#osd${n}_${el}_fontcolor`).value.replace(/^#/, '');
	const fontstrokecolor = $(`#osd${n}_${el}_fontstrokecolor`).value.replace(/^#/, '');

	if (fontcolor == '' || fontstrokecolor == '') return;
	sendToWs('{"stream'+n+'":{"osd":{'+
		'"'+el+'_font_color":"0xff'+fontcolor+'",'+
		'"'+el+'_font_stroke_color":"0xff'+fontstrokecolor+'"'+
		'}},"action":{"restart_thread":10}}');
}

function toggleOSDElement(el) {
	const status = el.checked ? 'true' : 'false';
	const stream_id = el.id.substr(3, 1);
	const id = el.id.replace('osd0_', '').replace('osd1_', '');
	sendToWs('{"stream'+stream_id+'":{"osd":{'+
		'"'+id+'":'+status+
		'}},"action":{"restart_thread":10}}');
}

function toggleWrappers(id) {
	const wrappers = $$(`#fontname${id}_wrap,#fontsize${id}_wrap,#fontfile${id}_wrap`);
	if ($(`#osd${id}_enabled`).checked) {
		wrappers.forEach(el => el.classList.remove('d-none'));
	} else {
		wrappers.forEach(el => el.classList.add('d-none'));
	}
}

function saveValue(domain, name) {
	const el = $(`#${domain}_${name}`);
	if (!el) {
		// console.error(`Element #${domain}_${name} not found`);
		return;
	}

	let value;
	if (el.type == "checkbox") {
		if (domain == 'image' && name == 'running_mode')
			value = el.checked ? 1 : 0;
		else
			value = el.checked;
	} else {
		value = el.value;
		if (["format", "input_format", "mode", "rtsp_endpoint"].includes(name)) {
			value = `"${value}"`;
		}
	}

	let payload = `"${name}":${value}`
	let thread = 0;
	if (domain == 'audio') {
		thread += ThreadAudio;
		console.log(name, value);
		if (name == 'input_format') {
			if (value == '"G711A"' || value == '"G711U"') {
				payload += ',"input_sample_rate":8000'
			} else if (value == '"G726"') {
				payload += ',"input_sample_rate":16000'
			} else if (value == '"OPUS"') {
				payload += ',"input_sample_rate":48000'
			}
		}
	} else if (domain == 'stream0' || domain == 'stream1') {
		thread += ThreadRtsp;
		thread += ThreadVideo;
	} else {
		// domain 'image' does not need a restart
	}

	let json_actions = '';
	if (thread > 0) json_actions = ',"action":{"restart_thread":'+thread+'}';
	sendToWs('{"'+domain+'":{'+payload+json_actions+'}}');
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

$('#stream2_jpeg_channel_0').addEventListener('click', ev => {
	sendToWs('{"stream2":{"jpeg_channel":0},"action":{"restart_thread":11}}');
});

$('#stream2_jpeg_channel_1').addEventListener('click', ev => {
	sendToWs('{"stream2":{"jpeg_channel":1},"action":{"restart_thread":11}}');
});

$('#save-prudynt-config').addEventListener('click', ev => {
	sendToWs('{"action":{"save_config":null}}');
});

$('#restart-audio').addEventListener('click', ev => {
	sendToWs('{"action":{"restart_thread":' + ThreadAudio + '}}');
});

for (const i in [0, 1]) {
	$('#fontname'+i).onchange = () => setFont(i);
	$('#fontsize'+i).onchange = () => setFont(i);
	$('#fontstrokesize'+i).onchange = () => setFont(i);

	$('#osd'+i+'_enabled').onchange = (ev) => sendToWs('{"stream'+i+'":{"osd":{"enabled":'+ev.target.checked+'}},"action":{"restart_thread":10}}}');
	$('#osd'+i+'_logo_enabled').onchange = (ev) => toggleOSDElement(ev.target);

	$('#osd'+i+'_time_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_time_fontcolor').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_fontstrokecolor').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_format').onchange = (ev) => sendToWs('{"stream'+i+'":{"osd":{"time_format":"'+ev.target.value+'"}},"action":{"restart_thread":10}}}');

	$('#osd'+i+'_uptime_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_uptime_fontcolor').onchange = () => setFontColor(i, 'uptime');
	$('#osd'+i+'_uptime_fontstrokecolor').onchange = () => setFontColor(i, 'uptime');

	$('#osd'+i+'_usertext_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_usertext_fontcolor').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_fontstrokecolor').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_format').onchange = (ev) => sendToWs('{"stream'+i+'":{"osd":{"usertext_format":"'+ev.target.value+'"}},"action":{"restart_thread":10}}}');
}
</script>

<%in _footer.cgi %>
