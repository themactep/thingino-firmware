#!/usr/bin/haserl
<%in p/common.cgi %>
<%in p/icons.cgi %>
<%
page_title="Camera preview"
rtsp_address=$network_address
rtsp_username="$(sed -En '/^rtsp:/n/username:/{s/^.+username:\s\"(.+)";/\1/p}' /etc/prudynt.cfg)"
rtsp_password="$(sed -En '/^rtsp:/n/password:/{s/^.+password:\s\"(.+)";/\1/p}' /etc/prudynt.cfg)"
rtsp_port="$(sed -En '/^rtsp:/n/port:/{s/^.+port:\s(.+);/\1/p}' /etc/prudynt.cfg)"
[ "$rtsp_port" == "554" ] && rtsp_port="" || rtsp_port=":$rtsp_port"
rtsp_url="rtsp://${rtsp_username}:${rtsp_password}@${rtsp_address}${rtsp_port}/ch0"

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
<%in p/header.cgi %>

<div class="row preview">
	<div class="col-12 mb-3">
		<div id="frame" class="position-relative mb-2">
			<div class="smpte">
				<div class="bar1"></div>
				<div class="bar2"></div>
				<div class="bar3"></div>
			</div>
			<img id="preview" class="img-fluid" alt="Image: Preview"></img>
			<%in p/motors.cgi %>
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
					<input type="checkbox" class="btn-check" name="whled" id="whled" value="1"<% checked_if $whled 1 %><% get gpio_whled >/dev/null || echo " disabled" %>>
					<label class="btn btn-sm btn-dark" for="whled" title="White LED"><%= $icon_white %></label>
					<input type="checkbox" class="btn-check" name="flip" id="flip" value="1"<% check_flip %>>
					<label class="btn btn-sm btn-dark" for="flip" title="Flip vertically"><%= $icon_flip %></label>
					<input type="checkbox" class="btn-check" name="mirror" id="mirror" value="1"<% check_mirror %>>
					<label class="btn btn-sm btn-dark" for="mirror" title="Flip horizontally"><%= $icon_flop %></label>
				</div>
			</div>
		</div>
		<p class="small text-body-secondary">The image above refreshes once per second and may appear choppy.
			Use RTSP media player instead, e.g. <span class="text-white">mpv --profile=low-latency <%= $rtsp_url %></span>.
			<br>Move the cursor over the center of the preview image to reveal the motor controls. Use a single click for precise positioning, double click for coarse, long-distance movement.
		</p>
	</div>
	<div class="col-12">
		<div class="d-flex flex-column flex-md-row gap-2 mb-3">
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
			<button id="zonemapper" class="form-control btn btn-secondary" type="button">Zone Mapper</button>
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
		xhrGet("/cgi-bin/send.cgi?to=" + tgt);
	});
});

const l = document.location;
const pimg = '/cgi-bin/mjpeg.cgi';
const jpg = document.getElementById("preview");

document.addEventListener('DOMContentLoaded', loaded, false);

async function loaded() {
	while (true) {
		await jpg.decode().catch(function() {
			jpg.src = pimg;
		});
		await new Promise((resolve) => setTimeout(resolve, 5000));
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

/* ZONE MAPPER */

let rois = [
	[0,0,50,50],
	[300,300,100,100]
];

function reorderCoords(ar) {
	let numArray = new Float64Array(ar);
	return numArray.sort();
}

function normalizeZone(x, y, w, h) {
	if (w < 0) {
		w = -(w);
		x = x - w;
	}
	if (h < 0) {
		h = -(h);
		y = y - h;
	}
	return [x,y,w,h];
}

function enableZoneMapper() {
	MinZoneHeight = 30;
	MinZoneWidth = 30;
	let mode = 'draw';

	function loadZones() {
	    rois.forEach(z => {
		ctx.fillRect(z[0], z[1], z[2], z[3]);
	    });
	}

	function resetZones() {
		ctx.reset();
		loadZones();
	}

	let sx = 0;
	let sy = 0;

	const frame = $('#frame');
	const fw = frame.clientWidth;
	const fh = frame.clientHeight;

	const cv = document.createElement('canvas');
	cv.width = fw;
	cv.height = fh;
	cv.id = 'roi';
	cv.classList.add('position-absolute', 'top-0');
	frame.append(cv);

	const bound = cv.getBoundingClientRect();
	const bl = bound.left;
	const bt = bound.top;
	const ccl = cv.clientLeft;
	const cct = cv.clientTop;

        const ctx = cv.getContext('2d');
        resetZones();

	cv.addEventListener('mousedown', ev => {
		const x = Math.ceil(ev.clientX - bl - ccl);
		const y = Math.ceil(ev.clientY - bt - cct);
		console.log("Mouse button pressed at (" + x + "," + y + ")");

		if (ev.shiftKey) {
			console.log("Shift key is pressed");
			let index = 0;
			rois.forEach(z => {
				console.log("Zone " + index + " " + z);
				if (x > z[0] && x < (z[0] + z[2]) && y > z[1] && x < (z[1] + z[3])) {
					console.log("Click is within this zone!");
					rois.splice(index, 1);
					resetZones();
				}
				index = index + 1;
			});
			return;
		} else {
			sx = x;
			sy = y;
		}
		ev.preventDefault();
	});

	cv.addEventListener('mousemove', ev => {
		if (ev.buttons != 1) return;
		if (ev.shiftKey) return;

		const w = Math.ceil(ev.clientX - bl - ccl - sx);
		const h = Math.ceil(ev.clientY - bt - cct - sy);
		resetZones();

		if (Math.abs(w) < MinZoneWidth || Math.abs(h) < MinZoneHeight) {
			ctx.strokeStyle = "red";
		} else {
			ctx.strokeStyle = "white";
		}
		ctx.lineWidth = 5;
		ctx.rect(sx, sy, w, h);
		ctx.stroke();
	});

	cv.addEventListener('mouseup', ev => {
		if (ev.shiftKey) {
			console.log("Shift key is pressed. Exiting.");
			return;
		}

		const x = Math.ceil(ev.clientX - bl - ccl);
		const y = Math.ceil(ev.clientY - bt - cct);
		console.log("Mouse button released at (" + x + "," + y + ")");

		const w = x - sx;
		const h = y - sy;
		console.log("Zone size: " + w + "x" + h);

		if (Math.abs(w) < MinZoneWidth) {
			console.log("Width is less than " + MinZoneWidth + "px");
			resetZones();
			return;
		} else if (Math.abs(h) < MinZoneHeight) {
			console.log("Height is less than " + MinZoneHeight + "px");
			resetZones();
			return;
		} else {
			resetZones();
			ctx.fillStyle = "red";
			ctx.fillRect(sx, sy, w, h);
			rois.push(normalizeZone(sx, sy, w, h));
		}
	})
}

$('#zonemapper').addEventListener('click', () => {
	enableZoneMapper();
})
</script>

<style>
#controls div.buttons { background: #88888888; visibility: hidden; width: 100%; height: 100%; }
#controls:hover div.buttons { visibility: visible; }
</style>

<%in p/footer.cgi %>
