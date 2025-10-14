const ThreadRtsp = 1;
const ThreadVideo = 2;
const ThreadAudio = 4;
const ThreadOSD = 8;

let max = 0;
let HeartBeatInterval = 30 * 1000;

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
	if (el.type === "checkbox") {
		el.checked = value;
	} else {
		el.value = value;
		if (el.type === "range") {
			$(`${id}-show`).textContent = value;
		}
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

function heartbeat() {
	fetch('/x/json-heartbeat.cgi')
		.then((response) => response.json())
		.then((json) => {
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

			if (json.daynight_value !== '-1')
				$$('.gain').forEach(el => el.textContent = '☀️ ' + json.daynight_value);

			if (typeof (json.uptime) !== 'undefined' && json.uptime !== '')
				$('#uptime').textContent = 'Uptime:️ ' + json.uptime;
		})
		.then(setTimeout(heartbeat, HeartBeatInterval));
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
	}

	window.addEventListener('load', initAll)
})();
