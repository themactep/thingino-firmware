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
<input type="radio" class="btn-check" name="preview_source" id="preview_source_0" value="0" checked>
<label class="btn btn-outline-primary" for="preview_source_0">Main stream</label>
<input type="radio" class="btn-check" name="preview_source" id="preview_source_1" value="1">
<label class="btn btn-outline-primary" for="preview_source_1">Substream</label>
</div>
</div>

<p><img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Stream Preview"></p>

<div class="d-flex flex-wrap align-content-around gap-1">
<a class="btn btn-warning" href="<%= $SCRIPT_NAME %>?do=restart">Restart streamer</a>
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
<label class="form-label" for="osd<%= $i %>_fontname">Font</label>
<div class="input-group mb-3">
<button class="btn btn-secondary" type="button" data-bs-toggle="modal" data-bs-target="#mdFont" title="Upload a font">
<img src="/a/upload.svg" alt="Upload" class="img-fluid icon-sm">
</button>
<select class="form-select" id="osd<%= $i %>_fontname">
<% for f in $FONTS; do %><option><%= $f %></option><% done %></select></div></div>
<div class="col-3"><% field_range "osd${i}_fontsize" "Font size" "10,80,1" %></div>
<div class="col-3"><% field_range "osd${i}_strokesize" "Shadow size" "0,5,1" %></div>
</div>
<div class="accordion" id="#osd${i}Elements">
<div class="accordion-item">
<div class="accordion-header" id="headingLogo">
<button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseLogo" aria-controls="collapseLogo" aria-expanded="false">Logo</button>
</div>
<div id="collapseLogo" class="accordion-collapse collapse" aria-labelledby="headingLogo" data-bs-parent="#osd${i}Elements">
<div class="accordion-body">
<% field_switch "osd${i}_logo_enabled" "Display" %>
</div>
</div>
</div>
<div class="accordion-item">
<div class="accordion-header" id="headingTime">
<button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseTime" aria-controls="collapseTime" aria-expanded="false">Time</button>
</div>
<div id="collapseTime" class="accordion-collapse collapse" aria-labelledby="headingTime" data-bs-parent="#osd${i}Elements">
<div class="accordion-body">
<% field_switch "osd${i}_time_enabled" "Display" %>
<div class="row g-1">
<div class="col col-4"><% field_color "osd${i}_time_fillcolor" "Color" %></div>
<div class="col col-4"><% field_color "osd${i}_time_strokecolor" "Shadow" %></div>
<div class="col col-4"><% field_text "osd${i}_time_format" "Format" "$STR_SUPPORTS_STRFTIME" %></div>
</div>
</div>
</div>
</div>
<div class="accordion-item">
<div class="accordion-header" id="headingUptime">
<button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseUptime" aria-controls="collapseUptime" aria-expanded="false">Uptime</button>
</div>
<div id="collapseUptime" class="accordion-collapse collapse" aria-labelledby="headingUptime" data-bs-parent="#osd${i}Elements">
<div class="accordion-body">
<% field_switch "osd${i}_uptime_enabled" "Display" %>
<div class="row g-1">
<div class="col col-4"><% field_color "osd${i}_uptime_fillcolor" "Color" %></div>
<div class="col col-4"><% field_color "osd${i}_uptime_strokecolor" "Shadow" %></div>
</div>
</div>
</div>
</div>
<div class="accordion-item">
<div class="accordion-header" id="headingUsertext">
<button class="accordion-button collapsed" type="button" data-bs-toggle="collapse" data-bs-target="#collapseUsertext" aria-controls="collapseUsertext" aria-expanded="false">User Text</button>
</div>
<div id="collapseUsertext" class="accordion-collapse collapse" aria-labelledby="headingUsertext" data-bs-parent="#osd${i}Elements">
<div class="accordion-body">
<% field_switch "osd${i}_usertext_enabled" "Display" %>
<div class="row g-1">
<div class="col col-4"><% field_color "osd${i}_usertext_fillcolor" "Color" %></div>
<div class="col col-4"><% field_color "osd${i}_usertext_strokecolor" "Shadow" %></div>
<div class="col col-4"><% field_text "osd${i}_usertext_format" "Format" "$STR_usertext_FMT" %></div>
</div>
</div>
</div>
</div>
</div>
</div>
<% done %>

