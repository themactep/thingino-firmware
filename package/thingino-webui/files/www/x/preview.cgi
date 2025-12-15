#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Camera preview"
which motors > /dev/null && has_motors="true"
%>
<%in _header.cgi %>

<div class="row preview">
<div class="col-lg-1">

<div class="d-flex flex-nowrap flex-lg-wrap align-content-around gap-1" aria-label="controls">
<input type="checkbox" class="btn-check" name="motion" id="motion" value="1">
<label class="btn btn-dark border mb-2" for="motion" title="Motion Guard"><img src="/a/motion.svg" alt="Motion Guard" class="img-fluid"></label>

<input type="checkbox" class="btn-check" name="rotate" id="rotate" value="1">
<label class="btn btn-dark border mb-2" for="rotate" title="Rotate 180°"><img src="/a/rotate.svg" alt="Rotate 180°" class="img-fluid"></label>

<input type="checkbox" class="btn-check" name="daynight" id="daynight" value="1">
<label class="btn btn-dark border mb-2" for="daynight" title="Night mode"><img src="/a/night.svg" alt="Day/Night Mode" class="img-fluid"></label>

<input type="checkbox" class="btn-check" name="color" id="color" value="1">
<label class="btn btn-dark border mb-2" for="color" title="Color mode"><img src="/a/color.svg" alt="Color mode" class="img-fluid"></label>

<% if [ -n "$gpio_ircut" ]; then %>
<input type="checkbox" class="btn-check" name="ircut" id="ircut" value="1">
<label class="btn btn-dark border mb-2" for="ircut" title="IR filter"><img src="/a/ircut_filter.svg" alt="IR filter" class="img-fluid"></label>
<% fi %>

<% if [ -n "$gpio_ir850" ]; then %>
<input type="checkbox" class="btn-check" name="ir850" id="ir850" value="1">
<label class="btn btn-dark border mb-2" for="ir850" title="IR LED 850 nm"><img src="/a/light_850nm.svg" alt="850nm LED" class="img-fluid"></label>
<% fi %>

<% if [ -n "$gpio_ir940" ]; then %>
<input type="checkbox" class="btn-check" name="ir940" id="ir940" value="1">
<label class="btn btn-dark border mb-2" for="ir940" title="IR LED 940 nm"><img src="/a/light_940nm.svg" alt="940nm LED" class="img-fluid"></label>
<% fi %>

<% if [ -n "$gpio_white" ]; then %>
<input type="checkbox" class="btn-check" name="white" id="white" value="1">
<label class="btn btn-dark border mb-2" for="white" title="White LED"><img src="/a/light_white.svg" alt="White light" class="img-fluid"></label>
<% fi %>

<button type="button" class="btn btn-dark border mb-2" title="Zoom" data-bs-toggle="modal" data-bs-target="#mdPreview">
<img src="/a/zoom.svg" alt="Zoom" class="img-fluid"></button>

<button type="button" class="btn btn-dark border mb-2" title="Imaging controls" id="toggle-imaging" aria-controls="imaging-slider" aria-expanded="false">
<img src="/a/controls.svg" alt="Controls" class="img-fluid"></button>

</div>
</div>
<div class="col-lg-10">
<div id="frame" class="position-relative mb-2">

<img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Preview">
<% if [ "true" = "$has_motors" ]; then %><%in _motors.cgi %><% fi %>
</div>

<div id="imaging-slider" class="p-4 bg-black mb-2 d-none" aria-hidden="true">
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-4 g-3 mb-3">
<div class="col"><% field_range "brightness" "Brightness" "0,255,1" %></div>
<div class="col"><% field_range "contrast" "Constrast" "0,255,1" %></div>
<div class="col"><% field_range "sharpness" "Sharpness" "0,255,1" %></div>
<div class="col"><% field_range "saturation" "Saturation" "0,255,1" %></div>
</div>
<div class="row row-cols-1 row-cols-md-2 row-cols-xl-5 g-3">
<div class="col"><% field_range "backlight" "Backlight" "0,10,1" %></div>
<div class="col"><% field_range "wide_dynamic_range" "WDR" "0,255,1" %></div>
<div class="col"><% field_range "tone" "Highlights" "0,255,1" %></div>
<div class="col"><% field_range "defog" "Defog" "0,255,1" %></div>
<div class="col"><% field_range "noise_reduction" "Noise reduction" "0,255,1" %></div>
</div>
</div>

<div class="alert alert-secondary">
<% if [ "true" = "$has_motors" ]; then %>
<p class="small">Move mouse over the center of the preview image for motor controls.
Use single click for precise positioning, double click for coarse navigation.</p>
<% fi %>
<p class="small mb-0">This page has no audio. Open RTSP stream in a video player to hear audio:
<span id="playrtsp" class="cb"></span></p>
</div>

</div>

