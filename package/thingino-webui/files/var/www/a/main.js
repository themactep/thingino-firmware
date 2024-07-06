let max = 0;

function $(n) {
	return document.querySelector(n)
}

function $$(n) {
	return document.querySelectorAll(n)
}

function refresh() {
	window.location.reload()
}

function sleep(ms) {
	return new Promise(resolve => setTimeout(resolve, ms))
}

function setProgressBar(id, value, maxvalue) {
	let value_percent = Math.ceil(value / (maxvalue / 100));
	const el = $(id);
	el.setAttribute('aria-valuemin', 0);
	el.setAttribute('aria-valuemax', maxvalue);
	el.setAttribute('aria-valuenow', value);
	el.style.width = value_percent + '%';
}

function sendToApi(endpoint) {
	const xhr = new XMLHttpRequest();
	xhr.addEventListener("load", reqListener);
	xhr.open("GET", 'http://' + network_address + endpoint);
	xhr.setRequestHeader("Authorization", "Basic " + btoa("admin:"));
	xhr.send();
}

function reqListener(data) {
	console.log(data.responseText);
}

function xhrGet(url) {
	const xhr = new XMLHttpRequest();
	xhr.open('GET', url);
	xhr.send();
}

function heartbeat() {
	fetch('/cgi-bin/j/heartbeat.cgi')
		.then((response) => response.json())
		.then((json) => {
			if (json.time_now !== '') {
				let options = {timeZone: json.timezone.replaceAll(' ', '_')};
				const d = new Date(json.time_now * 1000);
				$('#time-now').textContent = d.toLocaleString(navigator.language, options) + ' ' + json.timezone;
			}

			$('.progress-stacked.memory').title = "Free memory: " + json.mem_free + "KiB"
			setProgressBar('#pb-memory-active', json.mem_active, json.mem_total);
			setProgressBar('#pb-memory-buffers', json.mem_buffers, json.mem_total);
			setProgressBar('#pb-memory-cached', json.mem_cached, json.mem_total);

			$('.progress-stacked.overlay').title = "Free overlay: " + json.overlay_free + "KiB"
			setProgressBar('#pb-overlay-used', json.overlay_used, json.overlay_total);

			if (json.daynight_value !== '-1') {
				$('#daynight_value').textContent = '☀️ ' + json.daynight_value;
			}
			if (typeof (json.uptime) !== 'undefined' && json.uptime !== '') {
				$('#uptime').textContent = 'Uptime:️ ' + json.uptime;
			}
		})
		.then(setTimeout(heartbeat, 10000));
}

(() => {
	function initAll() {
		function toggleAuto(el) {
			const id = el.dataset.for;
			const p = $('#' + id);
			const r = $('#' + id + '-range');
			const s = $('#' + id + '-show');
			if (el.checked) {
				el.dataset.value = r.value;
				p.value = 'auto';
				r.disabled = true;
				s.textContent = '--';
			} else {
				p.value = el.dataset.value;
				r.value = p.value;
				r.disabled = false;
				s.textContent = p.value;
			}
		}

		$$('form').forEach(el => el.autocomplete = 'off');

		// For .warning and .danger buttons, ask confirmation on action.
		$$('.btn-danger, .btn-warning, .confirm').forEach(el => {
			// for input, find its parent form and attach listener to it submit event
			if (el.nodeName === "INPUT") {
				while (el.nodeName !== "FORM") el = el.parentNode
				el.addEventListener('submit', ev => (!confirm("Are you sure?")) ? ev.preventDefault() : null)
			} else {
				el.addEventListener('click', ev => (!confirm("Are you sure?")) ? ev.preventDefault() : null)
			}
		});

		$$('.refresh').forEach(el => el.addEventListener('click', refresh));

		// open links to external resources in a new window.
		$$('a[href^=http]').forEach(el => el.target = '_blank');

		// add auto toggle button and value display for range elements.
		$$('input[type=range]').forEach(el => {
			el.addEventListener('input', ev => {
				const id = ev.target.id.replace(/-range/, '');
				`1`
				$('#' + id + '-show').textContent = ev.target.value;
				$('#' + id).value = ev.target.value;
			})
		});

		$$('input.auto-value').forEach(el => {
			el.addEventListener('click', ev => toggleAuto(ev.target));
			toggleAuto(el);
		});

		// show password when "show" checkbox is checked
		$$(".password input[type=checkbox]").forEach(el => {
			el.addEventListener('change', ev => {
				const pw = $('#' + ev.target.dataset['for']);
				pw.type = (el.checked) ? 'text' : 'password';
				pw.focus();
			});
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
					if ("true" === el.dataset["reboot"]) {
						window.location.href = '/cgi-bin/reboot.cgi'
					} else {
						el.innerHTML += '\n--- finished ---\n';
					}
				}
			}

			async function run() {
				for await (let line of makeTextFileLineIterator('/cgi-bin/j/run.cgi?cmd=' + btoa(el.dataset["cmd"]))) {
					const re1 = /\u001b\[1;(\d+)m/;
					const re2 = /\u001b\[0m/;
					line = line.replace(re1, '<span class="ansi-$1">').replace(re2, '</span>')
					el.innerHTML += line + '\n';
				}
			}

			run()
		}

		heartbeat();
	}

	window.addEventListener('load', initAll);
})();