<div class="tab-pane fade" id="tab4-pane" role="tabpanel" aria-labelledby="tab4">
<% field_switch "audio_mic_enabled" "Microphone Enabled" %>
<div class="row g-2">
<div class="col"><% field_select "audio_mic_format" "Codec" "$AUDIO_FORMATS" %></div>
<div class="col"><% field_select "audio_mic_sample_rate" "Sampling, Hz" "$AUDIO_SAMPLING" %></div>
<div class="col"><% field_select "audio_mic_bitrate" "Bitrate, kbps" "$AUDIO_BITRATES" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_mic_vol" "Mic volume" "-30,120,1" %></div>
<div class="col"><% field_range "audio_mic_gain" "Mic gain" "0,31,1" %></div>
<div class="col"><% field_range "audio_mic_alc_gain" "<abbr title=\"Automatic Level Control\">ALC</abbr> gain" "0,7,1" %></div>
</div>
<br>
<div class="row g-2">
<div class="col"><% field_switch "audio_mic_agc_enabled" "<abbr title=\"Automatic gain control\">AGC</abbr> Enabled" %></div>
<div class="col"><% field_switch "audio_mic_high_pass_filter" "High pass filter" %></div>
<div class="col"><% field_switch "audio_force_stereo" "Force stereo" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_mic_noise_suppression" "Noise suppression level" "0,3,1" %></div>
</div>
<div class="row g-2">
<div class="col"><% field_range "audio_mic_agc_compression_gain_db" "Compression gain, dB" "0,90,1" %></div>
<div class="col"><% field_range "audio_mic_agc_target_level_dbfs" "Target level, dBfs" "0,31,1" %></div>
</div>
<br>
<% field_switch "audio_spk_enabled" "Speaker Enabled" %>
<div class="row g-2">
<div class="col"><% field_range "audio_spk_vol" "Speaker volume" "-30,120,1" %></div>
<div class="col"><% field_range "audio_spk_gain" "Speaker gain" "0,31,1" %></div>
<div class="col"><% field_select "audio_spk_sample_rate" "Speaker sampling, Hz" "$AUDIO_SAMPLING" %></div>
</div>

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

<div class="alert alert-danger mt-5">
<p>If you made changes that messed up the settings, you can restore the original configuration and start from scratch.</p>
<% button_restore_from_rom "/etc/prudynt.json" %>
</div>

<div class="modal fade" id="mdFont" tabindex="-1" aria-labelledby="mdlFont" aria-hidden="true">
<div class="modal-dialog"><div class="modal-content"><div class="modal-header">
<h1 class="modal-title fs-4" id="mdlFont">Upload font file</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div><div class="modal-body text-center">

<form action="<%= $SCRIPT_NAME %>" method="post" class="mb-4" enctype="multipart/form-data">
<% field_file "fontfile" "Upload a TTF file" %>
<% button_submit %></form>
</div></div></div></div>

<%in _preview.cgi %>

<script>
const soc = "<%= $soc_family %>";
const osdFontBasePath = "<%= $OSD_FONT_PATH %>";

const endpoint = '/x/json-prudynt.cgi';

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
	'audio_mic_agc_compression_gain_db': 0,
	'audio_mic_agc_target_level_dbfs': 10,
	'audio_mic_alc_gain': 0,
	'audio_mic_gain': 25,
	'audio_mic_noise_suppression': 0,
	'audio_mic_sample_rate':  16000,
	'audio_mic_vol': 80,
	'audio_spk_vol': 80,
	'audio_spk_gain': 25,
	'audio_spk_sample_rate': 16000,
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
const audio_params = [
	'mic_agc_compression_gain_db', 'mic_agc_enabled',
	'mic_agc_target_level_dbfs', 'mic_alc_gain', 'mic_bitrate',
	'mic_enabled', 'mic_format', 'mic_gain', 'mic_high_pass_filter',
	'mic_noise_suppression', 'mic_sample_rate', 'mic_vol',
	'spk_enabled', 'spk_vol', 'spk_gain', 'spk_sample_rate',
	'force_stereo', 'buffer_warn_frames', 'buffer_cap_frames'
];

