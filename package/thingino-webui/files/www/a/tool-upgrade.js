(function() {
  const API_URL = '/x/tool-upgrade.cgi';
  const statusEl = $('#statusMessage');
  const refreshBtn = $('#refreshState');
  const backupBtn = $('#backupButton');
  const partitionSelect = $('#partitionSelect');
  const partitionButton = $('#partitionDownload');
  const otaButton = $('#otaRun');
  const firmwareInput = $('#firmwareInput');
  const uploadButton = $('#uploadButton');
  const outputEl = $('#output');
  const copyLog = $('#copyLog');
  const clearLog = $('#clearLog');
  const flashProgressModal = $('#flashProgressModal');
  let flashProgressModalInstance = null;

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
      return;
    }
    list.forEach(part => {
      const option = document.createElement('option');
      option.value = part.download_url || `${API_URL}?partition=${part.id}`;
      option.textContent = part.label || part.id;
      partitionSelect.appendChild(option);
    });
    partitionButton.disabled = false;
  }

  function applyState(data = {}) {
    metadata = data;
    const partitions = getNested(data, ['mtd', 'partitions'], []);
    populatePartitions(Array.isArray(partitions) ? partitions : []);
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
    copyLog.disabled = true;
    showBusy('Running command...');

    // Show the flash progress modal
    if (flashProgressModal) {
      if (!flashProgressModalInstance && window.bootstrap && window.bootstrap.Modal) {
        flashProgressModalInstance = new bootstrap.Modal(flashProgressModal);
      }
      if (flashProgressModalInstance) {
        flashProgressModalInstance.show();
      }
    }
  }

  function handleCommandFinished() {
    hideBusy();
    copyLog.disabled = !(outputEl && outputEl.textContent.trim());
    loadState();

    // Keep modal open so user can see the final output
    // They can close it manually
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
    const selected = document.querySelector('input[name="otaOption"]:checked');
    const selectedLabel = selected ? selected.parentElement.querySelector('label .fw-semibold').textContent : 'update';
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
    copyLog.disabled = true;
  }

  backupBtn.addEventListener('click', handleBackupDownload);
  partitionButton.addEventListener('click', handlePartitionDownload);
  otaButton.addEventListener('click', handleOtaClick);
  uploadButton.addEventListener('click', uploadFirmware);
  if (refreshBtn) refreshBtn.addEventListener('click', loadState);
  if (copyLog) copyLog.addEventListener('click', copyOutput);
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
