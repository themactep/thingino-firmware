#!/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="On-Screen Display"
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

ts=$(date +%s)
FONTS=$(ls -1 $OSD_FONT_PATH)
%>
<%in _icons.cgi %>
<%in _header.cgi %>

<ul class="nav nav-underline mb-3" role="tablist">
<li class="nav-item" role="presentation"><a class="nav-link active" aria-current="page" href="#" data-bs-toggle="tab" data-bs-target="#main-tab-pane">Main stream</a></li>
<li class="nav-item" role="presentation"><a class="nav-link" href="#" data-bs-toggle="tab" data-bs-target="#sub-tab-pane">Substream</a></li>
<li class="nav-item" role="presentation"><a class="nav-link" href="#" data-bs-toggle="tab" data-bs-target="#upload-tab-pane">Upload font</a></li>
</ul>

<div class="tab-content" id="streamer-tabs">
<div class="tab-pane fade show active" id="main-tab-pane" role="tabpanel" aria-labelledby="home-tab" tabindex="0">
<div class="row">
<div class="col">
<% field_switch "osd0_enabled" "Enable main stream" %>
<div class="row g-1">
<div class="col-8"><% field_select "fontname0" "Font" "$FONTS" %></div>
<div class="col-4"><% field_range "fontsize0" "Font size" "10,80,1" %></div>
</div>
<div class="d-flex gap-3">
<% field_switch "osd0_logo_enabled" "Logo" %>
<% field_switch "osd0_time_enabled" "Time" %>
<% field_switch "osd0_uptime_enabled" "Uptime" %>
<% field_switch "osd0_user_text_enabled" "User text" %>
</div>
<div class="row g-1">
<div class="col col-4"><% field_color "fontcolor0" "Text color" %></div>
<div class="col col-4"><% field_color "fontstrokecolor0" "Shadow color" %></div>
<div class="col col-4"><% field_range "fontstrokesize0" "Shadow size" "0,100,1" %></div>
</div>
<div class="row g-1">
<div class="col col-4"><% field_text "osd0_time_format" "Time format" %></div>
</div>
</div>
<div class="col">
<div id="preview-wrapper" class="mb-4 position-relative">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
<button type="button" class="btn btn-primary btn-large position-absolute top-50 start-50 translate-middle" data-bs-toggle="modal" data-bs-target="#previewModal"><%= $icon_zoom %></button>
</div>
</div>
</div>
</div>
<div class="tab-pane fade" id="sub-tab-pane" role="tabpanel" aria-labelledby="profile-tab" tabindex="0">
<div class="row">
<div class="col">
<% field_switch "osd1_enabled" "Enable substream" %>
<div class="row g-1">
<div class="col col-8"><% field_select "fontname1" "Font" "$FONTS" %></div>
<div class="col col-4"><% field_range "fontsize1" "Font size" "10,80,1" %></div>
</div>
<div class="d-flex gap-3">
<% field_checkbox "osd1_logo_enabled" "Logo" %>
<% field_checkbox "osd1_time_enabled" "Time" %>
<% field_checkbox "osd1_uptime_enabled" "Uptime" %>
<% field_checkbox "osd1_user_text_enabled" "User Text" %>
</div>
<div class="row g-1">
<div class="col col-4"><% field_color "fontcolor1" "Color" %></div>
<div class="col col-4"><% field_range "fontstrokesize1" "Size" "0,100,1" %></div>
<div class="col col-4"><% field_color "fontstrokecolor1" "Color" %></div>
</div>
<div class="row g-1">
<% field_text "osd1_time_format" "Format" %>
</div>
</div>
<div class="col">
<div id="preview-sub-wrapper" class="mb-4 position-relative">
<img id="preview-sub" src="image.cgi?t=<%= $ts %>" alt="Image: Substream preview" class="img-fluid">
</div>
</div>
</div>
</div>
<div class="tab-pane fade" id="upload-tab-pane" role="tabpanel" aria-labelledby="profile-tab" tabindex="0">
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data" style="max-width:20rem">
<% field_file "fontfile" "Upload a TTF file" %>
<% button_submit %>
</form>
</div>
</div>

<div class="modal fade" id="previewModal" tabindex="-1" aria-labelledby="previewModalLabel" aria-hidden="true">
<div class="modal-dialog modal-fullscreen">
<div class="modal-content">
<div class="modal-header">
<h1 class="modal-title fs-4" id="previewModalLabel">Full screen preview</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body text-center">
<img id="preview_fullsize" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
</div>
</div>
</div>
</div>

<style>
#preview-wrapper button { visibility: hidden; }
#preview-wrapper:hover button { visibility: visible; }
</style>

<script>
const preview = $("#preview");
const previewModal = new bootstrap.Modal('#previewModal', {});
preview.onclick = () => { previewModal.show() }
preview.onload = function() { URL.revokeObjectURL(this.src) }

function ts() {
	return Math.floor(Date.now());
}

