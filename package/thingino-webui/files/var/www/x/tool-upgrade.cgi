#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Sysupgrade Tool"
tools_action="sysupgrade"
tools_upgrade_option="-p" # Default option is partial upgrade
upgrade_file_or_url=""
%>
<%in _header.cgi %>
<div class="row g-4 mb-4">
<div class="col col-md-4">
<form>
<% field_select "tools_upgrade_option" "Upgrade Option" "Full Upgrade, Partial Upgrade, Upgrade Bootloader" %>
<% field_text "upgrade_file_or_url" "File/URL (Optional)" "Local file path or URL" %>
<% button_submit "Run Upgrade" %>
</form>
</div>
<div class="col col-md-8">
<div id="output-wrapper"></div>
</div>
</div>

<script>
$('form').onsubmit = (ev) => {
    const upgradeOption = $('#tools_upgrade_option').value;
    const fileOrUrl = $('#upgrade_file_or_url').value;

    ev.preventDefault();
    $('form input[type=submit]').disabled = true;

    let cmd = `/sbin/sysupgrade ${upgradeOption}`;
    if (fileOrUrl) {
        cmd += ` ${fileOrUrl}`;
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
                    ({ value: chunk, done: readerDone } = await rd.read());
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
            $('form input[type=submit]').disabled = false;
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
    run();
}
</script>
<%in _footer.cgi %>
