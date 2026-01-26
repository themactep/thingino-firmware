const ThreadRtsp = 1;
const ThreadVideo = 2;
const ThreadAudio = 4;
const ThreadOSD = 8;

const ImageNoStream = '/a/nostream.svg';

let max = 0;

if (typeof window !== 'undefined') {
	window.network_address = window.network_address || window.location.hostname || '';
}

let recordingState = {
	ch0: false,
	ch1: false
};
const HeartBeatReconnectDelay = 2 * 1000;
const HeartBeatMaxReconnectDelay = 60 * 1000;
const HeartBeatEndpoint = '/x/json-heartbeat.cgi';
let heartbeatSource = null;
let currentReconnectDelay = HeartBeatReconnectDelay;
let debugModalCtx = null;

function $(n) {
	return document.querySelector(n)
}

function $$(n) {
	return document.querySelectorAll(n)
}

function $n(n) {
	return document.createElement(n)
}

function decodeBase64String(encoded) {
	if (!encoded) return '';
	try {
		const binary = atob(encoded);
		if (window.TextDecoder) {
			const bytes = new Uint8Array(binary.length);
			for (let i = 0; i < binary.length; i += 1) {
				bytes[i] = binary.charCodeAt(i);
			}
			return new TextDecoder('utf-8', { fatal: false }).decode(bytes);
		}
		return binary;
	} catch (err) {
		console.warn('Failed to decode base64 payload', err);
		return '';
	}
}

function hideDebugModal(ctx = debugModalCtx) {
	if (!ctx) return;
	if (ctx.modalInstance) {
		ctx.modalInstance.hide();
	} else {
		ctx.modalEl.classList.remove('show');
		ctx.modalEl.style.display = 'none';
		ctx.modalEl.setAttribute('aria-hidden', 'true');
		ctx.modalEl.removeAttribute('aria-modal');
		if (ctx.buttonRef) ctx.buttonRef.classList.remove('active');
	}
}

function showDebugModal(ctx = debugModalCtx) {
	if (!ctx) return;
	if (ctx.modalInstance) {
		ctx.modalInstance.show();
	} else {
		ctx.modalEl.classList.add('show');
		ctx.modalEl.style.display = 'block';
		ctx.modalEl.removeAttribute('aria-hidden');
		ctx.modalEl.setAttribute('aria-modal', 'true');
	}
}

function ensureDebugModalStructure() {
	if (debugModalCtx) return debugModalCtx;
	const modalEl = document.createElement('div');
	modalEl.id = 'debugInfoModal';
	modalEl.className = 'modal fade';
	modalEl.tabIndex = -1;
	modalEl.setAttribute('aria-hidden', 'true');
	modalEl.innerHTML = `
	  <div class="modal-dialog modal-lg modal-dialog-scrollable">
	    <div class="modal-content">
	      <div class="modal-header">
	        <h5 class="modal-title">Debug information</h5>
	        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
	      </div>
	      <div class="modal-body">
	        <p class="text-body-secondary mb-0">No debug information available.</p>
	      </div>
	    </div>
	  </div>`;
	document.body.appendChild(modalEl);
	const modalBody = modalEl.querySelector('.modal-body');
	let modalInstance = null;
	if (window.bootstrap && window.bootstrap.Modal) {
		modalInstance = window.bootstrap.Modal.getOrCreateInstance(modalEl);
	}
	const ctx = {
		modalEl,
		modalBody,
		modalInstance,
		buttonRef: null
	};
	const closeBtn = modalEl.querySelector('.btn-close');
	if (closeBtn && (!window.bootstrap || !window.bootstrap.Modal)) {
		closeBtn.addEventListener('click', ev => {
			ev.preventDefault();
			hideDebugModal(ctx);
		});
	}
	modalEl.addEventListener('hidden.bs.modal', () => {
		if (ctx.buttonRef) ctx.buttonRef.classList.remove('active');
	});
	debugModalCtx = ctx;
	return ctx;
}

function populateDebugModalContent() {
	const ctx = ensureDebugModalStructure();
	if (!ctx || !ctx.modalBody) return ctx;
	const fragment = document.createDocumentFragment();
	document.querySelectorAll('.ui-debug').forEach(panel => {
		const clone = panel.cloneNode(true);
		clone.classList.remove('d-none');
		fragment.appendChild(clone);
	});
	ctx.modalBody.innerHTML = '';
	if (!fragment.childNodes.length) {
		const placeholder = document.createElement('p');
		placeholder.className = 'text-body-secondary mb-0';
		placeholder.textContent = 'No debug information available.';
		ctx.modalBody.appendChild(placeholder);
	} else {
		ctx.modalBody.appendChild(fragment);
	}
	return ctx;
}

const ThemeState = {
	endpoint: '/x/json-config-webui.cgi',
	preferenceKey: 'thingino-theme-preference',
	activeKey: 'thingino-theme-active'
};

function safeStorageGet(key) {
	try {
		if (!window.localStorage) return null;
		return localStorage.getItem(key);
	} catch (err) {
		return null;
	}
}

function safeStorageSet(key, value) {
	try {
		if (!window.localStorage) return;
		if (value === null || typeof value === 'undefined' || value === '') {
			localStorage.removeItem(key);
			return;
		}
		localStorage.setItem(key, value);
	} catch (err) {
		// Best effort cache, ignore failures
	}
}

function applyThemeAttribute(theme) {
	if (!theme) return;
	document.documentElement.setAttribute('data-bs-theme', theme);
}

function rememberThemeState(activeTheme, preferenceTheme) {
	if (activeTheme) {
		safeStorageSet(ThemeState.activeKey, activeTheme);
		applyThemeAttribute(activeTheme);
	}
	if (preferenceTheme) {
		safeStorageSet(ThemeState.preferenceKey, preferenceTheme);
	}
}

async function refreshThemeFromServer() {
	if (typeof fetch !== 'function') return;
	try {
		const response = await fetch(ThemeState.endpoint, { headers: { 'Accept': 'application/json' } });
		if (!response.ok) return;
		const data = await response.json();
		const preference = data && (data.theme || (data.webui && data.webui.theme));
		const active = (data && data.active_theme) || preference;
		rememberThemeState(active, preference);
	} catch (err) {
		if (typeof console !== 'undefined' && typeof console.debug === 'function') {
			console.debug('Theme refresh skipped', (err && err.message) ? err.message : err);
		}
	}
}

(function initThemeBridge() {
	const cachedTheme = safeStorageGet(ThemeState.activeKey);
	if (cachedTheme) {
		applyThemeAttribute(cachedTheme);
	}
	refreshThemeFromServer();
})();

window.thinginoTheme = {
	apply: applyThemeAttribute,
	remember: rememberThemeState,
	refresh: refreshThemeFromServer,
	getPreference: () => safeStorageGet(ThemeState.preferenceKey),
	getActive: () => safeStorageGet(ThemeState.activeKey)
};

function ts() {
	return Math.floor(Date.now());
}

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms))
}

function hasNavigatorClipboard() {
	return typeof navigator !== 'undefined' && !!navigator.clipboard && !!window.isSecureContext;
}

function fallbackClipboardCopy(text) {
	return new Promise((resolve, reject) => {
		const textarea = document.createElement('textarea');
		textarea.value = text;
		textarea.style.position = 'fixed';
		textarea.style.left = '-9999px';
		textarea.style.top = '-9999px';
		document.body.appendChild(textarea);
		try {
			textarea.focus();
			textarea.select();
			const successful = document.execCommand('copy');
			if (successful) {
				resolve(true);
			} else {
				reject(new Error('clipboard-fallback'));
			}
		} catch (err) {
			reject(err);
		} finally {
			textarea.remove();
		}
	});
}

async function copyTextToClipboard(text) {
	const value = typeof text === 'string' ? text : (text === null || typeof text === 'undefined' ? '' : String(text));
	if (!value) {
		return Promise.reject(new Error('clipboard-empty'));
	}
	if (hasNavigatorClipboard()) {
		try {
			await navigator.clipboard.writeText(value);
			return true;
		} catch (err) {
			// Fallback below
		}
	}
	return fallbackClipboardCopy(value);
}