const params = ['enabled', 'font_color', 'font_path', 'font_size', 'font_stroke_color', 'font_stroke',
	'logo_enabled', 'time_enabled', 'time_format', 'uptime_enabled', 'user_text_enabled'];

let sts;
let ws = new WebSocket(`//${document.location.hostname}:8089?token=<%= $ws_token %>`);
ws.onopen = () => {
	console.log('WebSocket connection opened');
	stream_rq = '{"osd":{' + params.map((x) => `"${x}":null`).join() + '}}';
	const payload = `{"stream0":${stream_rq},"stream1":${stream_rq}}`;
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
		for (const i in [0, 1]) {
			data = msg[`stream${i}`];
			if (data) {
				if (data.osd) {
					//params.forEach(x => setValue(data, `stream${i}`, x));
					if (data.osd.enabled) {
						$(`#osd${i}_enabled`).checked = data.osd.enabled;
						toggleWrappers(i);
					}
					if (data.osd.font_color)
						$(`#fontcolor${i}`).value = data.osd.font_color.replace(/^0x../, '#');
					if (data.osd.font_path)
						$(`#fontname${i}`).value = data.osd.font_path.split('/').reverse()[0];
					if (data.osd.font_size) {
						$(`#fontsize${i}`).value = data.osd.font_size;
						$(`#fontsize${i}-show`).textContent = data.osd.font_size;
					}
					if (data.osd.font_stroke_color)
						$(`#fontstrokecolor${i}`).value = data.osd.font_stroke_color.replace(/^0x../, '#');
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
					if (data.osd.uptime_enabled)
						$(`#osd${i}_uptime_enabled`).checked = data.osd.uptime_enabled;
					if (data.osd.user_text_enabled)
						$(`#osd${i}_user_text_enabled`).checked = data.osd.user_text_enabled;
				}
			}
		}
	} else if (ev.data instanceof ArrayBuffer) {
		const blob = new Blob([ev.data], {type: 'image/jpeg'});
		const url = URL.createObjectURL(blob);
		preview.src = url;
		$("#preview_fullsize").src = url;
	}
}

const andSave = ',"action":{"save_config":null,"restart_thread":10}';

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
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

function setFont(n) {
	const fontname = $(`#fontname${n}`).value;
	const fontsize = $(`#fontsize${n}`).value;
	if (fontname == '' || fontsize == '') return;
	sendToWs(`{"stream${n}":{"osd":{"font_path":"/usr/share/fonts/${fontname}","font_size":${fontsize}}}}`);
}

function setFontColor(n) {
	const fontcolor = $(`#fontcolor${n}`).value.replace(/^#/, '');
	const fontstrokecolor = $(`#fontstrokecolor${n}`).value.replace(/^#/, '');
	const fontstrokesize = $(`#fontstrokesize${n}`).value;
	if (fontcolor == '' || fontstrokecolor == '') return;
	sendToWs(`{"stream${n}":{"osd":{"font_color":"0xff${fontcolor}","font_stroke_color":"0xff${fontstrokecolor}","font_stroke":${fontstrokesize}}}}`);
}

function toggleWrappers(id) {
	const wrappers = $$(`#fontname${id}_wrap,#fontsize${id}_wrap,#fontfile${id}_wrap`);
	if ($(`#osd${id}_enabled`).checked) {
		wrappers.forEach(el => el.classList.remove('d-none'));
	} else {
		wrappers.forEach(el => el.classList.add('d-none'));
	}
}

function toggleOSDElement(el) {
	const status = el.checked ? 'true' : 'false';
	const stream_id = el.id.substr(3, 1);
	const id = el.id.replace('osd0_', '').replace('osd1_', '');
	sendToWs(`{"stream${stream_id}":{"osd":{"${id}":${status}}}}`);
}

for (const i in [0, 1]) {
	$(`#fontcolor${i}`).onchange = () => setFontColor(i);
	$(`#fontname${i}`).onchange = () => setFont(i);
	$(`#fontsize${i}`).onchange = () => setFont(i);
	$(`#fontstrokecolor${i}`).onchange = () => setFontColor(i);
	$(`#fontstrokesize${i}`).onchange = () => setFontColor(i);
	$(`#osd${i}_enabled`).onchange = (ev) => sendToWs(`{"stream${i}":{"osd":{"enabled":${ev.target.checked}}}}`);
	$(`#osd${i}_logo_enabled`).onchange = (ev) => toggleOSDElement(ev.target);
	$(`#osd${i}_time_enabled`).onchange = (ev) => toggleOSDElement(ev.target);
	$(`#osd${i}_time_format`).onchange = (ev) => sendToWs(`{"stream${i}":{"osd":{"time_format":"${ev.target.value}"}}}`);
	$(`#osd${i}_uptime_enabled`).onchange = (ev) => toggleOSDElement(ev.target);
	$(`#osd${i}_user_text_enabled`).onchange = (ev) => toggleOSDElement(ev.target);
}
</script>

<%in _footer.cgi %>
