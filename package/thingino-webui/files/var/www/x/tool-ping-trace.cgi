#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Network Test"
tools_action="ping"
tools_target=""
tools_interface="auto"
tools_packet_size="56" # 56-1500 for ping, 38-32768 for trace
tools_duration="5"
%>
<%in _header.cgi %>
<div class="row g-1">
<div class="col"><% field_select "tools_action" "Action" "ping,trace" %></div>
<div class="col"><% field_text "tools_target" "Target" "FQDN or IP address" %></div>
</div>
<div class="row g-1">
<div class="col"><% field_select "tools_interface" "Interface" "auto,${interfaces}" %></div>
<div class="col"><% field_number "tools_packet_size" "Packet size" "56,65535,1" "Bytes" %></div>
<div class="col"><% field_number "tools_duration" "# of packets" "1,30,1" %></div>
</div>
<button type="button" class="btn btn-primary mb-4" id="run">Run test</button>
<div id="output-wrapper"></div>

<script>
$('#run').addEventListener('click', ev => {
	const tgt = $('#tools_target').value;
	const pkgsize = $('#tools_packet_size').value;
	const iface = $('#tools_interface').value;
	const duration = $('#tools_duration').value;

	ev.preventDefault();
	ev.target.disabled = true;

	if ($('#tools_action').value == 'ping') {
		cmd = `ping -s ${pkgsize}`;
		if (iface !== 'auto') cmd += ` -I ${iface}`;
		cmd += ` -c ${duration} ${tgt}`;
	} else {
		cmd = `traceroute -q ${duration} -w 1`;
		if (iface !== 'auto') cmd += ` -i ${iface}`;
		cmd += ` ${tgt} ${pkgsize}`;
	}

	const el = document.createElement('pre');
	el.id = "output";
	el.dataset.cmd = cmd;

	const h6 = document.createElement('h6');
	h6.textContent = `# ${cmd}`;

	const wr = $('#output-wrapper');
	wr.innerHTML = '';
	wr.appendChild(h6);
	wr.appendChild(el);

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
			for (;;) {
				result = re.exec(chunk);
				if (!result) {
					if (readerDone) break;
					let remainder = chunk.substr(startIndex);
					({value: chunk, done: readerDone} = await rd.read());
					chunk = remainder + (chunk ? td.decode(chunk) : '');
					startIndex = re.lastIndex = 0;
					continue;
				}
				yield chunk.substring(startIndex, result.index);
				startIndex = re.lastIndex;
			}
			if (startIndex < chunk.length) yield chunk.substr(startIndex);
		} finally {
			if ('true' === el.dataset.reboot) {
				window.location.href = '/x/reboot.cgi';
			} else {
				el.innerHTML += '\n--- finished ---\n';
			}
			ev.target.disabled = false
		}
	}
	async function run() {
		for await (let line of makeTextFileLineIterator('/x/run.cgi?cmd=' + btoa(el.dataset.cmd))) {
			const re1 = /\u001b\[1;(\d+)m/;
			const re2 = /\u001b\[0m/;
			line = line.replace(re1, '<span class="ansi-$1">').replace(re2, '</span>');
			el.innerHTML += line + '\n';
		}
	}

	run()
})
</script>
<%in _footer.cgi %>
