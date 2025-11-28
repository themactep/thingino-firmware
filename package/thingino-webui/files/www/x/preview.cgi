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
</div>
</div>
<div class="col-lg-10">
<div id="frame" class="position-relative mb-2">
<video id="previewVideo" class="img-fluid d-none" autoplay muted playsinline controlslist="nodownload nofullscreen noremoteplayback"></video>
<img id="preview" src="/a/nostream.webp" class="img-fluid" alt="Image: Preview">
<% if [ "true" = "$has_motors" ]; then %><%in _motors.cgi %><% fi %>
</div>

<% if [ "true" = "$has_motors" ]; then %>
<p class="small">Move mouse cursor over the center of the preview image to reveal the motor controls.
Use a single click for precise positioning, double click for coarse, larger distance movement.</p>
<% fi %>

<div class="alert alert-secondary">
<p class="mb-0">
<button type="button" id="audioToggle" class="btn btn-dark border m-2 px-3 py-1 float-end" title="Toggle audio" disabled>
<span data-audio-label>Audio Off</span></button>
When the browser supports MP4 streaming, the preview carries audio.
In the fallback JPEG mode, audio remains unavailable, so open the RTSP stream:
<b id="playrtsp" class="cb"></b></p>
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
const preview = $("#preview");
const previewVideo = $('#previewVideo');
const audioToggle = $('#audioToggle');
const audioToggleLabel = audioToggle ? audioToggle.querySelector('[data-audio-label]') : null;
if (previewVideo) {
	previewVideo.muted = true;
	previewVideo.setAttribute('muted', 'muted');
	previewVideo.playsInline = true;
}
let jpegPreviewActive = true;
let audioEnabled = false;
let hlsInstance = null;
let hlsScriptLoading = null;
let attemptedHlsJs = false;
let currentStreamMode = 'none';
let mp4FallbackTimer = null;
let playbackRestartTimer = null;
let restartSuppressionTimer = null;
let suppressVideoEvents = false;
let hlsCooldownUntil = 0;
let hasLoadedInitialFrame = false;
const hlsCooldownMs = 10000;
preview.onload = function() { URL.revokeObjectURL(this.src) }

const ImageBlackMode = 1
const ImageColorMode = 0

function requestNextCapture() {
	if (jpegPreviewActive && ws && ws.readyState === WebSocket.OPEN) {
		ws.send('{"action":{"capture":null}}');
	}
}

function updatePreview(buffer) {
	if (!buffer) return;
	const blob = new Blob([buffer], {type: 'image/jpeg'});
	const objectUrl = URL.createObjectURL(blob);
	previewVideo.classList.add('d-none');
	preview.classList.remove('d-none');
	preview.src = objectUrl;
	jpegPreviewActive = true;
}

function updateAudioToggle() {
	if (!audioToggle) return;
	audioToggle.classList.toggle('btn-success', audioEnabled && !audioToggle.disabled);
	audioToggle.classList.toggle('btn-dark', !audioEnabled || audioToggle.disabled);
	audioToggle.setAttribute('aria-pressed', audioEnabled ? 'true' : 'false');
	audioToggle.title = audioEnabled ? 'Mute preview audio' : 'Enable preview audio';
	if (audioToggleLabel) {
		audioToggleLabel.textContent = audioEnabled ? 'Audio On' : 'Audio Off';
	}
}