const clipboardApi = window.thinginoClipboard || {};
clipboardApi.copy = copyTextToClipboard;
clipboardApi.fallbackCopy = fallbackClipboardCopy;
clipboardApi.canUseNavigator = hasNavigatorClipboard;
window.thinginoClipboard = clipboardApi;

function setProgressBar(id, value, maxvalue, name) {
	const el = $(id);
	const safeMax = Number(maxvalue);
	if (!el || !Number.isFinite(safeMax) || safeMax <= 0) return;
	const safeValue = Math.max(0, Number(value) || 0);
	const valuePercent = Math.min(100, Math.max(0, Math.round((safeValue / safeMax) * 100)));
	el.setAttribute('aria-valuemin', '0');
	el.setAttribute('aria-valuemax', safeMax);
	el.setAttribute('aria-valuenow', safeValue);
	el.style.width = valuePercent + '%';
	el.title = (name || 'Usage') + ': ' + safeValue + 'KiB (' + valuePercent + '%)';
}

function setValue(data, domain, name) {
	const id = `#${domain}_${name}`;
	const el = $(id);
	if (!el) return;
	const value = data[name];
	if (typeof (value) == 'undefined') return;

	el.disabled = false;
	const wrapper = el.closest('.range, .number-range, .number, .select, .boolean, .file');
	if (wrapper) wrapper.classList.remove('disabled');

	if (el.type === "checkbox") {
		el.checked = value;
	} else {
		el.value = value;
		if (el.type === "range") {
			$(`${id}-show`).textContent = value;
		}
		// Also update modal slider for number_range fields
		const slider = $(`${id}-slider`);
		if (slider) {
			slider.value = value;
			slider.disabled = false;
			const sliderValue = $(`${id}-slider-value`);
			if (sliderValue) sliderValue.textContent = value;
		}
	}
}

function updateRecordingIcons() {
	$$('#recorder-ch0, #recorder-ch1').forEach(button => {
		const channel = parseInt(button.dataset.channel);
		const isRecording = recordingState[`ch${channel}`];
		button.classList.remove('pending');
		button.classList.toggle('active', isRecording);
		button.classList.toggle('recorder-active', isRecording);
	});
}

function updateRecordingState(state) {
	recordingState.ch0 = state.ch0;
	recordingState.ch1 = state.ch1;
	updateRecordingIcons();
}

function toggleRecording(channel) {
	const button = $(`#recorder-ch${channel}`);
	const isRecording = recordingState[`ch${channel}`];
	const action = isRecording ? 'stop' : 'start';

	console.log(`toggleRecording called: channel=${channel}, currentState=${isRecording ? 'recording' : 'stopped'}, action=${action}`);

	if (button) button.classList.add('pending');

	const payload = isRecording
		? JSON.stringify({ mp4: { stop: { channel: channel } } })
		: JSON.stringify({ mp4: { start: { channel: channel } } });

	console.log(`Sending payload: ${payload}`);

	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(response => {
			if (!response.ok) throw new Error(`HTTP error ${response.status}`);
			return response.text();
		})
		.then(text => {
			if (!text) {
				console.log(`Empty response (assumed success)`);
				return;
			}
			const data = JSON.parse(text);
			console.log(`Response received:`, data);
			if (data.mp4 && data.mp4[action]) {
				if (data.mp4[action] === 'ok') {
					console.log(`Recording ${action} successful on channel ${channel}`);
				} else {
					console.error('Recording control error:', data.mp4[action]);
					if (button) button.classList.remove('pending');
					alert(`Failed to ${action} recording on channel ${channel}: ${data.mp4[action]}`);
				}
			} else {
				console.error('Unexpected response:', data);
				if (button) button.classList.remove('pending');
				alert(`Failed to ${action} recording on channel ${channel}`);
			}
		})
		.catch(err => {
			console.error('Recording control failed:', err);
			if (button) button.classList.remove('pending');
			alert(`Failed to ${action} recording on channel ${channel}`);
		});
}

function toggleMotion(state) {
	const button = $('#motion');
	if (button) button.classList.add('pending');

	const payload = JSON.stringify({ motion: { enabled: state } });
	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(res => {
			if (!res.ok) throw new Error(`HTTP error ${res.status}`);
			return res.text();
		})
		.then(text => {
			if (!text) {
				console.log(ts(), '<===', 'Empty response (assumed success)');
				return;
			}
			const data = JSON.parse(text);
			console.log(ts(), '<===', JSON.stringify(data));
			if (data.motion && data.motion.enabled !== undefined) {
				// Pending class will be removed when heartbeat confirms the state
			} else {
				if (button) button.classList.remove('pending');
			}
		})
		.catch(err => {
			console.error('Motion toggle error', err);
			if (button) button.classList.remove('pending');
		});
}

function togglePrivacy(state) {
	const button = $('#privacy');
	if (button) button.classList.add('pending');

	const payload = JSON.stringify({ privacy: { enabled: state } });
	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(res => {
			if (!res.ok) throw new Error(`HTTP error ${res.status}`);
			return res.text();
		})
		.then(text => {
			if (!text) {
				console.log(ts(), '<===', 'Empty response (assumed success)');
				return;
			}
			const data = JSON.parse(text);
			console.log(ts(), '<===', JSON.stringify(data));
			if (data.privacy && data.privacy.enabled !== undefined) {
				// Pending class will be removed when heartbeat confirms the state
			} else {
				if (button) button.classList.remove('pending');
			}
		})
		.catch(err => {
			console.error('Privacy toggle error', err);
			if (button) button.classList.remove('pending');
		});
}

function toggleWireGuard(state) {
	const button = $('#wireguard');
	if (button) button.classList.add('pending');

	const targetState = state ? 1 : 0;
	fetch('/x/json-wireguard.cgi?iface=wg0&state=' + targetState)
		.then(res => {
			if (!res.ok) throw new Error(`HTTP error ${res.status}`);
			return res.json();
		})
		.then(data => {
			console.log(ts(), '<===', JSON.stringify(data));
			if (data.error) {
				console.error('WireGuard toggle error:', data.error.message);
				if (button) button.classList.remove('pending');
			} else {
				// Pending class will be removed when heartbeat confirms the state
			}
		})
		.catch(err => {
			console.error('WireGuard toggle error', err);
			if (button) button.classList.remove('pending');
		});
}

function toggleDayNight(mode) {
	const button = $('#daynight');
	if (button) button.classList.add('pending');

	const payload = JSON.stringify({ cmd: 'daynight', val: mode });
	console.log('Sending daynight payload:', payload);
	fetch('/x/json-imp.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(res => {
			if (!res.ok) throw new Error(`HTTP error ${res.status}`);
			return res.text();
		})
		.then(text => {
			if (!text) {
				console.log(ts(), '<===', 'Empty response (assumed success)');
				return;
			}
			const data = JSON.parse(text);
			console.log(ts(), '<===', JSON.stringify(data));
			if (button) button.classList.remove('pending');
		})
		.catch(err => {
			console.error('DayNight toggle error', err);
			if (button) button.classList.remove('pending');
		});
}

function toggleAudio(device, state) {
	const button = $('#' + device);
	if (button) button.classList.add('pending');

	const param = device === 'microphone' ? 'mic_enabled' : 'spk_enabled';
	const payload = JSON.stringify({ audio: { [param]: state } });
	console.log(ts(), '===>', payload);
	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(res => {
			if (!res.ok) throw new Error(`HTTP error ${res.status}`);
			return res.text();
		})
		.then(text => {
			if (!text) {
				console.log(ts(), '<===', 'Empty response (assumed success)');
				return;
			}
			const data = JSON.parse(text);
			console.log(ts(), '<===', JSON.stringify(data));
			if (data.audio && data.audio[param] !== undefined) {
				// Pending class will be removed when heartbeat confirms the state
			} else {
				if (button) button.classList.remove('pending');
			}
		})
		.catch(err => {
			console.error('Audio toggle error', err);
			if (button) button.classList.remove('pending');
		});
}

