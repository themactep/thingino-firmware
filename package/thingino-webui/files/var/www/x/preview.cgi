#!/bin/haserl
<%in _common.cgi %>
<%in _icons.cgi %>
<%
token="$(cat /run/prudynt_websocket_token)"
page_title="Camera preview"
rtsp_address=$network_address
rtsp_username="$(sed -En '/^rtsp:/n/username:/{s/^.+username:\s\"(.+)";/\1/p}' /etc/prudynt.cfg)"
rtsp_password="$(sed -En '/^rtsp:/n/password:/{s/^.+password:\s\"(.+)";/\1/p}' /etc/prudynt.cfg)"
#rtsp_port="$(sed -En '/^rtsp:/n/port:/{s/^.+port:\s(.+);/\1/p}' /etc/prudynt.cfg)"
#[ "$rtsp_port" == "554" ] && rtsp_port="" || rtsp_port=":$rtsp_port"
#rtsp_url="rtsp://${rtsp_username}:${rtsp_password}@${rtsp_address}${rtsp_port}/ch0"
rtsp_url="rtsp://${rtsp_username}:${rtsp_password}@${rtsp_address}/ch0"

for i in "ispmode"; do
	eval "$i=\"$(/usr/sbin/imp-control $i)\""
done

check_flip() {
	[ $flip -eq 2 ] || [ $flip -eq 3 ] && echo -n " checked"
}

check_mirror() {
	[ $flip -eq 1 ] || [ $flip -eq 3 ] && echo -n " checked"
}
%>
<%in _header.cgi %>

<div class="row preview">
	<div class="col-12 mb-3">
		<div id="frame" class="position-relative mb-2">
			<div class="smpte">
				<div class="bar1"></div>
				<div class="bar2"></div>
				<div class="bar3"></div>
			</div>
			<img id="preview" class="img-fluid" alt="Image: Preview"></img>
			<%in _motors.cgi %>
			<div id="controls" class="position-absolute bottom-0 start-0 end-0">
				<div class="buttons btn-group d-flex" role="group" aria-label="Night Mode">
					<input type="checkbox" class="btn-check" name="daynight" id="daynight" value="1"<% checked_if $daynight 1 %>>
					<label class="btn btn-dark" for="daynight" title="Night mode"><%= $icon_moon %></label>
					<input type="checkbox" class="btn-check" name="ispmode" id="ispmode" value="1"<% checked_if $ispmode 1 %>>
					<label class="btn btn-sm btn-dark" for="ispmode" title="Color mode"><%= $icon_color %></label>
					<input type="checkbox" class="btn-check" name="ircut" id="ircut" value="1"<% checked_if $ircut 1 %><% get gpio_ircut >/dev/null || echo " disabled" %>>
					<label class="btn btn-sm btn-dark" for="ircut" title="IR filter"><%= $icon_ircut %></label>
					<input type="checkbox" class="btn-check" name="ir850" id="ir850" value="1"<% checked_if $ir850 1 %><% get gpio_ir850 >/dev/null || echo " disabled" %>>
					<label class="btn btn-sm btn-dark" for="ir850" title="IR LED 850 nm"><%= $icon_ir850 %></label>
					<input type="checkbox" class="btn-check" name="ir940" id="ir940" value="1"<% checked_if $ir940 1 %><% get gpio_ir940 >/dev/null || echo " disabled" %>>
					<label class="btn btn-sm btn-dark" for="ir940" title="IR LED 940 nm"><%= $icon_ir940 %></label>
					<input type="checkbox" class="btn-check" name="white" id="white" value="1"<% checked_if $white 1 %><% get gpio_white >/dev/null || echo " disabled" %>>
					<label class="btn btn-sm btn-dark" for="white" title="White LED"><%= $icon_white %></label>
					<input type="checkbox" class="btn-check" name="flip" id="flip" value="1"<% check_flip %>>
					<label class="btn btn-sm btn-dark" for="flip" title="Flip vertically"><%= $icon_flip %></label>
					<input type="checkbox" class="btn-check" name="mirror" id="mirror" value="1"<% check_mirror %>>
					<label class="btn btn-sm btn-dark" for="mirror" title="Flip horizontally"><%= $icon_flop %></label>
				</div>
			</div>
		</div>
		<p class="small text-body-secondary">Use an RTSP media player instead, e.g. <span class="text-white">mpv --profile=low-latency <%= $rtsp_url %></span>.
			<br>Move the cursor over the center of the preview image to reveal the motor controls. Use a single click for precise positioning, double click for coarse, long-distance movement.
		</p>
	</div>
	<div class="col-12">
		<div class="d-flex flex-column flex-lg-row gap-2 mb-3">
			<a href="image.cgi" target="_blank" class="form-control btn btn-primary text-start">Save image</a>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="email">Email</button>
				<div class="input-group-text"><a href="plugin-send2email.cgi" title="Email settings"><%= $icon_gear %></a></div>
			</div>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="ftp">FTP</button>
				<div class="input-group-text"><a href="plugin-send2ftp.cgi" title="FTP Storage settings"><%= $icon_gear %></a></div>
			</div>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="telegram">Telegram</button>
				<div class="input-group-text"><a href="plugin-send2telegram.cgi" title="Telegram bot settings"><%= $icon_gear %></a></div>
			</div>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="mqtt">MQTT</button>
				<div class="input-group-text"><a href="plugin-send2mqtt.cgi" title="MQTT settings"><%= $icon_gear %></a></div>
			</div>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="webhook">WebHook</button>
				<div class="input-group-text"><a href="plugin-send2webhook.cgi" title="Webhook settings"><%= $icon_gear %></a></div>
			</div>
			<div class="input-group">
				<button class="form-control btn btn-primary text-start" type="button" data-sendto="yadisk">Yandex Disk</button>
				<div class="input-group-text"><a href="plugin-send2yadisk.cgi" title="Yandex Disk bot settings"><%= $icon_gear %></a></div>
			</div>
		</div>
	</div>