<div class="col-lg-1">
<div class="d-flex flex-nowrap flex-lg-wrap align-content-around gap-1" aria-label="controls">
<a href="image.cgi" target="_blank" class="btn btn-dark border mb-2" title="Save image"><img src="/a/download.svg" alt="Save image" class="img-fluid"></a>
<button type="button" class="btn btn-dark border mb-2" title="Send to email" data-sendto="email"><img src="/a/email.svg" alt="Email" class="img-fluid"></button>
<button type="button" class="btn btn-dark border mb-2" title="Send to Telegram" data-sendto="telegram"><img src="/a/telegram.svg" alt="Telegram" class="img-fluid"></button>
<button type="button" class="btn btn-dark border mb-2" title="Send to FTP" data-sendto="ftp"><img src="/a/ftp.svg" alt="FTP" class="img-fluid"></button>
<button type="button" class="btn btn-dark border mb-2" title="Send to MQTT" data-sendto="mqtt"><img src="/a/mqtt.svg" alt="MQTT" class="img-fluid"></button>
<button type="button" class="btn btn-dark border mb-2" title="Send to Webhook" data-sendto="webhook"><img src="/a/webhook.svg" alt="Webhook" class="img-fluid"></button>
<button type="button" class="btn btn-dark border mb-2" title="Send to Ntfy" data-sendto="ntfy"><img src="/a/ntfy.svg" alt="Ntfy" class="img-fluid"></button>
</div>
</div>

</div>

<%in _preview.cgi %>

<script>
<%
for i in email ftp mqtt telegram webhook ntfy; do
	continue
#	[ "true" = $(eval echo \$${i}_enabled) ] && continue
%>
{
	let a = document.createElement('a')
	a.href = 'tool-send2<%= $i %>.cgi'
	a.classList.add('btn','btn-outline-danger','mb-2')
	a.title = 'Configure sent2<%= $i%> plugin'
	a.append($('button[data-sendto=<%= $i %>] img'))
	$('button[data-sendto=<%= $i %>]').replaceWith(a);
}
<% done %>

const ImageBlackMode = 1
const ImageColorMode = 0

const endpoint = '/x/json-prudynt.cgi';

