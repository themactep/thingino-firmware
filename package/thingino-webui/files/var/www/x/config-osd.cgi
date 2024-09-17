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

<div class="row mb-4">
<div class="col col-12 col-lg-6 mb-4">

<div class="card mb-3">
	<div class="card-header">
		<% field_switch "osd0_enabled" "Main stream" %>
	</div>
	<div class="card-body">
		<div class="row">
			<div class="col col-8"><% field_select "fontname0" "Font" "$FONTS" %></div>
			<div class="col col-4"><% field_range "fontsize0" "Font size" "10,80,1" %></div>
		</div>
		<div class="d-flex gap-3">
			<% field_checkbox "osd0_logo_enabled" "Logo" %>
			<% field_checkbox "osd0_time_enabled" "Time" %>
			<% field_checkbox "osd0_user_text_enabled" "User Text" %>
			<% field_checkbox "osd0_uptime_enabled" "Uptime" %>
		</div>
	</div>
</div>
<div class="card mb-3">
	<div class="card-header">
		<% field_switch "osd1_enabled" "Sub stream" %>
	</div>
	<div class="card-body">
		<div class="row">
			<div class="col col-8"><% field_select "fontname1" "Font" "$FONTS" %></div>
			<div class="col col-4"><% field_range "fontsize1" "Font size" "10,80,1" %></div>
		</div>
		<div class="d-flex gap-3">
			<% field_checkbox "osd1_logo_enabled" "Logo" %>
			<% field_checkbox "osd1_time_enabled" "Time" %>
			<% field_checkbox "osd1_user_text_enabled" "User Text" %>
			<% field_checkbox "osd1_uptime_enabled" "Uptime" %>
		</div>
	</div>
</div>
<button type="button" class="btn btn-primary" data-bs-toggle="modal" data-bs-target="#fontModal">Upload a font</button>
</div>

<div class="col col-12 col-lg-6">
<div id="preview-wrapper" class="mb-4 position-relative">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
<button type="button" class="btn btn-primary btn-large position-absolute top-50 start-50 translate-middle" data-bs-toggle="modal" data-bs-target="#previewModal"><%= $icon_zoom %></button>
</div>
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

<div class="modal fade" id="fontModal" tabindex="-1" aria-labelledby="fontModalLabel" aria-hidden="true">
<div class="modal-dialog">
<div class="modal-content">
<div class="modal-header">
<h1 class="modal-title fs-4" id="fontModalLabel">Upload a font file</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body text-center">
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data">
<% field_file "fontfile" "Upload a TTF file" %>
<% button_submit %>
</form>
</div>
</div>
</div>
</div>

<style>
#preview-wrapper button { visibility: hidden; }
#preview-wrapper:hover button { visibility: visible; }
</style>

<script>
const previewModal = new bootstrap.Modal('#previewModal', {});
$('#preview').addEventListener('click', ev => {
	previewModal.show();
});

function ts() {
	return Math.floor(Date.now());
}

const OSD_THREAD = 2;
let sts;

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	stream_rq='"osd":{'+
		'"enabled":null,'+
		'"font_path":null,'+
		'"font_size":null,'+
		'"logo_enabled":null,'+
		'"time_enabled":null,'+
		'"uptime_enabled":null,'+
		'"user_text_enabled":null'+
		'}';
	const payload = '{"stream0":{' +
		stream_rq +
		'},"stream1":{' +
		stream_rq +
		'}}';
	console.log(payload);
	ws.send(payload);
	sts = setTimeout(getSnapshot, 1000);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (error) => { console.error('WebSocket error', error); }