function initPreviewVideo() {
	if (!previewVideo) return;
	const httpProto = location.protocol === "https:" ? "https:" : "http:";
	const httpPort = location.protocol === "https:" ? 8090 : 8089;
	const mp4Url = `${httpProto}//${document.location.hostname}:${httpPort}/ch0.mp4?token=<%= $ws_token %>`;
	const hlsUrl = `${httpProto}//${document.location.hostname}:${httpPort}/hls/playlist.m3u8?token=<%= $ws_token %>`;
	const ua = navigator.userAgent || '';
	const isSafari = /Safari/i.test(ua) && !/Chrome|Chromium|Android/i.test(ua);
	const nativeHls = isSafari && typeof previewVideo.canPlayType === 'function' &&
		previewVideo.canPlayType('application/vnd.apple.mpegurl');
	const initialMode = nativeHls ? 'hls-native' : 'mp4';

	const ensureHlsDestroyed = () => {
		if (hlsInstance) {
			try {
				hlsInstance.destroy();
			} catch (e) {
				console.warn('hls.js destroy error', e);
			}
			hlsInstance = null;
		}
	};

	const clearMp4FallbackTimer = () => {
		if (mp4FallbackTimer) {
			clearTimeout(mp4FallbackTimer);
			mp4FallbackTimer = null;
		}
	};

	const suppressVideoEventsFor = (durationMs = 1500) => {
		suppressVideoEvents = true;
		if (restartSuppressionTimer) {
			clearTimeout(restartSuppressionTimer);
		}
		restartSuppressionTimer = window.setTimeout(() => {
			suppressVideoEvents = false;
			restartSuppressionTimer = null;
		}, durationMs);
	};

	const resumeVideoEventHandling = () => {
		suppressVideoEvents = false;
		if (restartSuppressionTimer) {
			clearTimeout(restartSuppressionTimer);
			restartSuppressionTimer = null;
		}
	};

	const shouldIgnorePreloadEvent = (label) => {
		if (hasLoadedInitialFrame) {
			return false;
		}
		return label === 'emptied' || label === 'suspend' || label === 'abort' || label === 'ended';
	};

	const guardVideoEvent = (label, handler) => {
		if (shouldIgnorePreloadEvent(label)) {
			console.warn('Ignoring', label, 'before first frame');
			return;
		}
		if (suppressVideoEvents) {
			console.warn('Ignoring video event during restart:', label);
			return;
		}
		handler();
	};

	const schedulePlaybackRestart = (reason, delayMs = 3000) => {
		if (suppressVideoEvents) {
			console.warn('Restart already in progress; skipping', reason);
			return;
		}
		if (playbackRestartTimer) {
			return;
		}
		console.warn('Scheduling preview restart:', reason);
		playbackRestartTimer = window.setTimeout(() => {
			playbackRestartTimer = null;
			restartPlayback();
		}, delayMs);
	};

	const restartPlayback = () => {
		console.warn('Reinitializing inline preview stream');
		suppressVideoEventsFor();
		clearMp4FallbackTimer();
		ensureHlsDestroyed();
		attemptedHlsJs = false;
		currentStreamMode = 'none';
		hasLoadedInitialFrame = false;
		try {
			previewVideo.pause();
		} catch (e) {}
		previewVideo.removeAttribute('src');
		previewVideo.load();
		setVideoSource(initialMode);
	};

	const setVideoSource = (mode) => {
		clearMp4FallbackTimer();
		currentStreamMode = mode;
		if (audioToggle) {
			audioToggle.disabled = true;
		}
		if (mode === 'hls-native') {
			ensureHlsDestroyed();
			previewVideo.dataset.streamType = 'hls-native';
			previewVideo.src = hlsUrl;
			previewVideo.load();
			previewVideo.play().catch(() => {});
			return;
		}
		if (mode === 'hls-js') {
			if (Date.now() < hlsCooldownUntil) {
				console.warn('Skipping hls.js start (cooldown active)');
				fallbackToMp4();
				return;
			}
			ensureHlsDestroyed();
			loadHlsJs().then(() => {
				if (!window.Hls || !window.Hls.isSupported()) {
					console.warn('hls.js not supported in this browser');
					fallbackToMp4();
					return;
				}
				hlsInstance = new window.Hls({lowLatencyMode: false});
				hlsInstance.loadSource(hlsUrl);
				hlsInstance.attachMedia(previewVideo);
				hlsInstance.on(window.Hls.Events.MANIFEST_PARSED, () => {
					previewVideo.dataset.streamType = 'hls-js';
					previewVideo.play().catch(err => console.warn('autoplay blocked (hls.js)', err));
				});
				hlsInstance.on(window.Hls.Events.ERROR, (event, data) => {
					console.error('hls.js error', data);
					if (data && data.fatal) {
						hlsCooldownUntil = Date.now() + hlsCooldownMs;
						fallbackToMp4();
					}
				});
			}).catch(err => {
				console.error('Failed to load hls.js', err);
				hlsCooldownUntil = Date.now() + hlsCooldownMs;
				fallbackToMp4();
			});
			return;
		}
		// default mp4
		ensureHlsDestroyed();
		previewVideo.dataset.streamType = 'mp4';
		previewVideo.src = mp4Url;
		previewVideo.load();
		previewVideo.play().catch(() => {});
		if (!attemptedHlsJs) {
			mp4FallbackTimer = window.setTimeout(() => {
				if (currentStreamMode !== 'mp4') {
					return;
				}
				const haveData = typeof previewVideo.readyState === 'number' &&
					previewVideo.readyState >= HTMLMediaElement.HAVE_CURRENT_DATA;
				if (haveData) {
					return;
				}
				console.warn('MP4 inline playback timed out; switching to hls.js');
				attemptedHlsJs = true;
				setVideoSource('hls-js');
			}, 2500);
		}
	};

	const fallbackToMp4 = () => {
		if (currentStreamMode === 'mp4') {
			return;
		}
		setVideoSource('mp4');
	};

	const handleVideoError = (err) => {
		if (suppressVideoEvents) {
			console.warn('Ignoring inline video error while restarting');
			return;
		}
		console.error('Inline video error', err, previewVideo.error);
		if (currentStreamMode === 'mp4' && !attemptedHlsJs) {
			attemptedHlsJs = true;
			setVideoSource('hls-js');
			return;
		}
		if (currentStreamMode === 'hls-js') {
			attemptedHlsJs = true;
			hlsCooldownUntil = Date.now() + hlsCooldownMs;
			fallbackToMp4();
			return;
		}
		previewVideo.classList.add('d-none');
		preview.classList.remove('d-none');
		jpegPreviewActive = true;
		if (audioToggle) {
			audioToggle.disabled = true;
		}
		audioEnabled = false;
		updateAudioToggle();
		requestNextCapture();
		schedulePlaybackRestart('stream error fallback', 5000);
	};

	previewVideo.addEventListener('error', handleVideoError);
	previewVideo.addEventListener('loadeddata', () => {
		hasLoadedInitialFrame = true;
		resumeVideoEventHandling();
		clearMp4FallbackTimer();
		preview.classList.add('d-none');
		previewVideo.classList.remove('d-none');
		jpegPreviewActive = false;
		if (audioToggle) {
			audioToggle.disabled = false;
		}
		updateAudioToggle();
		previewVideo.play().catch(e => console.warn('autoplay blocked', e));
	});

	previewVideo.addEventListener('stalled', () => guardVideoEvent('stalled', () => {
		if (currentStreamMode === 'mp4' && !attemptedHlsJs) {
			console.warn('MP4 stream stalled; attempting hls.js fallback');
			attemptedHlsJs = true;
			setVideoSource('hls-js');
			return;
		}
		schedulePlaybackRestart('video stalled');
	}));

	['ended', 'abort', 'suspend', 'emptied'].forEach(evt => {
		previewVideo.addEventListener(evt, () => guardVideoEvent(evt, () => {
			schedulePlaybackRestart(`video ${evt}`);
		}));
	});

	setVideoSource(initialMode);
}