function handleMessage(msg) {
	if (msg.image) {
		if (msg.image.hflip)
			$('#rotate').checked = msg.image.hflip;
		if (msg.image.vflip)
			$('#rotate').checked = msg.image.vflip;
	}
	if (msg.motion && msg.motion.enabled) {
		$('#motion').checked = msg.motion.enabled;
	}
	if (msg.rtsp) {
		const r = msg.rtsp;
		if (r.username && r.password && r.port && msg.stream0?.rtsp_endpoint)
			$('#playrtsp').innerHTML = `ffplay rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
	}
}

async function loadConfig() {
	const payload = JSON.stringify({
			image: {hflip: null, vflip: null},
			motion: {enabled: null},
			rtsp: {username: null, password: null, port: null},
			stream0: {rtsp_endpoint: null},
			action: {capture: null}
		});
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
			body: JSON.stringify(payload)
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

async function toggleButton(el) {
	if (!el) return;
	const url = '/x/json-imp.cgi?' + new URLSearchParams({'cmd': el.id, 'val': (el.checked ? 1 : 0)}).toString();
	console.log(url)
	await fetch(url)
		.then(res => res.json())
		.then(data => {
			console.log(data.message)
			el.checked = data.message[el.id] == 1
		})
}

async function toggleDayNight(mode = 'read') {
	url = '/x/json-imp.cgi?' + new URLSearchParams({'cmd': 'daynight', 'val': mode}).toString()
	console.log(url)
	await fetch(url)
		.then(res => res.json())
		.then(data => {
			console.log(data.message)
			$('#daynight').checked = (data.message.daynight == 'night')
			if ($('#ir850')) $('#ir850').checked = (data.message.ir850 == 1)
			if ($('#ir940')) $('#ir940').checked = (data.message.ir940 == 1)
			if ($('#white')) $('#white').checked = (data.message.white == 1)
			if ($('#ircut')) $('#ircut').checked = (data.message.ircut == 1)
			if ($('#color')) $('#color').checked = (data.message.color == 1)
		})
}

$("#motion").addEventListener('change', ev =>
	sendToEndpoint({motion:{enabled: ev.target.checked}}));

$('#rotate').addEventListener('change', ev =>
	sendToEndpoint({image:{hflip: ev.target.checked, vflip: ev.target.checked}}));

$("#daynight").addEventListener('change', ev =>
	ev.target.checked ? toggleDayNight('night') : toggleDayNight('day'));

$$("#color, #ircut, #ir850, #ir940, #white").forEach(el =>
	el.addEventListener('change', ev => toggleButton(el)));

// Init on load
loadConfig().then(() => {
	// Preview
	const timeout = 5000;
	const preview = $('#preview');
	let lastLoadTime = Date.now();
	preview.src = '/x/ch0.mjpg';
	preview.addEventListener('load', () => {
		lastLoadTime = Date.now();
	});
	setInterval(() => {
		if (Date.now() - lastLoadTime > timeout) {
			// Restart stream
			preview.src = preview.src.split('?')[0] + '?' + new Date().getTime();
			lastLoadTime = Date.now();
		}
	}, 1000);
});

toggleDayNight();

const imagingFields = [
	"brightness",
	"contrast",
	"sharpness",
	"saturation",
	"backlight",
	"wide_dynamic_range",
	"tone",
	"defog",
	"noise_reduction"
];

const imagingPanel = $('#imaging-slider');
const imagingToggleButton = $('#toggle-imaging');
let imagingPanelVisible = false;

function setImagingPanelVisibility(show) {
	if (!imagingPanel || !imagingToggleButton) return;
	imagingPanelVisible = !!show;
	imagingPanel.classList.toggle('d-none', !show);
	imagingPanel.setAttribute('aria-hidden', show ? 'false' : 'true');
}

imagingToggleButton?.addEventListener('click', () => {
	const nextState = !imagingPanelVisible;
	setImagingPanelVisibility(nextState);
	if (nextState) {
		fetchImagingState();
	}
});

setImagingPanelVisibility(false);

function updateImagingLabel(name, value) {
	const badge = $(`#${name}-show`);
	if (badge) {
		const displayValue = value === undefined || value === null ? '—' : value;
		badge.textContent = displayValue;
	}
}

function setSliderBounds(slider, min, max, value, defaultValue) {
	if (Number.isFinite(min)) {
		slider.min = min;
	}
	if (Number.isFinite(max)) {
		slider.max = max;
	}
	if (Number.isFinite(value)) {
		slider.value = value;
	}
	if (Number.isFinite(defaultValue)) {
		slider.dataset.defaultValue = defaultValue;
	} else {
		delete slider.dataset.defaultValue;
	}
}

function applyFieldMetadata(field, data) {
	const slider = $(`#${field}`);
	if (!slider) return;
	const wrapper = slider.closest('.col') || slider.parentElement;
	const isSupported = data && data.supported !== false;
	if (!isSupported) {
		slider.disabled = true;
		slider.classList.add('opacity-50');
		wrapper?.classList.add('d-none');
		delete slider.dataset.defaultValue;
		updateImagingLabel(field, '—');
		return;
	}
	slider.disabled = false;
	slider.classList.remove('opacity-50');
	wrapper?.classList.remove('d-none');
	setSliderBounds(slider, Number(data.min), Number(data.max), Number(data.value), Number(data.default));
	updateImagingLabel(field, data.value);
}

async function fetchImagingState() {
	try {
		const res = await fetch('/x/json-imaging.cgi?cmd=read', {cache: 'no-store'});
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		const payload = await res.json();
		const fields = payload && payload.message && payload.message.fields;
		if (!fields) return;
		imagingFields.forEach(field => applyFieldMetadata(field, fields[field] || null));
	} catch (err) {
		console.warn('Unable to load imaging state', err);
	}
}

async function sendImagingUpdate(field, value, slider) {
	const params = new URLSearchParams({cmd: 'set'});
	params.append(field, value);
	slider?.setAttribute('data-busy', '1');
	slider?.classList.add('opacity-75');
	try {
		const res = await fetch(`/x/json-imaging.cgi?${params.toString()}`, {cache: 'no-store'});
		if (!res.ok) throw new Error(`HTTP ${res.status}`);
		const payload = await res.json();
		const fields = payload && payload.message && payload.message.fields;
		if (fields) {
			applyFieldMetadata(field, fields[field] || null);
		}
	} catch (err) {
		console.error('Failed to update imaging value', err);
	} finally {
		slider?.removeAttribute('data-busy');
		slider?.classList.remove('opacity-75');
	}
}

$$('#imaging-slider input[type="range"]').forEach(slider => {
	slider.addEventListener('input', ev => updateImagingLabel(ev.target.name, ev.target.value));
	slider.addEventListener('change', ev => sendImagingUpdate(ev.target.name, ev.target.value, ev.target));
	slider.addEventListener('dblclick', ev => {
		const min = Number(ev.target.min ?? 0);
		const max = Number(ev.target.max ?? 255);
		const midpoint = Math.round((min + max) / 2);
		const defaultValue = ev.target.dataset.defaultValue;
		const targetValue = Number.isFinite(Number(defaultValue)) ? Number(defaultValue) : midpoint;
		ev.target.value = targetValue;
		updateImagingLabel(ev.target.name, ev.target.value);
		sendImagingUpdate(ev.target.name, ev.target.value, ev.target);
	});
});

fetchImagingState();
</script>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
</div>

<%in _footer.cgi %>
