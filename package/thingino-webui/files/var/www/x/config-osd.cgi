#!/bin/haserl --upload-limit=1024 --upload-dir=/tmp
<%in _common.cgi %>
<%in _icons.cgi %>
<%
page_title="OSD Fonts"

token="$(cat /run/prudynt_websocket_token)"

OSD_CONFIG="/etc/prudynt.cfg"
OSD_FONT_PATH="/usr/share/fonts"
FONT_REGEXP="s/(#\s*)?font_path:(.+);/font_path: \"${OSD_FONT_PATH//\//\\/}\/\%s\";/"

FONTS=$(ls -1 $OSD_FONT_PATH)

if [ "POST" = "$REQUEST_METHOD" ]; then
	error=""
	if [ -n "$HASERL_fontfile_path" ] && [ $(stat -c%s $HASERL_fontfile_path) -gt 0 ]; then
		fontname="uploaded.ttf"
		mv "$HASERL_fontfile_path" "$OSD_FONT_PATH/$fontname"
		sed -ri "$(printf "$FONT_REGEXP" "$fontname")" /etc/prudynt.cfg
		need_to_reload="true"
	else
		echo "File upload failed. No font selected." > /root/fontname
		set_error_flag "File upload failed. No font selected."
	fi
fi
%>
<%in _header.cgi %>
<% if [ "true" = "$need_to_reload" ]; then %>
<h3>Restarting Prudynt</h3>
<h4>Please wait...</h4>
<progress max="2" value="0"></progress>
<script>
const p=document.querySelector('progress'); let s=0;
function t(){s+=1;p.value=s;(s===p.max)?g():setTimeout(t,1000);}
function g(){window.location.replace(window.location);}
setTimeout(t, 2000);
</script>
<%
	/etc/init.d/S95prudynt restart &
else
	ts=$(date +%s)
%>
<div class="row mb-4">
<div class="col col-12 col-lg-6 mb-4">
<form action="<%= $SCRIPT_NAME %>" method="post" enctype="multipart/form-data">
<h5>Main stream</h5>
<div class="row">
<div class="col col-6 col-lg-12"><% field_select "fontname0" "Select a font" "$FONTS" %></div>
<div class="col col-6 col-lg-12"><% field_file "fontfile0" "Upload a TTF file" %></div>
</div>
<h5>Sub stream</h5>
<div class="row">
<div class="col col-6 col-lg-12"><% field_select "fontname1" "Select a font" "$FONTS" %></div>
<div class="col col-6 col-lg-12"><% field_file "fontfile1" "Upload a TTF file" %></div>
</div>
<% button_submit %>
</form>
</div>
<div class="col col-12 col-lg-6">
<div id="preview-wrapper" class="mb-4 position-relative">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
<button type="button" class="btn btn-primary btn-large position-absolute top-50 start-50 translate-middle" data-bs-toggle="modal" data-bs-target="#previewModal"><%= $icon_zoom %></button>
</div>
<div class="modal fade" id="previewModal" tabindex="-1" aria-labelledby="previewModalLabel" aria-hidden="true">
<div class="modal-dialog modal-fullscreen">
<div class="modal-content">
<div class="modal-header">
<h1 class="modal-title fs-4" id="previewModalLabel">Full screen preview</h1>
<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
</div>
<div class="modal-body text-center">
<img id="preview" src="image.cgi?t=<%= $ts %>" alt="Image: Preview" class="img-fluid">
</div>
</div>
</div>
</div>
</div>
</div>

<script>
const previewModal = new bootstrap.Modal('#previewModal', {});
$('#preview').addEventListener('click', ev => {
	previewModal.show();
});
</script>
<% fi %>

<style>
#preview-wrapper button { visibility: hidden; }
#preview-wrapper:hover button { visibility: visible; }
</style>

<script>
const jpg = $("#preview");

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	ws.send('{"stream0":{"osd":{"font_path":null}},"stream1":{"osd":{"font_path":null}}}');
}
ws.onclose = () => {
	console.log('WebSocket connection closed');
	connectWs();
}
ws.onerror = (error) => { console.error('WebSocket error', error); }
ws.onmessage = (event) => {
	if (typeof event.data === 'string') {
		const msg = JSON.parse(event.data);
		const time = new Date(msg.date);
		const timeStr = time.toLocaleTimeString();
		if (msg.stream0) $('#fontname0').value = msg.stream0.osd.font_path.split('/').reverse()[0];
		if (msg.stream1) $('#fontname1').value = msg.stream1.osd.font_path.split('/').reverse()[0];
	} else if (event.data instanceof ArrayBuffer) {
		const blob = new Blob([event.data], {type: 'image/jpeg'});
		const url = URL.createObjectURL(blob);
		jpg.src = url;
	}
}

function connectWs() {
	 ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $token %>');
}

function getSnapshot() {
	ws.binaryType = 'arraybuffer';
	ws.send('{"action":{"capture":null}}');
}

function reloadConfig() {
	ws.send('{"action":{"restart_thread":2}}');
	getSnapshot();
}

function saveConfig() {
	ws.send('{"action":{"save_config":null}}');
	reloadConfig();
}

function setFont(n) {
	let fontname = $('#fontname'+n).value;
	if (fontname == '') {
		console.log("Font name seems empty.");
		return;
	}
	payload = '{"stream' + n + '":{"osd":{"font_path":"/usr/share/fonts/' + fontname + '"}}}';
	console.log(payload);
	ws.send(payload);
	saveConfig();
}

$('#fontname0').addEventListener('change', () => setFont(0));
$('#fontname1').addEventListener('change', () => setFont(1));
</script>

<%in _footer.cgi %>
