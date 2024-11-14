#!/bin/haserl
<%in _common.cgi %>
<%in _icons.cgi %>
<%
page_title="Camera preview"
which motors > /dev/null && has_motors="true"
%>
<%in _header.cgi %>

<div class="row preview">
<div class="col-lg-1" style="width:5em">

<div class="d-flex flex-nowrap flex-lg-wrap align-content-around gap-1" aria-label="controls">

<input type="checkbox" class="btn-check" name="motionguard" id="motionguard" value="1">
<label class="btn btn-dark border mb-2" for="motionguard" title="Motion Guard"><img src="/a/motion.svg" alt="Motion Guard" class="img-fluid"></label>

<input type="checkbox" class="btn-check" name="r180" id="r180" value="1">
<label class="btn btn-dark border mb-2" for="r180" title="Rotate 180°"><img src="/a/r180.svg" alt="Rotate 180°" class="img-fluid"></label>

<input type="checkbox" class="btn-check imp" name="daynight" id="daynight" value="1">
<label class="btn btn-dark border mb-2" for="daynight" title="Night mode"><img src="/a/day_night_mode.svg" alt="Day/Night Mode" class="img-fluid"></label>

<input type="checkbox" class="btn-check" name="ispmode" id="ispmode" value="1"<% checked_if $(color ?) "day" %>>
<label class="btn btn-dark border mb-2" for="ispmode" title="Color mode"><img src="/a/color_mode.svg" alt="Color mode" class="img-fluid"></label>

<% if get gpio_ircut >/dev/null; then %>
<input type="checkbox" class="btn-check imp" name="ircut" id="ircut" value="1"<% checked_if $(ircut ?) 1 %>>
<label class="btn btn-dark border mb-2" for="ircut" title="IR filter"><img src="/a/ircut_filter.svg" alt="IR filter" class="img-fluid"></label>
<% fi %>
<% if get gpio_ir850 >/dev/null; then %>
<input type="checkbox" class="btn-check imp" name="ir850" id="ir850" value="1"<% checked_if $(irled ? ir850) 1 %>>
<label class="btn btn-dark border mb-2" for="ir850" title="IR LED 850 nm"><img src="/a/light_850nm.svg" alt="850nm LED" class="img-fluid"></label>
<% fi %>
<% if get gpio_ir940 >/dev/null; then %>
<input type="checkbox" class="btn-check imp" name="ir940" id="ir940" value="1"<% checked_if $(irled ? ir940) 1 %>>
<label class="btn btn-dark border mb-2" for="ir940" title="IR LED 940 nm"><img src="/a/light_940nm.svg" alt="940nm LED" class="img-fluid"></label>
<% fi %>
<% if get gpio_white >/dev/null; then %>
<input type="checkbox" class="btn-check imp" name="white" id="white" value="1"<% checked_if $(irled ? white) 1 %>>
<label class="btn btn-dark border mb-2 imp" for="white" title="White LED"><img src="/a/light_white.svg" alt="White light" class="img-fluid"></label>
<% fi %>
</div>
</div>
<div class="col-lg-9 mb-3">
<div id="frame" class="position-relative mb-2">
<img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Preview">
<% if [ "true" = "$has_motors" ]; then %><%in _motors.cgi %><% fi %>
</div>
<% if [ "true" = "$has_motors" ]; then %>
<p class="small">Move mouse cursor over the center of the preview image to reveal the motor controls.
Use a single click for precise positioning, double click for coarse, larger distance movement.</p>
<% fi %>

<div class="alert alert-secondary">
<p class="mb-0"><img src="/a/volume-mute.svg" alt="Icon: No Audio" class="float-start me-2" style="height:1.75rem" title="No Audio">
Please note, there is no audio on this page. Open the RTSP stream in a player to hear audio.</p>
<b id="playrtsp" class="cb"></b>
</div>

</div>
<div class="col-lg-2">
<div class="gap-2">
<div class="mb-1">
<a href="image.cgi" target="_blank" class="form-control btn btn-primary text-start">Save image</a>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="email">Email</button>
<div class="input-group-text"><a href="plugin-send2email.cgi" title="Email settings"><%= $icon_gear %></a></div>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="ftp">FTP</button>
<div class="input-group-text"><a href="plugin-send2ftp.cgi" title="FTP Storage settings"><%= $icon_gear %></a></div>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="telegram">Telegram</button>
<div class="input-group-text"><a href="plugin-send2telegram.cgi" title="Telegram bot settings"><%= $icon_gear %></a></div>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="mqtt">MQTT</button>
<div class="input-group-text"><a href="plugin-send2mqtt.cgi" title="MQTT settings"><%= $icon_gear %></a></div>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="webhook">WebHook</button>
<div class="input-group-text"><a href="plugin-send2webhook.cgi" title="Webhook settings"><%= $icon_gear %></a></div>
</div>
<div class="input-group mb-1">
<button class="form-control btn btn-primary text-start" type="button" data-sendto="yadisk">Yandex Disk</button>
<div class="input-group-text"><a href="plugin-send2yadisk.cgi" title="Yandex Disk bot settings"><%= $icon_gear %></a></div>
</div>
</div>
</div>
</div>