// image
const image_params = [
	'ae_compensation', 'anti_flicker', 'backlight_compensation',
	'brightness', 'contrast', 'core_wb_mode', 'defog_strength',
	'dpc_strength', 'drc_strength', 'hflip', 'highlight_depress', 'hue',
	'max_again', 'max_dgain', 'running_mode', 'saturation', 'sharpness',
	'sinter_strength', 'temper_strength', 'vflip', 'wb_bgain', 'wb_rgain'
];

// motion
const motion_params = [
	'debounce_time', 'post_time', 'ivs_polling_timeout', 'cooldown_time',
	'init_time', 'min_time', 'sensitivity', 'skip_frame_count',
	'frame_width', 'frame_height', 'monitor_stream', 'roi_0_x', 'roi_0_y',
	'roi_1_x', 'roi_1_y', 'roi_count'
];

// stream [0, 1]
const stream_params = [
	'audio_enabled', 'bitrate', 'buffers', 'enabled', 'format', 'fps',
	'gop', 'height', 'max_gop', 'mode', 'profile', 'rtsp_endpoint', 'width'
];

// stream 2
const stream2_params = ['jpeg_channel'];

// OSD
const buildNullObject = (keys) => {
	const obj = {};
	keys.forEach((key) => { obj[key] = null; });
	return obj;
};

const buildStreamRequest = () => {
	const req = buildNullObject(stream_params);
	req.osd = {
		enabled: null,
		font_path: null,
		font_size: null,
		stroke_size: null,
		logo: { enabled: null },
		time: { enabled: null, format: null, fill_color: null, stroke_color: null },
		uptime: { enabled: null, format: null, fill_color: null, stroke_color: null },
		usertext: { enabled: null, format: null, fill_color: null, stroke_color: null }
	};
	return req;
};

let sts;

function rgba2color(hex8) {
	return hex8.substring(0, 7);
}

function rgba2alpha(hex8) {
	const alphaHex = hex8.substring(7, 9);
	const alpha = parseInt(alphaHex, 16);
	return alpha;
}

function updateColorInputs(streamIndex, elementKey, fillHex, strokeHex) {
	if (typeof fillHex === 'string' && fillHex.length >= 7) {
		const fillInput = $(`#osd${streamIndex}_${elementKey}_fillcolor`);
		if (fillInput) fillInput.value = rgba2color(fillHex);
		const fillAlphaInput = $(`#osd${streamIndex}_${elementKey}_fillcolor-alpha`);
		if (fillAlphaInput) fillAlphaInput.value = rgba2alpha(fillHex);
	}
	if (typeof strokeHex === 'string' && strokeHex.length >= 7) {
		const strokeInput = $(`#osd${streamIndex}_${elementKey}_strokecolor`);
		if (strokeInput) strokeInput.value = rgba2color(strokeHex);
		const strokeAlphaInput = $(`#osd${streamIndex}_${elementKey}_strokecolor-alpha`);
		if (strokeAlphaInput) strokeAlphaInput.value = rgba2alpha(strokeHex);
	}
}

function alphaToHex(value) {
	const numeric = Number(value);
	if (Number.isNaN(numeric)) return 'ff';
	return numeric.toString(16).padStart(2, '0');
}

function normalizeOsdElement(osd, key) {
	const nested = osd && osd[key] ? osd[key] : {};
	return {
		enabled: nested.enabled,
		format: nested.format,
		fill_color: nested.fill_color,
		stroke_color: nested.stroke_color
	};
}

function applyCheckbox(selector, value) {
	if (typeof value === 'undefined') return;
	const el = $(selector);
	if (el) el.checked = value;
}

