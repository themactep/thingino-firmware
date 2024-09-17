#!/bin/haserl
<%in _common.cgi %>
<%in _icons.cgi %>
<%
page_title="Camera preview"
which motors > /dev/null && has_motors="true"
%>
<%in _header.cgi %>

<div class="row preview">
<div class="col-lg-1" style="width:4em">

<div class="d-flex flex-nowrap flex-lg-wrap align-content-around" aria-label="Day/Night controls">
<input type="checkbox" class="btn-check" name="daynight" id="daynight" value="1">
<label class="btn btn-dark border mb-2" for="daynight" title="Night mode"><%= $icon_moon %></label>
<input type="checkbox" class="btn-check" name="ispmode" id="ispmode" value="1">
<label class="btn btn-dark border mb-2" for="ispmode" title="Color mode"><%= $icon_color %></label>
<input type="checkbox" class="btn-check" name="ircut" id="ircut" value="1"<% checked_if $ircut 1 %><% get gpio_ircut >/dev/null || echo " disabled" %>>
<label class="btn btn-dark border mb-2" for="ircut" title="IR filter"><%= $icon_ircut %></label>
<input type="checkbox" class="btn-check" name="ir850" id="ir850" value="1"<% checked_if $ir850 1 %><% get gpio_ir850 >/dev/null || echo " disabled" %>>
<label class="btn btn-dark border mb-2" for="ir850" title="IR LED 850 nm"><%= $icon_ir850 %></label>
<input type="checkbox" class="btn-check" name="ir940" id="ir940" value="1"<% checked_if $ir940 1 %><% get gpio_ir940 >/dev/null || echo " disabled" %>>
<label class="btn btn-dark border mb-2" for="ir940" title="IR LED 940 nm"><%= $icon_ir940 %></label>
<input type="checkbox" class="btn-check" name="white" id="white" value="1"<% checked_if $white 1 %><% get gpio_white >/dev/null || echo " disabled" %>>
<label class="btn btn-dark border mb-2" for="white" title="White LED"><%= $icon_white %></label>
<input type="checkbox" class="btn-check" name="vflip" id="vflip" value="1">
<label class="btn btn-dark border mb-2" for="vflip" title="Flip vertically"><%= $icon_flip %></label>
<input type="checkbox" class="btn-check" name="hflip" id="hflip" value="1">
<label class="btn btn-dark border mb-2" for="hflip" title="Flip horizontally"><%= $icon_flop %></label>
</div>
</div>
<div class="col-lg-9 mb-3">
<div id="frame" class="position-relative mb-2">
<img id="preview" class="img-fluid" alt="Image: Preview">
<% if [ "true" = "$has_motors" ]; then %><%in _motors.cgi %><% fi %>
</div>
<% if [ "true" = "$has_motors" ]; then %>
<p class="small">Move mouse cursor over the center of the preview image to reveal the motor controls. Use a single click for precise positioning, double click for coarse, larger distance movement.</p>
<% fi %>
<p class="small"><span id="playrtsp"></span></p>
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
[ "true" != "$email_enabled"    ] && echo "\$('button[data-sendto=email]').disabled = true;"
[ "true" != "$ftp_enabled"      ] && echo "\$('button[data-sendto=ftp]').disabled = true;"
[ "true" != "$mqtt_enabled"     ] && echo "\$('button[data-sendto=mqtt]').disabled = true;"
[ "true" != "$webhook_enabled"  ] && echo "\$('button[data-sendto=webhook]').disabled = true;"
[ "true" != "$telegram_enabled" ] && echo "\$('button[data-sendto=telegram]').disabled = true;"
[ "true" != "$yadisk_enabled"   ] && echo "\$('button[data-sendto=yadisk]').disabled = true;"
%>

$$("button[data-sendto]").forEach(el => {
	el.addEventListener("click", ev => {
		ev.preventDefault();
		if (!confirm("Are you sure?")) return false;
		const xhr = new XMLHttpRequest();
		xhr.open('GET', "/x/send.cgi?to=" + ev.target.dataset["sendto"]);
		xhr.send();
	});
});

function updatePreview(data) {
	const blob = new Blob([data], {type: 'image/jpeg'});
	const url = URL.createObjectURL(blob);
	jpg.src = url;

	ws.send('{"action":{"capture":null}}');
}

const jpg = $("#preview");

let ws = new WebSocket('ws://' + document.location.hostname + ':8089?token=<%= $ws_token %>');
ws.onopen = () => {
	console.log('WebSocket connection opened');
	ws.binaryType = 'arraybuffer';
	ws.send('{"image":{"hflip":null,"vflip":null,"running_mode":null},"rtsp":{"username":null,"password":null,"port":null},"action":{"capture":null}}');
}
ws.onclose = () => { console.log('WebSocket connection closed'); }
ws.onerror = (error) => { console.error('WebSocket error', error); }
ws.onmessage = (event) => {
	if (typeof event.data === 'string') {
		const msg = JSON.parse(event.data);
		const time = new Date(msg.date);
		const timeStr = time.toLocaleTimeString();

		if (msg.image) {
			console.log(event.data);
			if (msg.image.hflip)
				$('#hflip').checked = msg.image.hflip;
			if (msg.image.vflip)
				$('#vflip').checked = msg.image.vflip;
			if (msg.image.running_mode)
				$('#ispmode').checked = (msg.image.running_mode == 0);
		}

		if (msg.rtsp)
			if (msg.rtsp.username && msg.rtsp.password && msg.rtsp.port)
				$('#playrtsp').innerHTML = "RTSP player: mpv --profile=fast rtsp://" +
					msg.rtsp.username + ":" + msg.rtsp.password + "@" +
					document.location.hostname + ":" + msg.rtsp.port + "/ch0";

	} else if (event.data instanceof ArrayBuffer) {
		updatePreview(event.data);
	}
}

const andSave = ',"action":{"save_config":null}'

$('#hflip').addEventListener('change', ev => {
	ws.send('{"image":{"hflip":' + ev.target.checked + '}'+andSave+'}')
});
$('#vflip').addEventListener('change', ev => {
	ws.send('{"image":{"vflip":' + ev.target.checked + '}'+andSave+'}')
});
$('#ispmode').addEventListener('change', ev => {
	console.log('changes!')
	const m = ev.target.checked ? '0' : '1'
	ws.send('{"image":{"running_mode":' + m + '}' + andSave + '}')
}, true);

$("#daynight")?.addEventListener("change", ev => {
	if (ev.target.checked) {
		$("#ispmode").checked = false;
		$("#ircut").checked = false;
		["ir850", "ir940", "white"].forEach(n => $("#" + n).checked = true)
		mode = "night";
	} else {
		$("#ispmode").checked = true;
		$("#ircut").checked = true;
		["ir850", "ir940", "white"].forEach(n => $("#" + n).checked = false)
		mode = "day";
	}
});
</script>

<%in _footer.cgi %>