<script>
<%
[ "true" = "$email_enabled"    ] || echo "\$('button[data-sendto=email]').disabled = true;"
[ "true" = "$ftp_enabled"      ] || echo "\$('button[data-sendto=ftp]').disabled = true;"
[ "true" = "$mqtt_enabled"     ] || echo "\$('button[data-sendto=mqtt]').disabled = true;"
[ "true" = "$webhook_enabled"  ] || echo "\$('button[data-sendto=webhook]').disabled = true;"
[ "true" = "$telegram_enabled" ] || echo "\$('button[data-sendto=telegram]').disabled = true;"
[ "true" = "$yadisk_enabled"   ] || echo "\$('button[data-sendto=yadisk]').disabled = true;"
%>

$$("button[data-sendto]").forEach(el => {
	el.onclick = (ev) => {
		ev.preventDefault();
		if (!confirm("Are you sure?")) return false;
		fetch("/x/send.cgi?to=" + ev.target.dataset["sendto"])
		.then(res => res.json())
		.then(data => console.log(data))
	}
});

const preview = $("#preview");
preview.onload = function() { URL.revokeObjectURL(this.src) }
function updatePreview(data) {
	const blob = new Blob([data], {type: 'image/jpeg'});
	const url = URL.createObjectURL(blob);
	preview.src = url;
	ws.send('{"action":{"capture":null}}');
}

let ws = new WebSocket(`//${document.location.hostname}:8089?token=<%= $ws_token %>`);
ws.onopen = () => {
	console.log('WebSocket connection opened');
	ws.binaryType = 'arraybuffer';
	const payload = '{'+
		'"image":{"hflip":null,"vflip":null,"running_mode":null},'+
		'"motion":{"enabled":null},'+
		'"rtsp":{"username":null,"password":null,"port":null},'+
		'"stream0":{"rtsp_endpoint":null},'+
		'"action":{"capture":null}'+
		'}'
	console.log(ts(), '===>', payload);
	ws.send(payload);
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (err) => { console.error('WebSocket error', err); }
ws.onmessage = (ev) => {
	if (typeof ev.data == 'string') {
		if (ev.data == '') return;
		if (ev.data == '{"action":{"capture":"initiated"}}') return;
		console.log(ts(), '<===', ev.data);
		const msg = JSON.parse(ev.data);
		if (msg.image) {
			if (msg.image.hflip) $('#r180').checked = msg.image.hflip;
			if (msg.image.vflip) $('#r180').checked = msg.image.vflip;
			if (msg.image.running_mode) $('#ispmode').checked = (msg.image.running_mode == 0);
		}
		if (msg.motion) {
			if (msg.motion.enabled) $('#motionguard').checked = msg.motion.enabled;
		}
		if (msg.rtsp) {
			const r = msg.rtsp;
			if (r.username && r.password && r.port)
				$('#playrtsp').innerHTML = 'mpv --profile=fast ' +
					`rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
		}
	} else if (ev.data instanceof ArrayBuffer) {
		updatePreview(ev.data);
	}
}

function sendToWs(payload) {
	payload = payload.replace(/}$/, ',"action":{"save_config":null}}')
	console.log(ts(), '===>', payload);
	ws.send(payload);
}

$('#r180').onchange = (ev) => sendToWs(`{"image":{"hflip":${ev.target.checked},"vflip":${ev.target.checked}}}`);

// not .onchange because we need to catch the event here
$('#ispmode').addEventListener('change', (ev) => {
	const m = ev.target.checked ? '0' : '1'
	sendToWs(`{"image":{"running_mode":${m}}}`)
}, true);

$("#daynight").onchange = (ev) => {
	const leds = ["ir850", "ir940", "white"];
	if (ev.target.checked) {
		$("#ispmode").checked = false;
		$("#ircut").checked = false;
		leds.forEach((n) => {
			if ($(`#${n}`)) $(`#${n}`).checked = true
		});
		mode = "night";
	} else {
		$("#ispmode").checked = true;
		$("#ircut").checked = true;
		leds.forEach((n) => {
			if ($(`#${n}`)) $(`#${n}`).checked = false
		});
		mode = "day";
	}
}

$("#motionguard").addEventListener('change', (ev) => {
	sendToWs(`{"motion":{"enabled":${ev.target.checked}}}`);
});
</script>

<%in _footer.cgi %>
