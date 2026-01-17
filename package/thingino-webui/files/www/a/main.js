const ThreadRtsp = 1;
const ThreadVideo = 2;
const ThreadAudio = 4;
const ThreadOSD = 8;

let max = 0;

let recordingState = {
	ch0: false,
	ch1: false
};
const HeartBeatReconnectDelay = 2 * 1000;
const HeartBeatMaxReconnectDelay = 60 * 1000;
const HeartBeatEndpoint = '/x/json-heartbeat.cgi';
let heartbeatSource = null;
let currentReconnectDelay = HeartBeatReconnectDelay;

function $(n) {
	return document.querySelector(n)
}

function $$(n) {
	return document.querySelectorAll(n)
}

function ts() {
	return Math.floor(Date.now());
}

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms))
}

function setProgressBar(id, value, maxvalue, name) {
	let value_percent = Math.ceil(value / (maxvalue / 100));
	const el = $(id);
	el.setAttribute('aria-valuemin', '0');
	el.setAttribute('aria-valuemax', maxvalue);
	el.setAttribute('aria-valuenow', value);
	el.style.width = value_percent + '%';
	el.title = name + ': ' + value + 'KiB';
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

function dayNightIcon(mode) {
	switch ((mode || '').toString().toLowerCase()) {
		case 'day':
			return '☀️';
		case 'night':
			return '🌙';
		default:
			return '❔';
	}
}

function sendToApi(endpoint) {
	const xhr = new XMLHttpRequest();
	xhr.addEventListener('load', reqListener);
	xhr.open('GET', '//' + network_address + endpoint);
	xhr.setRequestHeader('Authorization', 'Basic ' + btoa('admin:'));
	xhr.send();
}

function reqListener(data) {
	console.log(data.responseText);
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

	/*
		// Save to server
		const payload = JSON.stringify({ webui: { theme: newTheme } });
		fetch('/x/json-config.cgi', {
			method: 'POST',
			headers: { 'Content-Type': 'application/json' },
			body: payload
		})
		.then(res => res.json())
		.then(data => {
			console.log('Theme saved:', data);
		})
		.catch(err => console.error('Theme save error', err));
	*/
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

function updateHeartbeatUi(json) {
	if (!json) return;
	if (json.time_now !== '') {
		const d = new Date(json.time_now * 1000);
		// Use device timezone if available, otherwise fall back to browser timezone
		const deviceTz = json.timezone?.replaceAll(' ', '_');
		let options = {
			year: "numeric",
			month: "short",
			day: "numeric",
			hour: "2-digit",
			minute: "2-digit",
			timeZone: deviceTz
		};
		$('#time-now').textContent = d.toLocaleString(navigator.language, options) + ' ' + json.timezone;
	}

	$('.progress-stacked.memory').title = 'Free memory: ' + json.mem_free + 'KiB'
	setProgressBar('#pb-memory-active', json.mem_active, json.mem_total, 'Memory Active');
	setProgressBar('#pb-memory-buffers', json.mem_buffers, json.mem_total, 'Memory Buffers');
	setProgressBar('#pb-memory-cached', json.mem_cached, json.mem_total, 'Memory Cached');

	$('.progress-stacked.overlay').title = 'Free overlay: ' + json.overlay_free + 'KiB'
	setProgressBar('#pb-overlay-used', json.overlay_used, json.overlay_total, 'Overlay Usage');

	$('.progress-stacked.extras').title = 'Free extras: ' + json.extras_free + 'KiB'
	setProgressBar('#pb-extras-used', json.extras_used, json.extras_total, 'Extras Usage');

	const hasBrightness = typeof (json.daynight_brightness) !== 'undefined' && json.daynight_brightness !== 'unknown' && json.daynight_brightness !== '';
	const hasTotalGain = typeof (json.total_gain) !== 'undefined' && json.total_gain !== 'unknown' && json.total_gain !== '' && json.total_gain >= 0;
	const hasMode = typeof (json.daynight_mode) !== 'undefined' && json.daynight_mode !== 'unknown' && json.daynight_mode !== '';
	if (hasTotalGain || hasBrightness || hasMode) {
		// const icon = dayNightIcon(json.daynight_mode);
		// const label = hasTotalGain ? `${icon} ${json.total_gain}` : (hasBrightness ? `${icon} ${json.daynight_brightness}` : icon);
		const label = hasTotalGain ? json.total_gain : (hasBrightness ? json.daynight_brightness : '---');
		$$('.dnd-gain').forEach(el => el.textContent = label);
	}

	if (typeof (json.uptime) !== 'undefined' && json.uptime !== '')
		$('#uptime').textContent = 'Uptime:️ ' + json.uptime;

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

	// Update daynight mode button
	if (typeof (json.daynight_mode) !== 'undefined') {
		const daynightBtn = $('#daynight');
		if (daynightBtn) {
			daynightBtn.classList.remove('pending');
			daynightBtn.classList.toggle('active', json.daynight_mode === 'night');

			// Update button text and icon based on photosensing state
			const daynightText = $('#daynight-text');
			const daynightIcon = daynightBtn.querySelector('i');
			const isNight = json.daynight_mode === 'night';
			const isAutoEnabled = json.daynight_enabled === true || json.daynight_enabled === 1;

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
	$$(".cb").forEach(function (el) {
		el.title = "Click to copy to clipboard";
		el.addEventListener("click", function (ev) {
			ev.target.preventDefault;
			ev.target.animate({ backgroundColor: '#f80' }, 250);
			let textArea = document.createElement("textarea");
			textArea.value = ev.target.textContent;
			textArea.style.position = "fixed";
			textArea.style.left = "-999999px";
			textArea.style.top = "-999999px";
			document.body.appendChild(textArea);
			textArea.focus();
			textArea.select();
			return new Promise((res, rej) => {
				document.execCommand('copy') ? res() : rej();
				textArea.remove();
			});
		})
	})
}

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

		// ask confirmation on action for .warning and .danger buttons
		$$('.btn-danger, .btn-warning, .confirm').forEach(el => {
			// for input, find its parent form and attach listener to it submit event
			if (el.nodeName === 'INPUT') {
				while (el.nodeName !== 'FORM') el = el.parentNode
				el.addEventListener('submit', ev => (!confirm('Are you sure?')) ? ev.preventDefault() : null)
			} else {
				el.addEventListener('click', ev => (!confirm('Are you sure?')) ? ev.preventDefault() : null)
			}
		});

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
			el.onclick = (ev) => {
				ev.preventDefault();
				if (!confirm("Are you sure?")) return false;
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
			}
		});

		// async output of a command running on camera
		if ($('pre#output[data-cmd]')) {
			const el = $('pre#output[data-cmd]');

			async function* makeTextFileLineIterator(url) {
				const td = new TextDecoder('utf-8');
				const response = await fetch(url);
				const rd = response.body.getReader();
				let { value: chunk, done: readerDone } = await rd.read();
				chunk = chunk ? td.decode(chunk) : '';
				const re = /\n|\r|\r\n/gm;
				let startIndex = 0;
				let result;
				try {
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
						yield chunk.substring(startIndex, result.index);
						startIndex = re.lastIndex;
					}
					if (startIndex < chunk.length) yield chunk.substring(startIndex);
				} finally {
					if ('true' === el.dataset['reboot']) {
						window.location.href = '/x/reboot.cgi'
					} else {
						el.innerHTML += '\n--- finished ---\n';
					}
				}
			}

			async function run() {
				for await (let line of makeTextFileLineIterator('/x/run.cgi?cmd=' + btoa(el.dataset['cmd']))) {
					const re1 = /\u001b\[1;(\d+)m/;
					const re2 = /\u001b\[0m/;
					line = line.replace(re1, '<span class="ansi-$1">').replace(re2, '</span>')
					el.innerHTML += line + '\n';
				}
			}

			run()
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

		// setup daynight button handler
		const daynightBtn = $('#daynight');
		if (daynightBtn) {
			daynightBtn.addEventListener('click', ev => {
				ev.preventDefault();
				const currentlyNight = daynightBtn.classList.contains('active');
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

		// setup debug toggle button handler
		const debugBtn = $('#debug');
		if (debugBtn) {
			debugBtn.addEventListener('click', ev => {
				ev.preventDefault();
				const currentlyDebug = debugBtn.classList.contains('active');
				if (currentlyDebug) {
					$('.ui-debug').classList.add('d-none');
					debugBtn.classList.remove('active');
				} else {
					$('.ui-debug').classList.remove('d-none');
					debugBtn.classList.add('active');
				}
			});
		}

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

	window.addEventListener('load', initAll)

	document.addEventListener("visibilitychange", () => {
		if (document.hidden) {
			if ($('#preview'))
				$('#preview').src = '/a/nostream.webp';
		} else {
			if ($('#preview'))
				$('#preview').src = '/x/ch0.mjpg';
		}
	});
})();