ws.onmessage = (event) => {
	if (typeof event.data === 'string') {
		if (event.data == '') {
			console.log('empty response');
			return;
		} else {
			console.log(ts(), '<===', event.data);
		}
		const msg = JSON.parse(event.data);
		const time = new Date(msg.date);
		const timeStr = time.toLocaleTimeString();
		if (msg.stream0) {
			if (msg.stream0.osd.enabled) {
				$('#osd0_enabled').checked = msg.stream0.osd.enabled;
				toggleWrappers(0);
			}

			if (msg.stream0.osd.font_path)
				$('#fontname0').value = msg.stream0.osd.font_path.split('/').reverse()[0];

			if (msg.stream0.osd.font_size) {
				$('#fontsize0').value = msg.stream0.osd.font_size;
				$('#fontsize0-show').value = msg.stream0.osd.font_size;
			}

			if (msg.stream0.osd.logo_enabled)
				$('#osd0_logo_enabled').checked = msg.stream0.osd.logo_enabled;

			if (msg.stream0.osd.time_enabled)
				$('#osd0_time_enabled').checked = msg.stream0.osd.time_enabled;

			if (msg.stream0.osd.uptime_enabled)
				$('#osd0_uptime_enabled').checked = msg.stream0.osd.uptime_enabled;

			if (msg.stream0.osd.user_text_enabled)
				$('#osd0_user_text_enabled').checked = msg.stream0.osd.user_text_enabled;

		}
		if (msg.stream1) {
			if (msg.stream1.osd.enabled) {
				$('#osd1_enabled').checked = msg.stream1.osd.enabled;
				toggleWrappers(1);
			}

			if (msg.stream1.osd.font_path)
				$('#fontname1').value = msg.stream1.osd.font_path.split('/').reverse()[0];

			if (msg.stream1.osd.font_size) {
				$('#fontsize1').value = msg.stream1.osd.font_size;
				$('#fontsize1-show').value = msg.stream1.osd.font_size;
			}

			if (msg.stream1.osd.logo_enabled)
				$('#osd1_logo_enabled').checked = msg.stream1.osd.logo_enabled;

			if (msg.stream1.osd.time_enabled)
				$('#osd1_time_enabled').checked = msg.stream1.osd.time_enabled;

			if (msg.stream1.osd.uptime_enabled)
				$('#osd1_uptime_enabled').checked = msg.stream1.osd.uptime_enabled;

			if (msg.stream1.osd.user_text_enabled)
				$('#osd1_user_text_enabled').checked = msg.stream1.osd.user_text_enabled;
		}

	} else if (event.data instanceof ArrayBuffer) {
		const blob = new Blob([event.data], {type: 'image/jpeg'});
		const url = URL.createObjectURL(blob);
		$("#preview").src = url;
		$("#preview_fullsize").src = url
	}
}

const andSave = ',"action":{"save_config":null,"restart_thread":'+OSD_THREAD+'}'

function sendToWs(payload) {
	payload = payload.replace(/}$/, andSave + '}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

function getSnapshot() {
	clearTimeout(sts);
	ws.binaryType = 'arraybuffer';
	const payload = '{"action":{"capture":null}}';
	console.log(ts(), "===>", payload);
	ws.send(payload);
	sts = setTimeout(getSnapshot, 500);
}

function setFont(n) {
	let fontname = $('#fontname'+n).value;
	if (fontname == '') {
		console.log("Font name seems empty.");
		return;
	}

	let fontsize = $('#fontsize'+n).value;
	if (fontsize == '') {
		console.log("Font size seems empty.");
		return;
	}

	sendToWs('{"stream' + n + '":{"osd":{'+
		'"font_path":"/usr/share/fonts/' + fontname + '",'+
		'"font_size":'+ fontsize + '}}}');
}

function toggleWrappers(id) {
	const wrappers = $$('#fontname'+id+'_wrap,#fontsize'+id+'_wrap,#fontfile'+id+'_wrap');
	if ($('#osd'+id+'_enabled').checked) {
		wrappers.forEach(el => el.classList.remove('d-none'));
	} else {
		wrappers.forEach(el => el.classList.add('d-none'));
	}
}

function toggleOSDElement(el) {
	const status = el.checked ? 'true' : 'false';
	const stream_id = el.id.substr(3, 1);
	const id = el.id.replace('osd0_', '').replace('osd1_', '');
	sendToWs('{"stream' + stream_id + '":{"osd":{"' + id + '":' + status + '}}}');
}

$('#osd0_enabled').addEventListener('change', ev => {
	const status = ev.target.checked ? 'true' : 'false';
	sendToWs('{"stream0":{"osd":{"enabled":'+status+'}}}');
});
$('#fontname0').addEventListener('change', () => setFont(0));
$('#fontsize0').addEventListener('change', () => setFont(0));

$('#osd0_logo_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd0_time_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd0_uptime_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd0_user_text_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));

$('#osd1_enabled').addEventListener('change', ev => {
	const status = ev.target.checked ? 'true' : 'false';
	sendToWs('{"stream1":{"osd":{"enabled":'+status+'}}}');
});
$('#fontname1').addEventListener('change', () => setFont(1));
$('#fontsize1').addEventListener('change', () => setFont(1));

$('#osd1_logo_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd1_time_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd1_uptime_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
$('#osd1_user_text_enabled').addEventListener('change', ev => toggleOSDElement(ev.target));
</script>

<%in _footer.cgi %>