function syncOsdTextElement(streamIndex, elementKey, config, withFormat = false) {
	if (!config) return;
	applyCheckbox(`#osd${streamIndex}_${elementKey}_enabled`, config.enabled);
	if (withFormat && typeof config.format !== 'undefined') {
		const input = $(`#osd${streamIndex}_${elementKey}_format`);
		if (input) input.value = config.format;
	}
	updateColorInputs(streamIndex, elementKey, config.fill_color, config.stroke_color);
}

function handleMessage(msg) {
	if (msg.action && msg.action.capture == 'initiated') return;

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
				const osd = data.osd;
				if (typeof osd.enabled !== 'undefined') {
					$(`#osd${i}_enabled`).checked = osd.enabled;
					toggleWrappers(i);
				}
				if (osd.font_path)
					$(`#osd${i}_fontname`).value = osd.font_path.split('/').reverse()[0];
				if (typeof osd.font_size !== 'undefined') {
					$(`#osd${i}_fontsize-show`).textContent = osd.font_size;
					$(`#osd${i}_fontsize`).value = osd.font_size;
				}
				if (typeof osd.stroke_size !== 'undefined') {
					$(`#osd${i}_strokesize-show`).textContent = osd.stroke_size;
					$(`#osd${i}_strokesize`).value = osd.stroke_size;
				}

				const logo = osd.logo || {};
				applyCheckbox(`#osd${i}_logo_enabled`, logo.enabled);

				syncOsdTextElement(i, 'time', normalizeOsdElement(osd, 'time'), true);
				syncOsdTextElement(i, 'uptime', normalizeOsdElement(osd, 'uptime'));
				syncOsdTextElement(i, 'usertext', normalizeOsdElement(osd, 'usertext'), true);
			}
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
}


async function loadConfig() {
	const payloadObj = {
		stream0: buildStreamRequest(),
		stream1: buildStreamRequest(),
		stream2: buildNullObject(stream2_params),
		audio: buildNullObject(audio_params),
		image: buildNullObject(image_params)
	};
	const payload = JSON.stringify(payloadObj);
	console.log('===>', payload);
	try {
		const response = await fetch(endpoint, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: payload
		});
		if (!response.ok) throw new Error(`HTTP ${response.status}`);
		const contentType = response.headers.get('content-type');
		if (contentType?.includes('application/json')) {
			const msg = await response.json();
			console.log(ts(), '<===', JSON.stringify(msg));
			handleMessage(msg);
		}
	} catch (err) {
		console.error('Load config error', err);
	}
}

