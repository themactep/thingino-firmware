(function() {
  const API_URL = '/x/tool-upgrade.cgi';
  const statusEl = $('#statusMessage');  const refreshBtn = $('#refreshState');
  const backupBtn = $('#backupButton');
  const backupFilename = $('#backupFilename');
  const backupWarning = $('#backupWarning');
  const partitionSelect = $('#partitionSelect');
  const partitionButton = $('#partitionDownload');
  const partitionWarning = $('#partitionWarning');
  const otaOptions = $('#otaOptions');
  const otaButton = $('#otaRun');
  const otaNotes = $('#otaNotes');
  const firmwareInput = $('#firmwareInput');
  const uploadButton = $('#uploadButton');
  const uploadWarning = $('#uploadWarning');
  const uploadDetails = $('#uploadDetails');
  const outputEl = $('#output');
  const copyLog = $('#copyLog');
  const clearLog = $('#clearLog');
  const commandHeading = $('#commandHeading');
  const debugProcMtd = $('#debugProcMtd');
  const debugDf = $('#debugDf');
  const debugUpload = $('#debugUpload');

  let metadata = null;
  const buttonLabels = new Map();
  buttonLabels.set(otaButton, otaButton.innerHTML);
  buttonLabels.set(uploadButton, uploadButton.innerHTML);

  function getNested(source, keys, fallback) {
    let current = source;
    for (let i = 0; i < keys.length; i += 1) {
      if (!current || typeof current !== 'object' || !(keys[i] in current)) {
        return fallback;
      }
      current = current[keys[i]];
    }
    return typeof current === 'undefined' ? fallback : current;
  }

  function setStatus(text, tone = 'info') {
    if (!statusEl) return;
    statusEl.className = `alert alert-${tone} flex-grow-1 mb-0 status-overlay`;
    statusEl.textContent = text;
  }

  function formatBytes(bytes) {
    const value = Number(bytes);
    if (!Number.isFinite(value) || value <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB'];
    let size = value;
    let unit = 0;
    while (size >= 1024 && unit < units.length - 1) {
      size /= 1024;
      unit += 1;
    }
    const precision = size >= 10 || unit === 0 ? 0 : 1;
    return `${size.toFixed(precision)} ${units[unit]}`;
  }

  function setButtonBusy(button, busy) {
    if (!button) return;
    button.disabled = !!busy;
    if (busy) {
      button.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Please wait...';
    } else {
      button.innerHTML = buttonLabels.get(button) || button.innerHTML;
    }
  }

  function populatePartitions(list = []) {
    partitionSelect.innerHTML = '';
    if (!list.length) {
      const opt = document.createElement('option');
      opt.textContent = 'No mtd partitions detected';
      opt.disabled = true;
      opt.selected = true;
      partitionSelect.appendChild(opt);
      partitionButton.disabled = true;
      partitionWarning.textContent = 'Is this model using raw NAND?';
      return;
    }
    list.forEach(part => {
      const option = document.createElement('option');
      option.value = part.download_url || `${API_URL}?partition=${part.id}`;
      option.textContent = part.label || part.id;
      partitionSelect.appendChild(option);
    });
    partitionButton.disabled = false;
    partitionWarning.textContent = getNested(metadata, ['mtd', 'warning'], '');
  }

  function createOtaOption(option, index) {
    const id = `ota-${option.id || index}`;
    const wrapper = document.createElement('div');
    wrapper.className = 'form-check border rounded-3 px-3 py-2 position-relative';
    const input = document.createElement('input');
    input.type = 'radio';
    input.name = 'otaOption';
    input.value = option.id || option.flag || 'partial';
    input.id = id;
    input.className = 'form-check-input position-absolute top-50 translate-middle-y';
    input.style.left = '0.85rem';
    if (index === 0) input.checked = true;
    const label = document.createElement('label');
    label.className = 'form-check-label d-block ms-4';
    label.setAttribute('for', id);
    label.innerHTML = `<span class="fw-semibold">${option.label || 'Update'}</span><br><span class="text-secondary small">${option.description || ''}</span>`;
    wrapper.appendChild(input);
    wrapper.appendChild(label);
    otaOptions.appendChild(wrapper);
  }

  function populateOtaOptions(options = []) {
    otaOptions.innerHTML = '';
    options.forEach((opt, index) => {
      createOtaOption(opt, index);
    });
    if (!options.length) {
      const alert = document.createElement('div');
      alert.className = 'alert alert-secondary mb-0';
      alert.textContent = 'OTA metadata unavailable on this model.';
      otaOptions.appendChild(alert);
      otaButton.disabled = true;
    } else {
      otaButton.disabled = false;
    }
  }

  function updateDebug(debug = {}) {
    debugProcMtd.textContent = debug.proc_mtd_base64 ? atob(debug.proc_mtd_base64) : 'No /proc/mtd output available.';
    debugDf.textContent = debug.df_base64 ? atob(debug.df_base64) : 'No df output available.';
    debugUpload.textContent = debug.upload_base64 ? atob(debug.upload_base64) : 'No upload log available.';
  }

  function applyState(data = {}) {
    metadata = data;
    backupFilename.textContent = getNested(data, ['backup', 'filename'], '—');
    backupWarning.textContent = getNested(data, ['messages', 'backup_warning'], '');
    const partitions = getNested(data, ['mtd', 'partitions'], []);
    populatePartitions(Array.isArray(partitions) ? partitions : []);
    const otaList = getNested(data, ['ota', 'options'], []);
    populateOtaOptions(Array.isArray(otaList) ? otaList : []);
    const otaWarning = getNested(data, ['messages', 'ota_warning'], '');
    const otaNote = otaWarning || getNested(data, ['ota', 'notes'], '');
    otaNotes.textContent = otaNote;
    const size = getNested(data, ['upload', 'size_bytes'], 0);
    const hasImage = !!getNested(data, ['upload', 'has_image'], false);
    const targetPath = getNested(data, ['upload', 'target'], '/tmp/fw-web.bin');
    uploadDetails.textContent = hasImage
      ? `Staged at ${targetPath} (${formatBytes(size)})`
      : `Staged at ${targetPath}`;
    uploadWarning.textContent = getNested(data, ['messages', 'flash_warning'], uploadWarning.textContent);
    updateDebug(data.debug || {});
  }

  async function loadState() {
    showBusy('Loading flash metadata...');
    if (refreshBtn) refreshBtn.disabled = true;
    try {
      const response = await fetch(API_URL, { cache: 'no-store' });
      const payload = await response.json();
      if (!response.ok || payload.error) {
        const message = getNested(payload, ['error', 'message'], 'Unable to load flash metadata.');
        throw new Error(message);
      }
      applyState(payload.data || {});
      setStatus('Flash metadata loaded.', 'success');
    } catch (err) {
      showAlert('danger', err.message || 'Failed to load flash metadata.');
      setStatus('Flash metadata unavailable.', 'danger');
    } finally {
      hideBusy();
      if (refreshBtn) refreshBtn.disabled = false;
    }
  }

  function startCommand(command, { reboot = true } = {}) {
    if (!command) {
      showAlert('warning', 'No command returned by the firmware.');
      return;
    }
    if (outputEl) {
      outputEl.dataset.reboot = reboot ? 'true' : 'false';
      outputEl.dispatchEvent(new CustomEvent('thingino:start-command', { detail: { cmd: command, reboot } }));
    }
  }

  function handleCommandStart(ev) {
    const detail = ev.detail || {};
    commandHeading.textContent = detail.cmd ? `# ${detail.cmd}` : 'Command console';
    copyLog.disabled = true;
    showBusy('Running command...');
  }

  function handleCommandFinished() {
    hideBusy();
    copyLog.disabled = !(outputEl && outputEl.textContent.trim());
    setStatus('Command finished.', 'success');
    loadState();
  }

  async function requestOtaCommand(option) {
    setButtonBusy(otaButton, true);
    try {
      const body = new URLSearchParams({ action: 'ota', option });
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      });
      const payload = await response.json();
      if (!response.ok || payload.error) {
        const message = getNested(payload, ['error', 'message'], 'OTA request failed.');
        throw new Error(message);
      }
      if (payload.message) showAlert('success', payload.message);
      startCommand(payload.command || '', { reboot: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to start OTA upgrade.');
      setStatus('OTA request failed.', 'danger');
    } finally {
      setButtonBusy(otaButton, false);
    }
  }

  async function uploadFirmware() {
    if (!firmwareInput.files || !firmwareInput.files.length) {
      showAlert('warning', 'Select a firmware image first.');
      return;
    }
    setButtonBusy(uploadButton, true);
    clearAlerts();
    showBusy('Uploading firmware...');
    const formData = new FormData();
    formData.append('firmware', firmwareInput.files[0]);
    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        body: formData
      });
      const payload = await response.json();
      if (!response.ok || payload.error) {
        const message = getNested(payload, ['error', 'message'], 'Firmware upload failed.');
        throw new Error(message);
      }
      showAlert('success', payload.message || 'Firmware uploaded. Ready to flash.');
      startCommand(payload.command || getNested(metadata, ['upload', 'command'], ''), { reboot: true });
      firmwareInput.value = '';
      uploadButton.disabled = true;
    } catch (err) {
      showAlert('danger', err.message || 'Firmware upload failed.');
      setStatus('Upload failed.', 'danger');
    } finally {
      hideBusy();
      setButtonBusy(uploadButton, false);
    }
  }

  function handleBackupDownload() {
    const downloadUrl = getNested(metadata, ['backup', 'download_url'], '');
    if (!downloadUrl) {
      showAlert('warning', 'Backup endpoint unavailable.');
      return;
    }
    window.location.href = downloadUrl;
  }

  function handlePartitionDownload() {
    const option = partitionSelect.value;
    if (!option) {
      showAlert('warning', 'Select a partition first.');
      return;
    }
    window.location.href = option;
  }

  async function handleOtaClick() {
    const selected = otaOptions.querySelector('input[name="otaOption"]:checked');
    const selectedLabel = selected ? selected.parentElement.querySelector('label').textContent : 'update';
    const value = selected ? selected.value : 'partial';

    const confirmed = await confirm(`Are you sure you want to download and apply ${selectedLabel}?\n\nThis will reboot the camera when finished.`);
    if (!confirmed) {
      return;
    }

    requestOtaCommand(value);
  }

  function copyOutput() {
    const clipboard = window.thinginoClipboard;
    if (!clipboard || typeof clipboard.copy !== 'function' || !outputEl.textContent.trim()) return;
    clipboard.copy(outputEl.textContent)
      .then(() => {
        copyLog.classList.replace('btn-outline-secondary', 'btn-success');
        copyLog.innerHTML = '<i class="bi bi-clipboard-check me-1"></i>Copied';
        setTimeout(() => {
          copyLog.classList.replace('btn-success', 'btn-outline-secondary');
          copyLog.innerHTML = '<i class="bi bi-clipboard me-1"></i>Copy';
        }, 1500);
      })
      .catch(() => {
        showAlert('warning', 'Clipboard copy failed on this browser.');
      });
  }

  function clearOutput() {
    if (!outputEl) return;
    outputEl.textContent = '';
    commandHeading.textContent = 'Command console';
    copyLog.disabled = true;
  }

  backupBtn.addEventListener('click', handleBackupDownload);
  partitionButton.addEventListener('click', handlePartitionDownload);
  otaButton.addEventListener('click', handleOtaClick);
  uploadButton.addEventListener('click', uploadFirmware);
  if (refreshBtn) refreshBtn.addEventListener('click', loadState);
  if (copyLog) copyLog.addEventListener('click', copyOutput);
  if (clearLog) clearLog.addEventListener('click', () => {
    clearOutput();
    setStatus('Console cleared.', 'secondary');
  });
  if (firmwareInput) {
    firmwareInput.addEventListener('change', () => {
      uploadButton.disabled = !firmwareInput.files || !firmwareInput.files.length;
    });
  }
  if (outputEl) {
    outputEl.addEventListener('thingino:command-start', handleCommandStart);
    outputEl.addEventListener('thingino:command-finished', handleCommandFinished);
  }

  loadState();
})();
