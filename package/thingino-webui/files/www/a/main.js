const ThreadRtsp = 1;
const ThreadVideo = 2;
const ThreadAudio = 4;
const ThreadOSD = 8;

let max = 0;

// Recording state management
let recordingState = {
	ch0: false,
	ch1: false
};
const HeartBeatReconnectDelay = 5 * 1000;
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

	// Enable the element since it has a value from backend
	el.disabled = false;
	const wrapper = el.closest('.range, .select, .boolean, .file');
	if (wrapper) wrapper.classList.remove('disabled');

	if (el.type === "checkbox") {
		el.checked = value;
	} else {
		el.value = value;
		if (el.type === "range") {
			$(`${id}-show`).textContent = value;
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
	$$('#recorder-ch0, #recorder-ch1').forEach(checkbox => {
		const channel = parseInt(checkbox.dataset.channel);
		const isRecording = recordingState[`ch${channel}`];
		const label = $$(`label[for="${checkbox.id}"]`)[0];

		console.log(`Updating recorder ch${channel}: isRecording=${isRecording}, label=${label ? 'found' : 'not found'}`);

		if (label) {
			label.classList.toggle('recorder-active', isRecording);
		}

		checkbox.checked = isRecording;
	});
}

function updateRecordingState(state) {
	console.log('updateRecordingState called:', state);
	recordingState.ch0 = state.ch0;
	recordingState.ch1 = state.ch1;
	updateRecordingIcons();
}

function toggleRecording(channel) {
	const isRecording = recordingState[`ch${channel}`];
	const action = isRecording ? 'stop' : 'start';

	console.log(`toggleRecording called: channel=${channel}, currentState=${isRecording ? 'recording' : 'stopped'}, action=${action}`);

	const payload = isRecording
		? JSON.stringify({ mp4: { stop: { channel: channel } } })
		: JSON.stringify({ mp4: { start: { channel: channel } } });

	console.log(`Sending payload: ${payload}`);

	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
	.then(response => response.json())
	.then(data => {
		console.log(`Response received:`, data);
		if (data.mp4 && data.mp4[action]) {
			if (data.mp4[action] === 'ok') {
				console.log(`Recording ${action} successful on channel ${channel}`);
				// Update will happen via heartbeat
			} else {
				console.error('Recording control error:', data.mp4[action]);
				alert(`Failed to ${action} recording on channel ${channel}: ${data.mp4[action]}`);
			}
		} else {
			console.error('Unexpected response:', data);
			alert(`Failed to ${action} recording on channel ${channel}`);
		}
	})
	.catch(err => {
		console.error('Recording control failed:', err);
		alert(`Failed to ${action} recording on channel ${channel}`);
	});
}

function toggleMotion(state) {
	const payload = JSON.stringify({ motion: { enabled: state } });
	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
	.then(res => res.json())
	.then(data => {
		console.log(ts(), '<===', JSON.stringify(data));
		if (data.motion && data.motion.enabled !== undefined) {
			const el = $('#motion');
			if (el) el.checked = data.motion.enabled;
		}
	})
	.catch(err => console.error('Motion toggle error', err));
}

function togglePrivacy(state) {
	const payload = JSON.stringify({ privacy: { enabled: state } });
	fetch('/x/json-prudynt.cgi', {
		method: 'POST',
		headers: { 'Content-Type': 'application/json' },
		body: payload
	})
	.then(res => res.json())
	.then(data => {
		console.log(ts(), '<===', JSON.stringify(data));
		if (data.privacy && data.privacy.enabled !== undefined) {
			const el = $('#privacy');
			if (el) el.checked = data.privacy.enabled;
		}
	})
	.catch(err => console.error('Privacy toggle error', err));
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

	const hasDndGain = typeof (json.dnd_gain) !== 'undefined' && json.dnd_gain !== '-1';
	const hasMode = typeof (json.dnd_mode) !== 'undefined' && json.dnd_mode !== '';
	if (hasDndGain || hasMode) {
		const icon = dayNightIcon(json.dnd_mode);
		const label = hasDndGain ? `${icon} ${json.dnd_gain}` : icon;
		$$('.dnd_gain').forEach(el => el.textContent = label);
	}

	if (typeof (json.uptime) !== 'undefined' && json.uptime !== '')
		$('#uptime').textContent = 'Uptime:️ ' + json.uptime;

	// Update recording state
	updateRecordingState({
		ch0: json.rec_ch0 === true,
		ch1: json.rec_ch1 === true
	});
}

function startHeartbeatSse() {
	if (heartbeatSource) return;
	heartbeatSource = new EventSource(HeartBeatEndpoint);
	heartbeatSource.onmessage = (event) => {
		try {
			// Reset reconnect delay on successful message
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
	// Reset reconnect delay on cleanup
	currentReconnectDelay = HeartBeatReconnectDelay;
}

// Cleanup on page unload and visibility change
window.addEventListener('beforeunload', cleanupHeartbeatResources);
window.addEventListener('pagehide', cleanupHeartbeatResources);

// Pause heartbeat when page is hidden, resume when visible
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
			ev.target.animate({backgroundColor: '#f80'}, 250);
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

		// For .warning and .danger buttons, ask confirmation on action.
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
			el.onclick = (ev) => {
				ev.preventDefault();
				if (!confirm("Are you sure?")) return false;
				fetch("/x/send.cgi?" + new URLSearchParams({'to': el.dataset.sendto}).toString())
					.then(res => res.json())
					.then(data => console.log(data))
			}
		});

// debug button
		if ($('#debug'))
			$('#debug').addEventListener('change', ev => {
				ev.target.checked ?
					$('.ui-debug').classList.remove('d-none') :
					$('.ui-debug').classList.add('d-none') ;
			});

// async output of a command running on camera
		if ($('pre#output[data-cmd]')) {
			const el = $('pre#output[data-cmd]');

			async function* makeTextFileLineIterator(url) {
				const td = new TextDecoder('utf-8');
				const response = await fetch(url);
				const rd = response.body.getReader();
				let {value: chunk, done: readerDone} = await rd.read();
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
							({value: chunk, done: readerDone} = await rd.read());
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

		// Setup recording button handlers
		$$('#recorder-ch0, #recorder-ch1').forEach(checkbox => {
			checkbox.addEventListener('click', function(e) {
				e.preventDefault();
				const channel = parseInt(this.dataset.channel);
				toggleRecording(channel);
			});
		});

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