async function sendToEndpoint(payload) {
	console.log(ts(), '===>', payload);
	try {
		const response = await fetch(endpoint, {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: payload
		});
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

function sendOsdUpdate(streamId, osdPayload, restartThread = 10) {
	const payload = {
		[`stream${streamId}`]: {
			osd: osdPayload
		}
	};
	if (restartThread) {
		payload.action = { restart_thread: restartThread };
	}
	sendToEndpoint(JSON.stringify(payload));
}

// n - stream #,
// el - osd element
function setFontColor(n, el) {
	const fillcolor = $(`#osd${n}_${el}_fillcolor`).value;
	const fillAlphaSlider = $(`#osd${n}_${el}_fillcolor-alpha`).value;
	const strokecolor = $(`#osd${n}_${el}_strokecolor`).value;
	const strokeAlphaSlider = $(`#osd${n}_${el}_strokecolor-alpha`).value;

	if (fillcolor === '' && strokecolor === '') return;
	const update = {};
	if (fillcolor !== '') {
		update.fill_color = `${fillcolor}${alphaToHex(fillAlphaSlider)}`;
	}
	if (strokecolor !== '') {
		update.stroke_color = `${strokecolor}${alphaToHex(strokeAlphaSlider)}`;
	}
	if (Object.keys(update).length)
		sendOsdUpdate(n, { [el]: update });
}

function setFont(n) {
	const fontSelect = $(`#osd${n}_fontname`);
	const fontSizeInput = $(`#osd${n}_fontsize`);
	const strokeSizeInput = $(`#osd${n}_strokesize`);
	if (!fontSelect || !fontSizeInput || !strokeSizeInput) return;

	const payload = {};
	const fontName = fontSelect.value;
	if (fontName)
		payload.font_path = `${osdFontBasePath}/${fontName}`;

	const fontSize = Number(fontSizeInput.value);
	if (!Number.isNaN(fontSize)) {
		payload.font_size = fontSize;
		$(`#osd${n}_fontsize-show`).textContent = fontSize;
	}

	const strokeSize = Number(strokeSizeInput.value);
	if (!Number.isNaN(strokeSize)) {
		payload.stroke_size = strokeSize;
		$(`#osd${n}_strokesize-show`).textContent = strokeSize;
	}

	if (Object.keys(payload).length === 0) return;
	sendOsdUpdate(n, payload);
}

function toggleOSDElement(el) {
	const stream_id = Number(el.id.substr(3, 1));
	if (Number.isNaN(stream_id)) return;
	const id = el.id.replace(/^osd[01]_/, '');
	if (!id.endsWith('_enabled')) return;
	const element = id.slice(0, -8);
	if (!element) return;
	sendOsdUpdate(stream_id, { [element]: { enabled: el.checked } });
}

function toggleWrappers(id) {
	const wrappers = $$(`#osd${id}_fontname_wrap,#osd${id}_fontsize_wrap,#osd${id}_fontfile_wrap`);
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
		if (name == 'mic_format') {
			if (value == '"G711A"' || value == '"G711U"') {
				payload += ',"mic_sample_rate":8000'
			} else if (value == '"G726"') {
				payload += ',"mic_sample_rate":16000'
			} else if (value == '"OPUS"') {
				payload += ',"mic_sample_rate":48000'
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
	sendToEndpoint('{"'+domain+'":{'+payload+json_actions+'}}');
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

$('#save-prudynt-config').addEventListener('click', ev => {
	sendToEndpoint('{"action":{"save_config":null}}');
});

$('#restart-audio').addEventListener('click', ev => {
	sendToEndpoint('{"action":{"restart_thread":' + ThreadAudio + '}}');
});

for (const i in [0, 1]) {
	$('#osd'+i+'_fontname').onchange = () => setFont(i);
	$('#osd'+i+'_fontsize').onchange = () => setFont(i);
	$('#osd'+i+'_strokesize').onchange = () => setFont(i);

	$('#osd'+i+'_enabled').onchange = (ev) => sendOsdUpdate(i, { enabled: ev.target.checked });
	$('#osd'+i+'_logo_enabled').onchange = (ev) => toggleOSDElement(ev.target);

	$('#osd'+i+'_time_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_time_fillcolor').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_fillcolor-alpha').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_strokecolor').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_strokecolor-alpha').onchange = () => setFontColor(i, 'time');
	$('#osd'+i+'_time_format').onchange = (ev) => sendOsdUpdate(i, { time: { format: ev.target.value } });

	$('#osd'+i+'_uptime_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_uptime_fillcolor').onchange = () => setFontColor(i, 'uptime');
	$('#osd'+i+'_uptime_fillcolor-alpha').onchange = () => setFontColor(i, 'uptime');
	$('#osd'+i+'_uptime_strokecolor').onchange = () => setFontColor(i, 'uptime');
	$('#osd'+i+'_uptime_strokecolor-alpha').onchange = () => setFontColor(i, 'uptime');

	$('#osd'+i+'_usertext_enabled').onchange = (ev) => toggleOSDElement(ev.target);
	$('#osd'+i+'_usertext_fillcolor').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_fillcolor-alpha').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_strokecolor').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_strokecolor-alpha').onchange = () => setFontColor(i, 'usertext');
	$('#osd'+i+'_usertext_format').onchange = (ev) => sendOsdUpdate(i, { usertext: { format: ev.target.value } });
}

$('#preview_source_0').addEventListener('click', () => { $('#preview').src='/x/ch0.mjpg' });
$('#preview_source_1').addEventListener('click', () => { $('#preview').src='/x/ch1.mjpg' });

loadConfig().then(() => { $('#preview').src = '/x/ch0.mjpg' });
</script>

<%in _footer.cgi %>
