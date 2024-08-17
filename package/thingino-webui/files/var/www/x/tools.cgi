#!/usr/bin/haserl
<%in _common.cgi %>
<%
page_title="Monitoring tools"
tools_action="ping"
tools_target="4.2.2.1"
tools_interface="auto"
tools_packet_size="56" # 56-1500 for ping, 38-32768 for trace
tools_duration="5"
%>
<%in _header.cgi %>
<div class="row g-4 mb-4">
<div class="col col-md-4">
<h3>Ping Quality</h3>
<form>
<% field_select "tools_action" "Action" "ping,trace" %>
<% field_text "tools_target" "Target FQDN or IP address" %>
<% field_select "tools_interface" "Network interface" "auto,${interfaces}" %>
<% field_number "tools_packet_size" "Packet size" "56,65535,1" "Bytes" %>
<% field_number "tools_duration" "Number of packets" "1,30,1" %>
<% button_submit "Run" %>
</form>
</div>
<div class="col col-md-8">
<div id="output-wrapper"></div>
</div>
</div>

<script>
$('form').addEventListener('submit', event => {
	event.preventDefault();
	$('form input[type=submit]').disabled = true;

	if ($('#tools_action').value == 'ping') {
		cmd = 'ping -s ' + $('#tools_packet_size').value;
		if ($('#tools_interface').value !== 'auto') cmd =+ ' -I ' + $('#tools_interface').value;
		cmd += ' -c ' + $('#tools_duration').value + ' ' + $('#tools_target').value;
	} else {
		cmd = 'traceroute -q ' + $('#tools_duration').value + ' -w 1';
		if ($('#tools_interface').value !== 'auto') cmd =+ ' -i ' + $('#tools_interface').value;
		cmd += ' ' + $('#tools_target').value + ' ' + $('#tools_packet_size').value;
	}

	el = document.createElement('pre')
	el.id = "output";
	el.dataset['cmd'] = cmd;

	h6 = document.createElement('h6')
	h6.textContent = '# ' + cmd;

	$('#output-wrapper').innerHTML = '';
	$('#output-wrapper').appendChild(h6);
	$('#output-wrapper').appendChild(el);

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
			if ('true' === el.dataset['reboot']) {
				window.location.href = '/x/reboot.cgi'
			} else {
				el.innerHTML += '\n--- finished ---\n';
			}
			$('form input[type=submit]').disabled = false;
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
});
</script>
<%in _footer.cgi %>
