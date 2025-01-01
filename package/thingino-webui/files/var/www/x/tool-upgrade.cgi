#!/bin/haserl --upload-limit=102400 --upload-dir=/tmp
<%in _common.cgi %>
<%
page_title="Flash Operations"
tools_action="sysupgrade"
tools_upgrade_option="-p"
upgrade_file_or_url=""

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
<div class="container g-4 mb-4">
  <div class="row">
    <div class="col col-md-6">
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
        <h5>Flash new firmware image</h5>
        <p>Upload a sysupgrade-compatible image here to replace the running firmware.</p>
        <div id="firmware-upload-form">
          <input type="file" class="form-control" id="firmware-image" name="firmware">
          <div class="mt-2">
            <% field_select "tools_upgrade_option" "Upgrade Option" "PartialUpgrade,FullUpgrade,UpgradeBootloader" %>
          </div>
          <button type="button" class="btn btn-primary mt-2" onclick="handleUpgrade()">Flash image</button>
        </div>
      </div>
    </div>

    <div class="col col-md-6">
      <div id="output-wrapper"></div>
    </div>
  </div>
</div>

<script>
async function handleUpgrade(ev) {
    if (ev) ev.preventDefault();

    const fileInput = $('#firmware-image');
    const hasFile = fileInput && fileInput.files && fileInput.files.length > 0;
    const submitButton = document.querySelector('#firmware-upload-form button');
    if (submitButton) submitButton.disabled = true;

    const wr = $('#output-wrapper');
    if (!wr) {
        if (submitButton) submitButton.disabled = false;
        return;
    }

    wr.innerHTML = '';
    let cmd = '/sbin/sysupgrade';

    if (hasFile) {
        const uploadStatus = document.createElement('pre');
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
    } else {
        const option = $('#tools_upgrade_option').value;
        if (option === 'FullUpgrade') cmd += ' -f';
        else if (option === 'PartialUpgrade') cmd += ' -p';
        else if (option === 'UpgradeBootloader') cmd += ' -b';
    }

    const el = document.createElement('pre');
    el.id = "output";
    el.dataset.cmd = cmd;

    const h6 = document.createElement('h6');
    h6.textContent = `# ${cmd}`;

    if (wr) {
        wr.innerHTML = '';
        wr.appendChild(h6);
        wr.appendChild(el);
    } else {
        if (submitButton) submitButton.disabled = false;
        return;
    }

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
            if (submitButton) submitButton.disabled = false;
        }
    }

    let lineCount = 0;
    const maxLines = 40;
    for await (let line of makeTextFileLineIterator('/x/run.cgi?cmd=' + btoa(el.dataset.cmd))) {
        const re1 = /\u001b\[1;(\d+)m/;
        const re2 = /\u001b\[0m/;
        line = line.replace(re1, '<span class="ansi-$1">').replace(re2, '</span>');
        el.innerHTML += line + '\n';
        lineCount++;
        if (lineCount > maxLines) {
            const lines = el.innerHTML.split('\n');
            el.innerHTML = lines.slice(lines.length - maxLines).join('\n');
        }
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