initPreviewVideo();

if (audioToggle) {
	audioToggle.addEventListener('click', () => {
		if (!previewVideo || audioToggle.disabled) return;
		audioEnabled = !audioEnabled;
		previewVideo.muted = !audioEnabled;
		if (audioEnabled) {
			previewVideo.removeAttribute('muted');
			previewVideo.play().catch(err => console.warn('audio play blocked', err));
		} else {
			previewVideo.setAttribute('muted', 'muted');
		}
		updateAudioToggle();
	});
	updateAudioToggle();
}

const wsPort = location.protocol === "https:" ? 8090 : 8089;
const wsProto = location.protocol === "https:" ? "wss:" : "ws:";
let ws = new WebSocket(`${wsProto}//${document.location.hostname}:${wsPort}?token=<%= $ws_token %>`);

ws.onopen = () => {
	console.log('WebSocket connection opened');
	ws.binaryType = 'arraybuffer';
	const payload = '{'+
		'"image":{"hflip":null,"vflip":null,"running_mode":null},'+
		'"motion":{"enabled":null},'+
		'"rtsp":{"username":null,"password":null,"port":null},'+
		'"stream0":{"rtsp_endpoint":null},'+
//		'"action":{"capture":null}'+
		'}'
	console.log(ts(), '===>', payload);
	ws.send(payload);
}
ws.onclose = () => {
	console.log('WebSocket connection closed');
	ws = null;
}
ws.onerror = (err) => {
	console.error('WebSocket error', err);
	ws.close();
}
ws.onmessage = (ev) => {
	if (typeof ev.data == 'string') {
		if (ev.data == '') {
			console.log('Empty response');
			return;
		}
		if (ev.data == '{"action":{"capture":"initiated"}}') {
			return;
		}
		console.log(ts(), '<===', ev.data);
		const msg = JSON.parse(ev.data);

		if (msg.image) {
			if (msg.image.hflip) {
				$('#rotate').checked = msg.image.hflip;
			}
			if (msg.image.vflip) {
				$('#rotate').checked = msg.image.vflip;
			}
		}
		if (msg.motion) {
			if (msg.motion.enabled) $('#motion').checked = msg.motion.enabled;
		}
		if (msg.rtsp) {
			const r = msg.rtsp;
			if (r.username && r.password && r.port)
				$('#playrtsp').innerHTML = `mpv rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
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
	sendToWs('{"motion":{"enabled":' + ev.target.checked + '}}'));

$('#rotate').addEventListener('change', ev =>
	sendToWs('{"image":{"hflip":' + ev.target.checked + ',"vflip":' + ev.target.checked + '}}'));

$("#daynight").addEventListener('change', ev =>
	ev.target.checked ? toggleDayNight('night') : toggleDayNight('day'));

$$("#color, #ircut, #ir850, #ir940, #white").forEach(el =>
	el.addEventListener('change', ev => toggleButton(el)));

toggleDayNight();

function loadHlsJs() {
	if (window.Hls && typeof window.Hls.isSupported === 'function') {
		return Promise.resolve();
	}
	if (hlsScriptLoading) {
		return hlsScriptLoading;
	}
	hlsScriptLoading = new Promise((resolve, reject) => {
		const script = document.createElement('script');
		script.src = 'https://cdn.jsdelivr.net/npm/hls.js@1.5.7/dist/hls.min.js';
		script.onload = () => resolve();
		script.onerror = (err) => reject(err);
		document.head.appendChild(script);
	});
	return hlsScriptLoading;
}
</script>

<div class="alert alert-dark ui-debug d-none">
<h4 class="mb-3">Debug info</h4>
</div>

<%in _footer.cgi %>
