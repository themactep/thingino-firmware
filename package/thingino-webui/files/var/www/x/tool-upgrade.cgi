#!/bin/haserl --upload-limit=102400 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="Flash Operations"
tools_action="sysupgrade"
tools_upgrade_option="-p"
ota_upgrade_option="Partial"
tools_upgrade_option="Partial"

if [ "$REQUEST_METHOD" = "POST" ]; then
    if [ -n "$HASERL_firmware_path" ]; then
        mv "$HASERL_firmware_path" /tmp/fw-web.bin
        echo "Content-Type: application/json"
        echo ""
        echo '{"success": true}'
        exit 0
    fi
fi

if [ "$QUERY_STRING" = "action=generate_backup" ]; then
    host=$(hostname)
    current_date=$(date +%Y-%m-%d)
    echo "Content-Type: application/octet-stream"
    echo "Content-Disposition: attachment; filename=backup-${host}-${current_date}.tar.gz"
    echo ""
    tar -cf - /etc | gzip
    exit 0
fi

if [ ! -z "$QUERY_STRING" ]; then
    if echo "$QUERY_STRING" | grep -q "^partition="; then
        partition=$(echo "$QUERY_STRING" | sed -n 's/^partition=//p')
        if [ -n "$partition" ] && [ -e "/dev/$partition" ]; then
            echo "Content-Type: application/octet-stream"
            echo "Content-Disposition: attachment; filename=$partition.bin"
            echo ""
            cat "/dev/$partition"
            exit 0
        else
            echo "Content-Type: text/plain"
            echo ""
            echo "Error: Invalid or missing partition."
            exit 1
        fi
    fi
fi

get_mtd_partitions() {
    awk -F: '/^mtd[0-9]+/ {print $1}' /proc/mtd | tr '
' ',' | sed 's/,$//'
}
%>
<%in _header.cgi %>
<style>
:root {
    /* Basic colors */
    --ansi-70: #5faf00;  /* Green */
    --ansi-66: #5f8787;  /* Cyan-ish */
    --ansi-144: #afaf87; /* Light grey */
}

/* FIXME: Hide hint texts? Ask Paul about this. */
span.hint.text-secondary {
    display: none;
}
</style>
<div class="container g-4 mb-4">
  <div class="row">
    <div class="col-12 col-md-6">
      <div class="mb-4">
        <h5>Backup</h5>
        <p>Click "Generate archive" to download a tar archive of the current configuration files.</p>
        <button class="btn btn-primary" onclick="generateBackup()">Generate archive</button>
      </div>

      <div class="mb-4">
        <h5>Save mtdblock contents</h5>
        <p>Click "Save mtdblock" to download the specified mtdblock file. (NOTE: THIS FEATURE IS FOR PROFESSIONALS!)</p>
        <form>
          <% field_select "mtdblock_partition" "Choose mtdblock" "$(get_mtd_partitions)" %>
          <button type="button" class="btn btn-primary" onclick="saveMtdblock()">Save mtdblock</button>
        </form>
      </div>

      <div class="mb-4">
        <h5>OTA (Over The Air) Update</h5>
        <p>Click to perform an upgrade of the latest firmware version from the Thingino GitHub repository</p>
        <div class="mt-2">
            <% field_select "ota_upgrade_option" "Upgrade Option" "Partial,Full,Bootloader" "Partial" %>
        </div>
        <button type="button" class="btn btn-primary mt-2" onclick="handleOTAUpgrade()">Download & Upgrade</button>
      </div>

      <div class="mb-4">
        <h5>Flash new firmware image</h5>
        <p>Upload a sysupgrade-compatible image here to replace the current firmware</p>
        <div id="firmware-upload-form">
          <input type="file" class="form-control" id="firmware-image" name="firmware" onchange="updateFlashButton()">
          <div class="mt-2">
            <% field_select "tools_upgrade_option" "Upgrade Option" "Partial,Full,Bootloader" "Partial" %>
          </div>
          <button type="button" class="btn btn-primary mt-2" onclick="handleUpgrade()" id="flash-button" disabled>Flash image</button>
        </div>
      </div>
    </div>

    <div class="col-12 col-md-6">
      <div id="output-wrapper" style="display: none; height: 600px; max-height: 600px; overflow-y: auto; padding: 1rem;">
        <pre style="margin: 0; white-space: pre-wrap; word-wrap: break-word;"></pre>
      </div>
    </div>
  </div>
</div>

<script>
function updateFlashButton() {
    const fileInput = document.getElementById('firmware-image');
    const flashButton = document.getElementById('flash-button');
    flashButton.disabled = !(fileInput && fileInput.files && fileInput.files.length > 0);
}