function toggleTheme() {
	const htmlEl = document.documentElement;
	const currentTheme = htmlEl.getAttribute('data-bs-theme');
	const newTheme = currentTheme === 'dark' ? 'light' : 'dark';

	htmlEl.setAttribute('data-bs-theme', newTheme);

	const themeBtn = $('#theme-toggle');
	if (themeBtn) {
		const img = themeBtn.querySelector('img');
		if (img) {
			img.src = newTheme === 'dark' ? '/a/brilliance.svg' : '/a/brilliance.svg';
			img.alt = newTheme === 'dark' ? 'Light mode' : 'Dark mode';
		}
	}
}

async function toggleButton(el) {
	if (!el) return;
	const currentState = el.classList.contains('active') ? 1 : 0;
	let newState = currentState ? 0 : 1;

	// Special handling for color button: ISP mode 0=color, 1=b&w
	// When active (color mode), we want to send 1 to switch to b&w
	// When inactive (b&w mode), we want to send 0 to switch to color
	if (el.id === 'color') {
		newState = currentState ? 1 : 0;
	}

	const payload = JSON.stringify({ cmd: el.id, val: newState });
	console.log('Sending to json-imp.cgi:', payload);
	await fetch('/x/json-imp.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
		.then(res => res.json())
		.then(data => {
			console.log(data.message)
		})
}

function resolveDeviceTimezone() {
	const uiConfig = window.thinginoUIConfig || {};
	const deviceTimezone = (uiConfig.device && typeof uiConfig.device.timezone === 'string') ? uiConfig.device.timezone.trim() : '';
	if (deviceTimezone) return deviceTimezone;
	if (typeof uiConfig.timezone === 'string' && uiConfig.timezone.trim()) return uiConfig.timezone.trim();
	return '';
}

function updateHeartbeatUi(json) {
	if (!json) return;
	const timeNowEl = $('#time-now');
	if (timeNowEl && json.time_now !== '') {
		const d = new Date(json.time_now * 1000);
		const configuredTimezone = resolveDeviceTimezone();
		const heartbeatTimezone = typeof json.timezone === 'string' ? json.timezone.trim() : '';
		const timezoneLabel = configuredTimezone || heartbeatTimezone;
		const timeZoneId = timezoneLabel ? timezoneLabel.replaceAll(' ', '_') : '';
		let options = {
			year: "numeric",
			month: "short",
			day: "numeric",
			hour: "2-digit",
			minute: "2-digit"
		};
		if (timeZoneId) {
			options.timeZone = timeZoneId;
		}
		const formatted = d.toLocaleString(navigator.language, options);
		timeNowEl.textContent = timezoneLabel ? formatted + ' ' + timezoneLabel : formatted;
	}

	const hasBrightness = typeof (json.daynight_brightness) !== 'undefined' && json.daynight_brightness !== 'unknown' && json.daynight_brightness !== '';
	const hasTotalGain = typeof (json.total_gain) !== 'undefined' && json.total_gain !== 'unknown' && json.total_gain !== '' && json.total_gain >= 0;
	const hasMode = typeof (json.daynight_mode) !== 'undefined' && json.daynight_mode !== 'unknown' && json.daynight_mode !== '';
	if (hasTotalGain || hasBrightness || hasMode) {
		// const icon = dayNightIcon(json.daynight_mode);
		// const label = hasTotalGain ? `${icon} ${json.total_gain}` : (hasBrightness ? `${icon} ${json.daynight_brightness}` : icon);
		const label = hasTotalGain ? json.total_gain : (hasBrightness ? json.daynight_brightness : '---');
		$$('.dnd-gain').forEach(el => el.textContent = label);
	}

	const uptimeEl = $('#uptime');
	if (uptimeEl && typeof (json.uptime) !== 'undefined' && json.uptime !== '')
		uptimeEl.textContent = 'Uptime:️ ' + json.uptime;

	updateRecordingState({
		ch0: json.rec_ch0 === true,
		ch1: json.rec_ch1 === true
	});

	// Update motion detection icon
	if (typeof (json.motion_enabled) !== 'undefined') {
		const motionBtn = $('#motion');
		if (motionBtn) {
			motionBtn.classList.remove('pending');
			motionBtn.classList.toggle('active', json.motion_enabled === true);
		}
	}

	// Update privacy icon
	if (typeof (json.privacy_enabled) !== 'undefined') {
		const privacyBtn = $('#privacy');
		if (privacyBtn) {
			privacyBtn.classList.remove('pending');
			privacyBtn.classList.toggle('active', json.privacy_enabled === true);
		}
	}

	// Update wireguard icon
	if (typeof (json.wg_status) !== 'undefined') {
		const wireguardBtn = $('#wireguard');
		if (wireguardBtn) {
			wireguardBtn.classList.remove('pending');
			wireguardBtn.classList.toggle('active', json.wg_status === 1);
		}
	}

	// Update daynight mode button
	if (typeof (json.daynight_mode) !== 'undefined') {
		const daynightBtn = $('#daynight');
		if (daynightBtn) {
			daynightBtn.classList.remove('pending');
			const isNight = json.daynight_mode === 'night';
			const isAutoEnabled = json.daynight_enabled === true || json.daynight_enabled === 1;
			daynightBtn.classList.toggle('active', isAutoEnabled);
			daynightBtn.classList.toggle('is-night', isNight);
			daynightBtn.classList.toggle('is-day', !isNight);

			// Update button text and icon based on photosensing state
			const daynightText = $('#daynight-text');
			const daynightIcon = daynightBtn.querySelector('i');

			if (daynightText) {
				daynightText.textContent = isAutoEnabled ? 'Auto' : (isNight ? 'Night' : 'Day');
			}

			if (daynightIcon) {
				daynightIcon.className = isNight ? 'bi bi-moon-stars' : 'bi bi-sun';
			}
		}

		// Update Day button active state
		const dayBtn = $('#day');
		if (dayBtn) {
			const isAutoEnabled = json.daynight_enabled === true || json.daynight_enabled === 1;
			const isDay = json.daynight_mode === 'day';
			dayBtn.classList.toggle('active', !isAutoEnabled && isDay);
		}

		// Update Night button active state
		const nightBtn = $('#night');
		if (nightBtn) {
			const isAutoEnabled = json.daynight_enabled === true || json.daynight_enabled === 1;
			const isNight = json.daynight_mode === 'night';
			nightBtn.classList.toggle('active', !isAutoEnabled && isNight);
		}
	}

	// Update color mode button
	if (typeof (json.color_mode) !== 'undefined' && json.color_mode !== null) {
		const colorBtn = $('#color');
		if (colorBtn) {
			// ISP mode: 0 = color, 1 = b&w, so active when 0
			colorBtn.classList.toggle('active', json.color_mode == 0);
		}
	}

	// Update ircut button
	if (typeof (json.ircut_state) !== 'undefined' && json.ircut_state !== null) {
		const ircutBtn = $('#ircut');
		if (ircutBtn) {
			ircutBtn.classList.toggle('active', json.ircut_state == 1);
		}
	}

	// Update ir850 button
	if (typeof (json.ir850_state) !== 'undefined' && json.ir850_state !== null) {
		const ir850Btn = $('#ir850');
		if (ir850Btn) {
			ir850Btn.classList.toggle('active', json.ir850_state == 1);
		}
	}

	// Update ir940 button
	if (typeof (json.ir940_state) !== 'undefined' && json.ir940_state !== null) {
		const ir940Btn = $('#ir940');
		if (ir940Btn) {
			ir940Btn.classList.toggle('active', json.ir940_state == 1);
		}
	}

	// Update white LED button
	if (typeof (json.white_state) !== 'undefined' && json.white_state !== null) {
		const whiteBtn = $('#white');
		if (whiteBtn) {
			whiteBtn.classList.toggle('active', json.white_state == 1);
		}
	}

	// Update microphone button
	if (typeof (json.mic_enabled) !== 'undefined') {
		const micBtn = $('#microphone');
		if (micBtn) {
			micBtn.classList.remove('pending');
			const isActive = json.mic_enabled === true;
			micBtn.classList.toggle('active', isActive);
			const img = micBtn.querySelector('img');
			if (img) {
				img.src = isActive ? '/a/mic.svg' : '/a/mic-mute.svg';
			}
		}
	}

	// Update speaker button
	if (typeof (json.spk_enabled) !== 'undefined') {
		const spkBtn = $('#speaker');
		if (spkBtn) {
			spkBtn.classList.remove('pending');
			const isActive = json.spk_enabled === true;
			spkBtn.classList.toggle('active', isActive);
			const img = spkBtn.querySelector('img');
			if (img) {
				img.src = isActive ? '/a/volume-up.svg' : '/a/volume-mute.svg';
			}
		}
	}

	// Update Auto button
	if (typeof (json.daynight_enabled) !== 'undefined' && json.daynight_enabled !== null) {
		const autoBtn = $('#auto');
		if (autoBtn) {
			autoBtn.classList.toggle('active', json.daynight_enabled == 1);
		}
	}
}

function startHeartbeatSse() {
	if (heartbeatSource) return;
	heartbeatSource = new EventSource(HeartBeatEndpoint);
	heartbeatSource.onmessage = (event) => {
		try {
			currentReconnectDelay = HeartBeatReconnectDelay;
			updateHeartbeatUi(JSON.parse(event.data));
		} catch (error) {
			console.error('Heartbeat SSE payload error', error);
		}
	};
	heartbeatSource.onerror = (error) => {
		console.error('Heartbeat SSE error', error);
		heartbeatSource.close();
		heartbeatSource = null;
		console.log(`Reconnecting in ${currentReconnectDelay / 1000}s`);
		setTimeout(startHeartbeatSse, currentReconnectDelay);
		// Double the delay for next failure, capped at max
		currentReconnectDelay = Math.min(currentReconnectDelay * 2, HeartBeatMaxReconnectDelay);
	};
}

function cleanupHeartbeatResources() {
	if (heartbeatSource) {
		heartbeatSource.close();
		heartbeatSource = null;
	}
	currentReconnectDelay = HeartBeatReconnectDelay;
}

window.addEventListener('beforeunload', cleanupHeartbeatResources);
window.addEventListener('pagehide', cleanupHeartbeatResources);

document.addEventListener('visibilitychange', () => {
	if (document.hidden) {
		cleanupHeartbeatResources();
	} else {
		heartbeat();
	}
});

function heartbeat() {
	startHeartbeatSse();
}

function initCopyToClipboard() {
	const clipboard = window.thinginoClipboard;
	$$(".cb").forEach(function (el) {
		el.title = "Click to copy to clipboard";
		el.addEventListener("click", function (ev) {
			ev.preventDefault();
			const target = ev.currentTarget || ev.target;
			const text = target && target.textContent ? target.textContent : '';
			if (!text || !clipboard || typeof clipboard.copy !== 'function') return;
			if (target && typeof target.animate === 'function') {
				target.animate({ backgroundColor: '#f80' }, 250);
			}
			clipboard.copy(text).catch(err => {
				if (typeof console !== 'undefined' && typeof console.warn === 'function') {
					console.warn('Clipboard copy failed', err);
				}
			});
		})
	})
}

// Shared quick actions for the Send modal to avoid duplicating markup.
const sendModalTargets = [
	{ key: 'email', label: 'Email', icon: 'bi bi-envelope-at' },
	{ key: 'ftp', label: 'FTP', icon: 'bi bi-postage' },
	{ key: 'mqtt', label: 'MQTT', icon: 'bi bi-postage' },
	{ key: 'ntfy', label: 'Ntfy', icon: 'bi bi-postage' },
	{ key: 'storage', label: 'Storage', icon: 'bi bi-sd-card' },
	{ key: 'telegram', label: 'Telegram', icon: 'bi bi-telegram' },
	{ key: 'webhook', label: 'Webhook', icon: 'bi bi-postage' }
];

let busyBarCtx = null;
let busyBarTimeout = null;
const BUSY_BAR_TTL = 20000; // 20 seconds

function ensureBusyBar() {
	if (busyBarCtx) return busyBarCtx;
	const barEl = document.createElement('div');
	barEl.id = 'thinginoBusyBar';
	barEl.style.cssText = 'position:fixed;top:0;left:0;right:0;height:4px;z-index:9999;background:#000;overflow:hidden;';
	barEl.innerHTML = '<div class="progress-bar" style="width:0;height:100%;background:linear-gradient(90deg,#0d6efd,#0dcaf0);transition:width 0.3s ease;"></div>';
	document.body.insertBefore(barEl, document.body.firstChild);
	const progressBar = barEl.querySelector('.progress-bar');
	busyBarCtx = { barEl, progressBar };
	return busyBarCtx;
}

function showBusy(message) {
	const ctx = ensureBusyBar();

	// Clear any existing timeout
	if (busyBarTimeout) {
		clearTimeout(busyBarTimeout);
		busyBarTimeout = null;
	}

	// Animate progress bar
	ctx.progressBar.style.width = '0%';
	setTimeout(() => ctx.progressBar.style.width = '70%', 10);

	// Set timeout to auto-hide with warning
	busyBarTimeout = setTimeout(() => {
		console.warn('Busy bar timeout reached - auto-hiding after', BUSY_BAR_TTL / 1000, 'seconds');
		hideBusy();
		if (typeof showAlert === 'function') {
			showAlert('warning', 'Operation timed out. Please try again or check your connection.', 8000);
		} else {
			alert('Operation timed out. Please try again or check your connection.');
		}
	}, BUSY_BAR_TTL);
}

function hideBusy() {
	// Clear the timeout when manually hiding
	if (busyBarTimeout) {
		clearTimeout(busyBarTimeout);
		busyBarTimeout = null;
	}

	if (!busyBarCtx) {
		console.warn('hideBusy: busyBarCtx is null');
		return;
	}

	// Complete the progress bar then hide
	busyBarCtx.progressBar.style.width = '100%';
	setTimeout(() => {
		if (busyBarCtx && busyBarCtx.progressBar) {
			busyBarCtx.progressBar.style.width = '0%';
		}
	}, 300);
}

window.showBusy = showBusy;
window.hideBusy = hideBusy;

// Universal slider modal system
let sliderModalInstance = null;
let sliderModalElement = null;

function ensureSliderModal() {
	if (sliderModalElement) return sliderModalElement;

	let modal = $('#thinginoSliderModal');
	if (modal) {
		sliderModalElement = modal;
		return modal;
	}

	modal = document.createElement('div');
	modal.className = 'modal fade';
	modal.id = 'thinginoSliderModal';
	modal.tabIndex = -1;
	modal.setAttribute('aria-hidden', 'true');
	modal.innerHTML = `
		<div class="modal-dialog modal-dialog-centered">
			<div class="modal-content">
				<div class="modal-header">
					<h5 class="modal-title" id="sliderModalTitle"></h5>
					<button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
				</div>
				<div class="modal-body">
					<div class="d-flex justify-content-between mb-2">
						<span id="sliderModalMin"></span>
						<span class="fw-bold" id="sliderModalValue"></span>
						<span id="sliderModalMax"></span>
					</div>
					<input type="range" id="sliderModalRange" class="form-range">
				</div>
				<div class="modal-footer">
					<button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
				</div>
			</div>
		</div>`;
	document.body.appendChild(modal);
	sliderModalElement = modal;

	if (window.bootstrap && window.bootstrap.Modal) {
		sliderModalInstance = new bootstrap.Modal(modal);
	}

	return modal;
}

function openSliderModal(inputId) {
	const input = $('#' + inputId);
	if (!input) return;

	const min = parseInt(input.dataset.min) || parseInt(input.getAttribute('min')) || 0;
	const max = parseInt(input.dataset.max) || parseInt(input.getAttribute('max')) || 100;
	const step = parseInt(input.dataset.step) || parseInt(input.getAttribute('step')) || 1;
	const label = input.parentElement.parentElement.querySelector('label')?.textContent || 'Value';

	const modal = ensureSliderModal();
	const slider = $('#sliderModalRange');
	const valueDisplay = $('#sliderModalValue');
	const titleEl = $('#sliderModalTitle');
	const minEl = $('#sliderModalMin');
	const maxEl = $('#sliderModalMax');

	if (!slider) return;

	titleEl.textContent = label;
	minEl.textContent = min;
	maxEl.textContent = max;
	slider.min = min;
	slider.max = max;
	slider.step = step;
	slider.value = input.value || min;
	valueDisplay.textContent = slider.value;

	// Store initial value
	const initialValue = input.value;

	// Only update display while sliding, don't update input
	slider.oninput = function() {
		valueDisplay.textContent = this.value;
	};

	// Remove old hidden listener if exists
	const oldHiddenHandler = sliderModalElement?._hiddenHandler;
	if (oldHiddenHandler) {
		sliderModalElement.removeEventListener('hidden.bs.modal', oldHiddenHandler);
	}

	// Update input only when modal closes
	const hiddenHandler = function() {
		const finalValue = slider.value;
		if (finalValue !== initialValue) {
			input.value = finalValue;
			input.dispatchEvent(new Event('change', { bubbles: true }));
		}
	};

	// Store handler reference for cleanup
	if (sliderModalElement) {
		sliderModalElement._hiddenHandler = hiddenHandler;
		sliderModalElement.addEventListener('hidden.bs.modal', hiddenHandler, { once: true });
	}

	if (sliderModalInstance) {
		sliderModalInstance.show();
	}
}

// Initialize slider buttons on page load
function attachSliderButtons(root = document) {
	root.querySelectorAll('.number-range .dropdown-toggle').forEach(button => {
		if (button.dataset.sliderInitialized) return;
		button.dataset.sliderInitialized = 'true';
		button.addEventListener('click', (e) => {
			e.preventDefault();
			const input = button.closest('.input-group')?.querySelector('input[type="text"]');
			if (input && input.id) {
				openSliderModal(input.id);
			}
		});
	});
}

document.addEventListener('DOMContentLoaded', () => {
	attachSliderButtons();
});

window.attachSliderButtons = attachSliderButtons;

// Unified slider initialization function (deprecated - kept for compatibility)
function initSlider(id) {
	const input = $('#' + id);
	const slider = $('#' + id + '-slider');
	const sliderValue = $('#' + id + '-slider-value');

	if (!input || !slider || !sliderValue) return;

	const min = parseInt(slider.getAttribute('min')) || 0;
	const max = parseInt(slider.getAttribute('max')) || 100;

	slider.addEventListener('input', function() {
		input.value = this.value;
		sliderValue.textContent = this.value;
	});

	input.addEventListener('input', function() {
		const val = parseInt(this.value) || min;
		const clampedVal = Math.max(min, Math.min(max, val));
		slider.value = clampedVal;
		sliderValue.textContent = clampedVal;
	});
}

function initSliders(sliderIds) {
	if (Array.isArray(sliderIds)) {
		sliderIds.forEach(initSlider);
	}
}

window.initSlider = initSlider;
window.initSliders = initSliders;

function ensureSendModal() {
	if ($('#sendModal')) return;
	const modal = document.createElement('div');
	modal.className = 'modal fade';
	modal.id = 'sendModal';
	modal.tabIndex = -1;
	modal.setAttribute('aria-labelledby', 'sendModalLabel');
	modal.setAttribute('aria-hidden', 'true');
	modal.innerHTML = `
	  <div class="modal-dialog modal-lg">
	    <div class="modal-content">
	      <div class="modal-header">
	        <h5 class="modal-title" id="sendModalLabel">Send snapshot/videoclip to...</h5>
	        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
	      </div>
	      <div class="modal-body">
	        <div class="row g-2" id="send-modal-grid"></div>
	      </div>
	    </div>
	  </div>`;
	document.body.appendChild(modal);
}

function buildSendModalGrid() {
	ensureSendModal();
	const grid = $('#send-modal-grid');
	if (!grid) return;

	const createIcon = (className) => {
		const icon = document.createElement('i');
		icon.className = className;
		return icon;
	};

	grid.innerHTML = '';

	sendModalTargets.forEach(target => {
		const col = document.createElement('div');
		col.className = 'col-12 col-lg-6';

		const group = document.createElement('div');
		group.className = 'btn-group d-flex gap-1';
		group.setAttribute('role', 'group');

		const mainBtn = document.createElement('button');
		mainBtn.type = 'button';
		mainBtn.className = 'btn btn-secondary text-start w-100';
		mainBtn.dataset.sendto = target.key;
		mainBtn.title = 'Send as configured';
		mainBtn.appendChild(createIcon(target.icon));
		mainBtn.appendChild(document.createTextNode(` ${target.label}`));
		group.appendChild(mainBtn);

		const photoBtn = document.createElement('button');
		photoBtn.type = 'button';
		photoBtn.className = 'btn btn-secondary flex-shrink-0';
		photoBtn.dataset.sendto = target.key;
		photoBtn.dataset.type = 'photo';
		photoBtn.title = 'Send photo only';
		photoBtn.appendChild(createIcon('bi bi-image'));
		group.appendChild(photoBtn);

		const videoBtn = document.createElement('button');
		videoBtn.type = 'button';
		videoBtn.className = 'btn btn-secondary flex-shrink-0';
		videoBtn.dataset.sendto = target.key;
		videoBtn.dataset.type = 'video';
		videoBtn.title = 'Send video only';
		videoBtn.appendChild(createIcon('bi bi-film'));
		group.appendChild(videoBtn);

		const configLink = document.createElement('a');
		configLink.className = 'btn btn-secondary flex-shrink-0';
		configLink.href = `/tool-send2.html`;
		configLink.title = 'Configure';
		configLink.appendChild(createIcon('bi bi-gear'));
		group.appendChild(configLink);

		col.appendChild(group);
		grid.appendChild(col);
	});

	const downloadCol = document.createElement('div');
	downloadCol.className = 'col-12 col-lg-6';
	const downloadGroup = document.createElement('div');
	downloadGroup.className = 'btn-group d-flex gap-1';
	downloadGroup.setAttribute('role', 'group');

	const downloadLinkCh0 = document.createElement('a');
	downloadLinkCh0.className = 'btn btn-secondary w-100 text-start';
	downloadLinkCh0.href = '/x/dl0.jpg';
	downloadLinkCh0.target = '_blank';
	downloadLinkCh0.title = 'Download main stream';
	downloadLinkCh0.appendChild(createIcon('bi bi-download'));
	downloadLinkCh0.appendChild(document.createTextNode(' Download Ch0'));
	downloadGroup.appendChild(downloadLinkCh0);

	const downloadLinkCh1 = document.createElement('a');
	downloadLinkCh1.className = 'btn btn-secondary w-100 text-start';
	downloadLinkCh1.href = '/x/dl1.jpg';
	downloadLinkCh1.target = '_blank';
	downloadLinkCh1.download = 'ch1-snapshot.jpg';
	downloadLinkCh1.title = 'Download substream';
	downloadLinkCh1.appendChild(createIcon('bi bi-download'));
	downloadLinkCh1.appendChild(document.createTextNode(' Download Ch1'));
	downloadGroup.appendChild(downloadLinkCh1);

	downloadCol.appendChild(downloadGroup);
	grid.appendChild(downloadCol);
}

function ensureDebugControl(attempt = 0) {
	const debugPanels = $$('.ui-debug');
	if (!debugPanels.length) return;
	debugPanels.forEach(panel => panel.classList.add('d-none'));
	const footerStack = $('#footer-action-stack');
	if (!footerStack) {
		if (attempt < 20) {
			window.setTimeout(() => ensureDebugControl(attempt + 1), 150);
		}
		return;
	}
	let debugBtn = $('#debug');
	if (!debugBtn) {
		debugBtn = document.createElement('button');
		debugBtn.type = 'button';
		debugBtn.id = 'debug';
		debugBtn.value = '1';
		debugBtn.title = 'Debug info';
		debugBtn.className = 'btn btn-outline-secondary btn-sm w-100';
		debugBtn.innerHTML = '<i class="bi bi-bug"></i> Debug';
		footerStack.appendChild(debugBtn);
	} else if (debugBtn.parentElement !== footerStack) {
		footerStack.appendChild(debugBtn);
	}
	if (debugBtn.dataset.bound === 'true') return;
	debugBtn.dataset.bound = 'true';
	debugBtn.addEventListener('click', ev => {
		ev.preventDefault();
		const ctx = ensureDebugModalStructure();
		const isVisible = ctx.modalEl.classList.contains('show');
		if (isVisible) {
			hideDebugModal(ctx);
			return;
		}
		ctx.buttonRef = debugBtn;
		populateDebugModalContent();
		debugBtn.classList.add('active');
		showDebugModal(ctx);
	});
}

const ConfirmDefaults = {
	title: 'Confirm action',
	message: 'Are you sure you want to continue?',
	confirmLabel: 'Continue',
	cancelLabel: 'Cancel',
	intent: 'danger'
};

let confirmModalCtx = null;
const confirmProcessedElements = new WeakSet();
const confirmFormSubmitters = new WeakMap();
let confirmMutationObserver = null;
let confirmScanScheduled = false;

function ensureConfirmModalStructure() {
	if (confirmModalCtx) return confirmModalCtx;
	const modalEl = document.createElement('div');
	modalEl.id = 'thinginoConfirmModal';
	modalEl.className = 'modal fade';
	modalEl.tabIndex = -1;
	modalEl.setAttribute('aria-hidden', 'true');
	modalEl.innerHTML = `
	  <div class="modal-dialog modal-dialog-centered">
	    <div class="modal-content">
	      <div class="modal-header">
	        <h5 class="modal-title" data-confirm-title>${ConfirmDefaults.title}</h5>
	        <button type="button" class="btn-close" data-confirm-close aria-label="Close"></button>
	      </div>
	      <div class="modal-body">
	        <p class="mb-0" data-confirm-message>${ConfirmDefaults.message}</p>
	      </div>
	      <div class="modal-footer gap-2">
	        <button type="button" class="btn btn-outline-secondary" data-confirm-cancel>${ConfirmDefaults.cancelLabel}</button>
	        <button type="button" class="btn btn-primary" data-confirm-accept>${ConfirmDefaults.confirmLabel}</button>
	      </div>
	    </div>
	  </div>`;
	const mountTarget = document.body || document.documentElement;
	mountTarget.appendChild(modalEl);
	const ctx = {
		modalEl,
		titleEl: modalEl.querySelector('[data-confirm-title]'),
		messageEl: modalEl.querySelector('[data-confirm-message]'),
		confirmBtn: modalEl.querySelector('[data-confirm-accept]'),
		cancelBtn: modalEl.querySelector('[data-confirm-cancel]'),
		closeBtn: modalEl.querySelector('[data-confirm-close]'),
		modalInstance: null
	};
	if (window.bootstrap && window.bootstrap.Modal) {
		ctx.modalInstance = window.bootstrap.Modal.getOrCreateInstance(modalEl);
	}
	if (ctx.closeBtn && (!window.bootstrap || !window.bootstrap.Modal)) {
		ctx.closeBtn.addEventListener('click', ev => {
			ev.preventDefault();
			hideConfirmModalInstant(ctx);
		});
	}
	confirmModalCtx = ctx;
	return ctx;
}

function hideConfirmModalInstant(ctx) {
	if (!ctx || !ctx.modalEl) return;
	ctx.modalEl.classList.remove('show');
	ctx.modalEl.style.display = 'none';
	ctx.modalEl.setAttribute('aria-hidden', 'true');
	ctx.modalEl.removeAttribute('aria-modal');
}

function resolveConfirmIntentClass(intent) {
	switch ((intent || ConfirmDefaults.intent).toLowerCase()) {
		case 'warning':
			return 'btn-warning';
		case 'success':
			return 'btn-success';
		case 'primary':
			return 'btn-primary';
		case 'danger':
		default:
			return 'btn-danger';
	}
}

function normalizeConfirmOptions(messageOrOptions, extraOptions) {
	const normalized = { ...ConfirmDefaults };
	const assignFrom = (source) => {
		if (!source) return;
		if (typeof source === 'string') {
			normalized.message = source;
			return;
		}
		if (typeof source !== 'object') return;
		if (source.title) normalized.title = source.title;
		if (source.message) normalized.message = source.message;
		if (source.confirmLabel) normalized.confirmLabel = source.confirmLabel;
		if (source.cancelLabel) normalized.cancelLabel = source.cancelLabel;
		if (source.intent) normalized.intent = source.intent;
	};
	assignFrom(messageOrOptions);
	assignFrom(extraOptions);
	if (!normalized.message) normalized.message = ConfirmDefaults.message;
	return normalized;
}

function showConfirmDialog(options) {
	const ctx = ensureConfirmModalStructure();
	if (!ctx) {
		return Promise.resolve(true);
	}
	ctx.titleEl.textContent = options.title || ConfirmDefaults.title;
	ctx.messageEl.textContent = options.message || ConfirmDefaults.message;
	ctx.confirmBtn.textContent = options.confirmLabel || ConfirmDefaults.confirmLabel;
	ctx.cancelBtn.textContent = options.cancelLabel || ConfirmDefaults.cancelLabel;
	ctx.confirmBtn.className = 'btn ' + resolveConfirmIntentClass(options.intent);
	return new Promise(resolve => {
		let finished = false;
		const handleConfirm = ev => {
			if (ev) ev.preventDefault();
			finalize(true);
		};
		const handleCancel = ev => {
			if (ev) ev.preventDefault();
			finalize(false);
		};
		const handleHidden = () => finalize(false);
		const cleanup = () => {
			ctx.confirmBtn.removeEventListener('click', handleConfirm);
			ctx.cancelBtn.removeEventListener('click', handleCancel);
			if (ctx.closeBtn) ctx.closeBtn.removeEventListener('click', handleCancel);
			ctx.modalEl.removeEventListener('hidden.bs.modal', handleHidden);
		};
		const hideModal = () => {
			if (ctx.modalInstance && window.bootstrap && window.bootstrap.Modal) {
				ctx.modalInstance.hide();
			} else {
				hideConfirmModalInstant(ctx);
			}
		};
		const finalize = result => {
			if (finished) return;
			finished = true;
			cleanup();
			hideModal();
			resolve(result);
		};
		ctx.confirmBtn.addEventListener('click', handleConfirm);
		ctx.cancelBtn.addEventListener('click', handleCancel);
		if (ctx.closeBtn) ctx.closeBtn.addEventListener('click', handleCancel);
		ctx.modalEl.addEventListener('hidden.bs.modal', handleHidden, { once: true });
		if (window.bootstrap && window.bootstrap.Modal) {
			ctx.modalInstance = window.bootstrap.Modal.getOrCreateInstance(ctx.modalEl);
			ctx.modalInstance.show();
		} else {
			ctx.modalEl.classList.add('show');
			ctx.modalEl.style.display = 'block';
			ctx.modalEl.removeAttribute('aria-hidden');
			ctx.modalEl.setAttribute('aria-modal', 'true');
		}
	});
}

function getElementConfirmOptions(element) {
	if (!element || !element.dataset) return {};
	const opts = {};
	const { dataset } = element;
	if (dataset.confirmMessage) opts.message = dataset.confirmMessage;
	else if (dataset.confirm) opts.message = dataset.confirm;
	if (dataset.confirmTitle) opts.title = dataset.confirmTitle;
	if (dataset.confirmIntent) opts.intent = dataset.confirmIntent;
	if (dataset.confirmConfirm) opts.confirmLabel = dataset.confirmConfirm;
	else if (dataset.confirmAction) opts.confirmLabel = dataset.confirmAction;
	if (dataset.confirmCancel) opts.cancelLabel = dataset.confirmCancel;
	return opts;
}

function isSubmitControl(element) {
	if (!element) return false;
	const tag = element.tagName;
	const type = (element.getAttribute('type') || '').toLowerCase();
	if (tag === 'BUTTON') {
		return type === '' || type === 'submit';
	}
	if (tag === 'INPUT') {
		return type === 'submit' || type === 'image';
	}
	return false;
}

function attachConfirmTrigger(element) {
	if (!element || confirmProcessedElements.has(element)) return;
	const skip = element.dataset && (element.dataset.confirmSkip === 'true' || element.dataset.confirmSkip === '1');
	if (skip) return;
	confirmProcessedElements.add(element);
	const form = element.closest('form');
	if (form && isSubmitControl(element)) {
		bindConfirmFormSubmit(form, element);
		return;
	}
	bindConfirmClick(element);
}

function bindConfirmClick(element) {
	element.addEventListener('click', ev => handleConfirmableClick(ev, element));
}

function bindConfirmFormSubmit(form, trigger) {
	let submitters = confirmFormSubmitters.get(form);
	if (!submitters) {
		submitters = new Set();
		confirmFormSubmitters.set(form, submitters);
		form.addEventListener('submit', ev => handleConfirmableSubmit(ev, form), true);
	}
	submitters.add(trigger);
}

async function handleConfirmableClick(ev, element) {
	if (element.dataset.confirmBypass === '1') {
		delete element.dataset.confirmBypass;
		return;
	}
	if (element.disabled) return;
	ev.preventDefault();
	ev.stopImmediatePropagation();
	const options = getElementConfirmOptions(element);
	const confirmed = await window.confirm(options.message, options);
	if (!confirmed) return;
	element.dataset.confirmBypass = '1';
	window.setTimeout(() => {
		if (typeof element.click === 'function') {
			element.click();
			return;
		}
		if (element.tagName === 'A' && element.href) {
			if (element.target && element.target !== '_self') {
				window.open(element.href, element.target, 'noopener');
			} else {
				window.location.href = element.href;
			}
		}
	}, 0);
}

async function handleConfirmableSubmit(ev, form) {
	if (form.dataset.confirmBypass === '1') {
		delete form.dataset.confirmBypass;
		return;
	}
	const submitters = confirmFormSubmitters.get(form);
	if (!submitters || !submitters.size) return;
	const trigger = ev.submitter;
	if (!trigger || !submitters.has(trigger)) return;
	ev.preventDefault();
	ev.stopImmediatePropagation();
	const options = getElementConfirmOptions(trigger);
	const confirmed = await window.confirm(options.message, options);
	if (!confirmed) return;
	form.dataset.confirmBypass = '1';
	const submitAgain = () => {
		if (typeof form.requestSubmit === 'function') {
			form.requestSubmit(trigger);
		} else {
			form.submit();
		}
	};
	window.setTimeout(submitAgain, 0);
}

function scanConfirmTriggers(root = document) {
	if (!root || typeof root.querySelectorAll !== 'function') return;
	root.querySelectorAll('.confirm').forEach(attachConfirmTrigger);
}

function scheduleConfirmScan() {
	if (confirmScanScheduled) return;
	confirmScanScheduled = true;
	const run = () => {
		confirmScanScheduled = false;
		scanConfirmTriggers();
	};
	if (typeof window.requestAnimationFrame === 'function') {
		window.requestAnimationFrame(run);
	} else {
		window.setTimeout(run, 100);
	}
}

function initConfirmObserver() {
	if (confirmMutationObserver || !window.MutationObserver) return;
	const target = document.body || document.documentElement;
	if (!target) return;
	confirmMutationObserver = new MutationObserver(mutations => {
		for (const mutation of mutations) {
			if (mutation.type === 'childList' && mutation.addedNodes && mutation.addedNodes.length) {
				scheduleConfirmScan();
				break;
			}
		}
	});
	confirmMutationObserver.observe(target, { childList: true, subtree: true });
}

const nativeConfirm = (typeof window !== 'undefined' && typeof window.confirm === 'function')
	? window.confirm.bind(window)
	: () => true;

function thinginoConfirm(messageOrOptions, extraOptions) {
	const options = normalizeConfirmOptions(messageOrOptions, extraOptions);
	return showConfirmDialog(options);
}

thinginoConfirm.defaults = ConfirmDefaults;
thinginoConfirm.normalize = normalizeConfirmOptions;
thinginoConfirm.fromElement = getElementConfirmOptions;
thinginoConfirm.scan = scanConfirmTriggers;

window.nativeConfirm = nativeConfirm;
window.confirm = thinginoConfirm;
window.confirmAsync = thinginoConfirm;
window.thinginoConfirm = thinginoConfirm;

(() => {
	function initAll() {
		function toggleAuto(el) {
			const id = el.dataset.for;
			const p = $('#' + id);
			const s = $('#' + id + '-show');
			if (el.checked) {
				el.dataset.value = r.value;
				p.value = 'auto';
				p.disabled = true;
				s.textContent = '--';
			} else {
				p.value = el.dataset.value;
				p.disabled = false;
				s.textContent = p.value;
			}
		}

		$$('form,input').forEach(el => el.autocomplete = 'off');

		const tooltipTriggerList = $$('[data-bs-toggle="tooltip"]')
		const tooltipList = [...tooltipTriggerList].map(tooltipTriggerEl => new bootstrap.Tooltip(tooltipTriggerEl))

		// Populate the shared Send modal once the DOM is ready.
		buildSendModalGrid();

		// ranges
		$$('input[type=range]').forEach(el => {
			el.addEventListener('change', ev => {
				if ($('#' + ev.target.id + '-show'))
					$('#' + ev.target.id + '-show').textContent = ev.target.value
			})
			el.addEventListener('input', ev => {
				if ($('#' + ev.target.id + '-show'))
					$('#' + ev.target.id + '-show').textContent = ev.target.value
			});
		});

		// scan for confirmable buttons and observe future additions
		scanConfirmTriggers();
		initConfirmObserver();

		// toggle auto value
		$$('input.auto-value').forEach(el => {
			el.addEventListener('click', ev => toggleAuto(ev.target));
			toggleAuto(el);
		});

		// show password when checkbox is checked
		$$('.password input[type=checkbox]').forEach(el => {
			el.addEventListener('change', ev => {
				const pw = $('#' + ev.target.dataset['for']);
				pw.type = (el.checked) ? 'text' : 'password';
				pw.focus();
			});
		});

		// reload window when refresh button is clicked
		$$('.refresh').forEach(el => {
			el.addEventListener('click', ev => {
				window.location.reload()
			});
		});

		// set links to external resources to open in a new window.
		$$('a[href^=http]').forEach(el => el.target = '_blank');

		// handle sendto buttons
		$$("button[data-sendto]").forEach(el => {
			if (el.dataset.sendtoBypass === '1' || el.dataset.sendtoBypass === 'true') return;
			el.addEventListener('click', async ev => {
				ev.preventDefault();
				const options = getElementConfirmOptions(el);
				const confirmed = await confirm(options.message || 'Send this action now?', options);
				if (!confirmed) return;
				const params = { to: el.dataset.sendto };
				if (el.dataset.type) {
					params.type = el.dataset.type;
				}
				fetch("/x/send.cgi", {
					method: 'POST',
					headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
					body: new URLSearchParams(params).toString()
				})
					.then(res => res.json())
					.then(data => console.log(data))
			});
		});

		// async output of a command running on camera
		const outputEl = $('pre#output');
		if (outputEl) {
			let commandInFlight = false;

			async function* makeTextFileLineIterator(url) {
				const td = new TextDecoder('utf-8');
				const response = await fetch(url);
				const rd = response.body.getReader();
				let { value: chunk, done: readerDone } = await rd.read();
				chunk = chunk ? td.decode(chunk) : '';
				const re = /\r\n|\n|\r/gm;
				let startIndex = 0;
				let result;
				for (; ;) {
					result = re.exec(chunk);
					if (!result) {
						if (readerDone) break;
						let remainder = chunk.substring(startIndex);
						({ value: chunk, done: readerDone } = await rd.read());
						chunk = remainder + (chunk ? td.decode(chunk) : '');
						startIndex = re.lastIndex = 0;
						continue;
					}
					const lineContent = chunk.substring(startIndex, result.index);
					const lineEnding = result[0];
					yield { line: lineContent, ending: lineEnding };
					startIndex = re.lastIndex;
				}
				if (startIndex < chunk.length) yield { line: chunk.substring(startIndex), ending: '' };
			}

			const finalizeStream = () => {
				commandInFlight = false;
				if ('true' === outputEl.dataset['reboot']) {
					window.location.href = '/x/reboot.cgi';
				} else {
					outputEl.innerHTML += '\n--- finished ---\n';
				}
				outputEl.dispatchEvent(new CustomEvent('thingino:command-finished'));
			};

			async function streamCommand(url) {
				if (!url || commandInFlight) return;
				commandInFlight = true;
				try {
					for await (let { line, ending } of makeTextFileLineIterator(url)) {
						const re1 = /\u001b\[1;(\d+)m/;
						const re2 = /\u001b\[0m/;
						line = line.replace(re1, '<span class="ansi-$1">').replace(re2, '</span>')

						// Handle carriage return - replace last line instead of adding new
						if (ending === '\r') {
							// Carriage return: replace the last line
							const lines = outputEl.innerHTML.split('\n');
							if (lines.length > 0) {
								lines[lines.length - 1] = line;
								outputEl.innerHTML = lines.join('\n');
							} else {
								outputEl.innerHTML = line;
							}
						} else {
							// Normal newline: add new line
							outputEl.innerHTML += line + '\n';
						}

						outputEl.scrollTop = outputEl.scrollHeight;
					}
				} finally {
					finalizeStream();
				}
			}

			const startStreaming = (command, options = {}) => {
				if (commandInFlight) return;
				const streamOverride = options.stream || outputEl.dataset['stream'] || '';
				const encodedOverride = options.encoded || outputEl.dataset['encoded'] || '';
				const resolvedCommand = command || outputEl.dataset['cmd'] || '';
				let streamUrl = '';
				let encodedValue = '';

				if (streamOverride) {
					streamUrl = streamOverride;
				} else if (encodedOverride) {
					encodedValue = encodedOverride;
					streamUrl = '/x/run.cgi?cmd=' + encodedOverride;
				} else if (resolvedCommand) {
					encodedValue = btoa(resolvedCommand);
					streamUrl = '/x/run.cgi?cmd=' + encodedValue;
				} else {
					return;
				}
				if (options.reboot !== undefined) {
					outputEl.dataset['reboot'] = options.reboot ? 'true' : 'false';
				}
				outputEl.dataset['cmd'] = resolvedCommand;
				outputEl.dataset['stream'] = streamOverride || '';
				outputEl.dataset['encoded'] = encodedValue;
				outputEl.innerHTML = '';
				outputEl.dispatchEvent(new CustomEvent('thingino:command-start', { detail: { cmd: resolvedCommand } }));
				streamCommand(streamUrl);
			};

			if (outputEl.dataset['cmd'] || outputEl.dataset['stream'] || outputEl.dataset['encoded']) {
				startStreaming(outputEl.dataset['cmd'] || '', {
					stream: outputEl.dataset['stream'] || '',
					encoded: outputEl.dataset['encoded'] || ''
				});
			}

			outputEl.addEventListener('thingino:start-command', ev => {
				const detail = ev.detail || {};
				if (detail.reboot !== undefined) {
					outputEl.dataset['reboot'] = detail.reboot ? 'true' : 'false';
				}
				if (detail.cmd || detail.stream || detail.encoded) {
					startStreaming(detail.cmd || '', {
						reboot: detail.reboot,
						stream: detail.stream,
						encoded: detail.encoded
					});
				}
			});
		}

		initCopyToClipboard()
		heartbeat()

		// setup recording button handlers
		$$('#recorder-ch0, #recorder-ch1').forEach(button => {
			button.addEventListener('click', function (e) {
				e.preventDefault();
				const channel = parseInt(this.dataset.channel);
				// State is managed by recordingState and will be toggled by toggleRecording
				toggleRecording(channel);
			});
		});

		// setup motion button handler
		const motionBtn = $('#motion');
		if (motionBtn) {
			motionBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleMotion(!motionBtn.classList.contains('active'));
			});
		}

		// setup privacy button handler
		const privacyBtn = $('#privacy');
		if (privacyBtn) {
			privacyBtn.addEventListener('click', ev => {
				ev.preventDefault();
				togglePrivacy(!privacyBtn.classList.contains('active'));
			});
		}

		// setup wireguard button handler
		const wireguardBtn = $('#wireguard');
		if (wireguardBtn) {
			wireguardBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleWireGuard(!wireguardBtn.classList.contains('active'));
			});
		}

		// setup daynight button handler
		const daynightBtn = $('#daynight');
		if (daynightBtn) {
			daynightBtn.addEventListener('click', ev => {
				ev.preventDefault();
				const currentlyNight = daynightBtn.classList.contains('is-night');
				const newMode = currentlyNight ? 'day' : 'night';
				toggleDayNight(newMode);
			});
		}

		// setup day mode button handler
		const dayBtn = $('#day');
		if (dayBtn) {
			dayBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleDayNight('day');
			});
		}

		// setup night mode button handler
		const nightBtn = $('#night');
		if (nightBtn) {
			nightBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleDayNight('night');
			});
		}

		// setup microphone button handler
		const micBtn = $('#microphone');
		if (micBtn) {
			micBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleAudio('microphone', !micBtn.classList.contains('active'));
			});
		}

		// setup speaker button handler
		const spkBtn = $('#speaker');
		if (spkBtn) {
			spkBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleAudio('speaker', !spkBtn.classList.contains('active'));
			});
		}

		ensureDebugControl();

		// setup camera control buttons (color, ircut, ir850, ir940, white)
		$$("#auto, #color, #ircut, #ir850, #ir940, #white").forEach(el => {
			if (el) {
				el.addEventListener('click', ev => {
					ev.preventDefault();
					toggleButton(el);
				});
			}
		});

		// setup theme toggle link handler
		const themeBtn = $('#theme-toggle');
		if (themeBtn) {
			themeBtn.addEventListener('click', ev => {
				ev.preventDefault();
				toggleTheme();
			});
		}

		updateRecordingIcons();
	}

	// Create universal alert area (uses existing global-message-overlay)
	function createAlertArea() {
		// The global-message-overlay is created by footer.js
		// This is just for compatibility - can be removed later
	}

	// Universal alert function - delegates to global message overlay
	window.showAlert = function(type, message, timeout = 6000) {
		if (!message) return;

		// Map alert types to variants
		const variantMap = {
			'success': 'success',
			'danger': 'danger',
			'warning': 'info',
			'info': 'info',
			'primary': 'info',
			'secondary': 'info'
		};

		const variant = variantMap[type] || 'info';

		// Use the global message system from footer.js
		if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
			window.thinginoFooter.showMessage(message, variant);
		} else {
			// Fallback: create and show message directly
			let el = $('#global-message-overlay');
			if (!el) {
				el = document.createElement('div');
				el.id = 'global-message-overlay';
				el.className = 'global-message-overlay';
				el.setAttribute('role', 'status');
				el.setAttribute('aria-live', 'polite');
				document.body.appendChild(el);
			}
			el.textContent = message;
			el.dataset.variant = variant;
			el.classList.add('show');
			setTimeout(() => el.classList.remove('show'), timeout);
		}
	};

	window.addEventListener('load', initAll)
	window.addEventListener('DOMContentLoaded', createAlertArea)

	document.addEventListener("visibilitychange", () => {
		if (document.hidden) {
			if ($('#preview'))
				$('#preview').src = ImageNoStream;
		} else {
			if ($('#preview'))
				$('#preview').src = '/x/ch0.mjpg';
		}
	});

	// Global modal focus management - prevent aria-hidden focus conflicts for all modals
	document.addEventListener('hide.bs.modal', (event) => {
		const modal = event.target;

		// Check if the modal element itself has focus
		if (document.activeElement === modal) {
			modal.blur();
		}

		// Also check for any focused elements within the modal
		const focusedElement = modal.querySelector(':focus');
		if (focusedElement) {
			focusedElement.blur();
		}
	});
})();