</div>

<script src="/a/imp-config.js"></script>
<script>
const network_address = "<%= $network_address %>";

<% [ "true" != "$email_enabled"    ] && echo "\$('button[data-sendto=email]').disabled = true;" %>
<% [ "true" != "$ftp_enabled"      ] && echo "\$('button[data-sendto=ftp]').disabled = true;" %>
<% [ "true" != "$mqtt_enabled"     ] && echo "\$('button[data-sendto=mqtt]').disabled = true;" %>
<% [ "true" != "$webhook_enabled"  ] && echo "\$('button[data-sendto=webhook]').disabled = true;" %>
<% [ "true" != "$telegram_enabled" ] && echo "\$('button[data-sendto=telegram]').disabled = true;" %>
<% [ "true" != "$yadisk_enabled"   ] && echo "\$('button[data-sendto=yadisk]').disabled = true;" %>

$$("button[data-sendto]").forEach(el => {
	el.addEventListener("click", ev => {
		ev.preventDefault();
		if (!confirm("Are you sure?")) return false;
		const tgt = ev.target.dataset["sendto"];
		xhrGet("/x/send.cgi?to=" + tgt);
	});
});

function capture() { ws.send('{"action":{"capture":null}}'); }

const jpg = $("#preview");
const ws_url = 'ws://' + document.location.hostname + ':8089?token=<%= $token %>';
let ws = new WebSocket(ws_url);
ws.binaryType = 'arraybuffer';
ws.onopen  = () => capture();
ws.onclose = () => console.log('WebSocket connection closed');
ws.onerror = (error) => console.error('WebSocket error', error);
ws.onmessage = (event) => {
	if (typeof event.data === 'string') {
		const msg = JSON.parse(event.data);
		const time = new Date(msg.date);
		const timeStr = time.toLocaleTimeString();
	} else if (event.data instanceof ArrayBuffer) {
		const blob = new Blob([event.data], {type: 'image/jpeg'});
		const url = URL.createObjectURL(blob);
		jpg.src = url;
		capture();
	}
}

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

<style>
#controls div.buttons { background: #88888888; visibility: hidden; width: 100%; height: 100%; }
#controls:hover div.buttons { visibility: visible; }
</style>

<%in _footer.cgi %>