async function handleOTAUpgrade() {
    const wr = document.getElementById('output-wrapper');
    if (!wr) return;

    wr.style.display = 'block';
    wr.innerHTML = '';

    let cmd = '/sbin/sysupgrade -p';  // Default to partial upgrade

    const option = document.getElementById('ota_upgrade_option').value;
    if (option === 'Full') {
        cmd = '/sbin/sysupgrade -f';
    } else if (option === 'Bootloader') {
        cmd = '/sbin/sysupgrade -b';
    }

    const el = document.createElement('pre');
    el.id = "output";
    el.dataset.cmd = cmd;
    el.style.margin = '0';
    el.style.whiteSpace = 'pre-wrap';
    el.style.wordWrap = 'break-word';

    const h6 = document.createElement('h6');
    h6.textContent = `# ${cmd}`;
    h6.style.margin = '0 0 1rem 0';

    wr.appendChild(h6);
    wr.appendChild(el);

    await streamOutput(el, cmd);
}

async function handleUpgrade(ev) {
    if (ev) ev.preventDefault();

    const fileInput = document.getElementById('firmware-image');
    if (!fileInput || !fileInput.files || !fileInput.files.length) {
        return; // Early return if no file selected
    }

    const submitButton = document.querySelector('#firmware-upload-form button');
    if (submitButton) submitButton.disabled = true;

    const wr = document.getElementById('output-wrapper');
    if (!wr) {
        if (submitButton) submitButton.disabled = false;
        return;
    }

    wr.style.display = 'block';
    wr.innerHTML = '';
    let cmd = '/sbin/sysupgrade';

    const uploadStatus = document.createElement('pre');
    uploadStatus.style.margin = '0';
    uploadStatus.style.whiteSpace = 'pre-wrap';
    uploadStatus.style.wordWrap = 'break-word';
    uploadStatus.textContent = 'Uploading firmware file...';
    wr.appendChild(uploadStatus);

    const formData = new FormData();
    formData.append('firmware', fileInput.files[0]);

    try {
        const response = await fetch(window.location.pathname, {
            method: 'POST',
            body: formData
        });

        if (!response.ok) throw new Error(`Upload failed: ${response.statusText}`);
        cmd += ` /tmp/fw-web.bin`;
        wr.innerHTML = '';
    } catch (error) {
        uploadStatus.textContent = 'Upload failed: ' + error.message;
        if (submitButton) submitButton.disabled = false;
        return;
    }

    const option = document.getElementById('tools_upgrade_option').value;
    if (option === 'Full') cmd += ' -f';
    else if (option === 'Partial') cmd += ' -p';
    else if (option === 'Bootloader') cmd += ' -b';

    const el = document.createElement('pre');
    el.id = "output";
    el.dataset.cmd = cmd;
    el.style.margin = '0';
    el.style.whiteSpace = 'pre-wrap';
    el.style.wordWrap = 'break-word';

    const h6 = document.createElement('h6');
    h6.textContent = `# ${cmd}`;
    h6.style.margin = '0 0 1rem 0';

    wr.appendChild(h6);
    wr.appendChild(el);

    await streamOutput(el, cmd);
}

async function streamOutput(el, cmd) {
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
            el.innerHTML += '\n--- sysupgrade exit! ---\n';
            // Only re-enable the flash button if we're in the manual upload flow
            if (cmd.includes('/tmp/fw-web.bin')) {
                const submitButton = document.getElementById('flash-button');
                if (submitButton) submitButton.disabled = false;
            }
        }
    }

    let lastProgressLine = '';
    let lines = [];

    for await (let line of makeTextFileLineIterator('/x/run.cgi?cmd=' + btoa(cmd))) {
        line = line.trimEnd() + '</span>';

        line = line
            .replace(/\[38;5;(\d+)m/g, '</span><span style="color: var(--ansi-$1);">')
            .replace(/\[(\d+)m/g, '</span><span class="ansi-$1">')
            .replace(/\[0m/g, '</span>')
            .replace(/\x1B/g, '')
            .replace(/[\x00-\x1F\x7F-\x9F]/g, '');

        if (line.includes('Writing kb:') ||
            line.includes('Verifying kb:') ||
            line.match(/^[#O-]+\s+\d+\.?\d*%/) ||
            line.match(/^#+\s+\d+\.?\d*%/) ||
            line.match(/^#[#O=\-]+.*/) ||
            line.match(/^Erasing block: \d+\/\d+ \(\d+%\)/)) {
            if (lastProgressLine) {
                lines[lines.length - 1] = line;
            } else {
                lines.push(line);
            }
            lastProgressLine = line;
        } else if (line.trim()) {
            lastProgressLine = '';
            lines.push(line);
        }

        el.innerHTML = lines.join('\n');
        const wr = document.getElementById('output-wrapper');
        if (wr) wr.scrollTop = wr.scrollHeight;
    }
}

function generateBackup() {
    const url = `${window.location.pathname}?action=generate_backup`;
    window.location.href = url;
}

function saveMtdblock() {
    const partition = document.querySelector('#mtdblock_partition').value;
    if (partition) {
        const url = `${window.location.pathname}?partition=${partition}`;
        window.location.href = url;
    } else {
        alert('Please select an mtdblock partition.');
    }
}
</script>
<%in _footer.cgi %>