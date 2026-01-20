(function() {
  const API_URL = '/x/tool-sdcard.cgi';
  const statusEl = $('#statusMessage');
  const refreshBtn = $('#refreshState');
  const noCardPanel = $('#noCardPanel');
  const cardContent = $('#cardContent');
  const deviceSummary = $('#deviceSummary');
  const partitionOutput = $('#partitionOutput');
  const mountOutput = $('#mountOutput');
  const formatForm = $('#formatForm');
  const formatOptions = $('#formatOptions');
  const formatSubmit = $('#formatSubmit');
  const formatDisabledNote = $('#formatDisabledNote');
  const formatLogWrap = $('#formatLogWrap');
  const formatLog = $('#formatLog');
  const copyFormatLog = $('#copyFormatLog');
  const formatConfirmModalEl = $('#formatConfirmModal');
  const formatConfirmFilesystem = $('#formatConfirmFilesystem');
  const formatConfirmBtn = $('#formatConfirmBtn');
  const formatConfirmCancelBtn = $('#formatConfirmCancel');
  let formatConfirmModalInstance = null;
  let pendingFilesystem = 'exfat';

  const buttonDefault = formatSubmit.innerHTML;
  let lastState = null;
  const textDecoder = window.TextDecoder ? new TextDecoder() : null;
  const ANSI_SEQUENCE = /\u001b\[([0-9;]*)m/g;
  const ANSI_CLASS_MAP = {
    66: 'ansi-fg-66',
    70: 'ansi-fg-70',
    142: 'ansi-fg-142',
    144: 'ansi-fg-144',
    240: 'ansi-fg-240'
  };

  function escapeHtml(text) {
    if (!text) return '';
    return text
      .replace(/&/g, '&amp;')
      .replace(/</g, '&lt;')
      .replace(/>/g, '&gt;')
      .replace(/"/g, '&quot;')
      .replace(/'/g, '&#39;');
  }

  function stripAnsi(text) {
    if (!text) return '';
    return text.replace(/\u001b\[[0-9;]*m/g, '');
  }

  function ansiToHtml(text) {
    if (!text) return '';
    ANSI_SEQUENCE.lastIndex = 0;
    let result = '';
    let lastIndex = 0;
    let activeClass = '';
    let spanOpen = false;
    const state = { colorClass: '', bold: false };

    function buildClassName() {
      const classes = ['ansi-fragment'];
      if (state.bold) classes.push('ansi-bold');
      if (state.colorClass) classes.push(state.colorClass);
      return classes.join(' ');
    }

    function ensureSpan() {
      const nextClass = buildClassName();
      if (spanOpen && nextClass === activeClass) {
        return;
      }
      if (spanOpen) {
        result += '</span>';
      }
      result += `<span class="${nextClass}">`;
      activeClass = nextClass;
      spanOpen = true;
    }

    let match;
    while ((match = ANSI_SEQUENCE.exec(text)) !== null) {
      const chunk = text.slice(lastIndex, match.index);
      if (chunk) {
        ensureSpan();
        result += escapeHtml(chunk);
      }
      const codes = match[1] ? match[1].split(';').map(code => Number(code || 0)) : [0];
      for (let i = 0; i < codes.length; i += 1) {
        const code = codes[i];
        if (Number.isNaN(code)) continue;
        if (code === 0) {
          state.colorClass = '';
          state.bold = false;
          ensureSpan();
          continue;
        }
        if (code === 1) {
          state.bold = true;
          ensureSpan();
          continue;
        }
        if (code === 22) {
          state.bold = false;
          ensureSpan();
          continue;
        }
        if (code === 39) {
          state.colorClass = '';
          ensureSpan();
          continue;
        }
        if (code === 38 && codes[i + 1] === 5 && typeof codes[i + 2] !== 'undefined') {
          const mapped = ANSI_CLASS_MAP[codes[i + 2]] || '';
          state.colorClass = mapped;
          ensureSpan();
          i += 2;
          continue;
        }
      }
      lastIndex = ANSI_SEQUENCE.lastIndex;
    }
    if (lastIndex < text.length) {
      ensureSpan();
      result += escapeHtml(text.slice(lastIndex));
    }
    if (spanOpen) result += '</span>';
    return result;
  }

  function readTextField(source, key) {
    if (!source || !key) return '';
    const b64Key = `${key}_b64`;
    if (source[b64Key]) {
      const decoded = decodeBase64String(source[b64Key]);
      if (decoded) return decoded;
    }
    return source[key] || '';
  }

  function setStatus(text, tone = 'info') {
    if (!statusEl) return;
    statusEl.className = `alert alert-${tone} flex-grow-1 mb-0 status-overlay`;
    statusEl.textContent = text;
  }

  function showFormatConfirmModal(fs) {
    const targetFs = (fs || 'exfat').toLowerCase();
    pendingFilesystem = targetFs;
    if (formatConfirmFilesystem) {
      formatConfirmFilesystem.textContent = targetFs.toUpperCase();
    }
    if (!formatConfirmModalEl) {
      executeFormat(pendingFilesystem);
      return;
    }
    if (formatConfirmBtn) {
      formatConfirmBtn.disabled = false;
    }
    if (window.bootstrap && window.bootstrap.Modal) {
      formatConfirmModalInstance = window.bootstrap.Modal.getOrCreateInstance(formatConfirmModalEl);
      formatConfirmModalInstance.show();
    } else {
      formatConfirmModalEl.classList.add('show');
      formatConfirmModalEl.style.display = 'block';
      formatConfirmModalEl.removeAttribute('aria-hidden');
      formatConfirmModalEl.setAttribute('aria-modal', 'true');
    }
  }

  function hideFormatConfirmModal() {
    if (!formatConfirmModalEl) return;
    if (formatConfirmModalInstance && window.bootstrap && window.bootstrap.Modal) {
      formatConfirmModalInstance.hide();
    } else {
      formatConfirmModalEl.classList.remove('show');
      formatConfirmModalEl.style.display = 'none';
      formatConfirmModalEl.setAttribute('aria-hidden', 'true');
      formatConfirmModalEl.removeAttribute('aria-modal');
    }
  }

  function dispatchAlert(type, message) {
    if (typeof window.showAlert === 'function') {
      window.showAlert(type, message);
    } else if (message) {
      console[type === 'danger' ? 'error' : 'log'](message);
    }
  }

  async function executeFormat(filesystem) {
    const fs = (filesystem || 'exfat').toLowerCase();
    setFormBusy(true);
    showBusy('Formatting SD card. Please wait...');
    const body = new URLSearchParams({ action: 'format', fstype: fs });
    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: body.toString()
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error && payload.error.message ? payload.error.message : 'Unable to format the SD card.';
        throw new Error(message);
      }
      const message = payload.message || 'SD card formatted successfully.';
      dispatchAlert('success', message);
      setStatus(message, 'success');
      applyState(payload.data || {});
    } catch (err) {
      dispatchAlert('danger', err.message || 'Formatting failed.');
      setStatus('Formatting failed.', 'danger');
    } finally {
      hideBusy();
      setFormBusy(false);
    }
  }

  function formatBytes(value) {
    const bytes = Number(value);
    if (!Number.isFinite(bytes) || bytes <= 0) return '—';
    const units = ['B', 'KB', 'MB', 'GB', 'TB', 'PB'];
    let size = bytes;
    let unitIndex = 0;
    while (size >= 1024 && unitIndex < units.length - 1) {
      size /= 1024;
      unitIndex += 1;
    }
    const precision = size >= 10 || unitIndex === 0 ? 0 : 1;
    return `${size.toFixed(precision)} ${units[unitIndex]}`;
  }

  function renderDeviceSummary(device = {}) {
    if (!deviceSummary) return;
    deviceSummary.innerHTML = '';

    // Extract mountpoint from mounts data
    let mountpoint = '—';
    if (lastState && lastState.reports) {
      const mountsText = readTextField(lastState.reports, 'mounts');
      if (mountsText) {
        const mountLines = mountsText.split('\n');
        const firstMount = mountLines.find(line => line.trim() && line.includes('/dev/mmc'));
        if (firstMount) {
          const parts = firstMount.trim().split(/\s+/);
          if (parts.length >= 2) {
            mountpoint = parts[1]; // Second column is the mountpoint
          }
        }
      }
    }

    const entries = [
      ['Device node', device.node || '—'],
      ['Capacity', formatBytes(device.size_bytes), false, true], // Fourth element indicates modal trigger
      ['Mountpoint', mountpoint, mountpoint !== '—'], // Third element indicates if it should be a link
      ['Vendor', device.vendor || '—'],
      ['Model', device.model || '—'],
      ['Serial', device.serial || '—']
    ];
    entries.forEach(([label, value, isLink, isModalTrigger]) => {
      const dt = document.createElement('dt');
      dt.className = 'col text-secondary';
      dt.textContent = label;
      const dd = document.createElement('dd');
      dd.className = 'col';

      if (isLink && value !== '—') {
        // Create a link to file manager with the mountpoint path
        const link = document.createElement('a');
        link.href = `/tool-file-manager.html?cd=${encodeURIComponent(value)}`;
        link.className = 'text-decoration-none';
        link.innerHTML = `<i class="bi bi-folder2-open me-1"></i>${value}`;
        dd.appendChild(link);
      } else if (isModalTrigger && value !== '—') {
        // Create clickable link that opens filesystem details modal
        const modalLink = document.createElement('a');
        modalLink.href = '#';
        modalLink.className = 'text-decoration-none';
        modalLink.setAttribute('data-bs-toggle', 'modal');
        modalLink.setAttribute('data-bs-target', '#sdDetailsModal');
        modalLink.textContent = value;
        modalLink.addEventListener('click', (e) => e.preventDefault());
        dd.appendChild(modalLink);
      } else {
        dd.textContent = value || '—';
      }

      deviceSummary.appendChild(dt);
      deviceSummary.appendChild(dd);
    });
  }

  function getSelectedFs() {
    if (!formatOptions) return '';
    const selected = formatOptions.querySelector('input[name="fstype"]:checked');
    return selected ? selected.value : '';
  }

  function setFormBusy(busy) {
    if (!formatOptions || !formatSubmit) return;
    const radios = formatOptions.querySelectorAll('input[name="fstype"]');
    radios.forEach(input => {
      input.disabled = busy || !(lastState && lastState.has_sdcard);
    });
    formatSubmit.disabled = busy || !(lastState && lastState.has_sdcard);
    formatSubmit.innerHTML = busy
      ? '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Formatting...'
      : buttonDefault;
  }

  function setCardEnabled(enabled) {
    if (!formatForm) return;
    if (formatDisabledNote) {
      formatDisabledNote.classList.toggle('d-none', enabled);
    }
    const controls = formatForm.querySelectorAll('input, button');
    controls.forEach(ctrl => {
      if (ctrl === copyFormatLog) return;
      ctrl.disabled = !enabled && ctrl !== refreshBtn;
    });
    setFormBusy(false);
  }

  function populateFilesystems(filesystems = []) {
    if (!formatOptions) {
      console.warn('populateFilesystems: formatOptions container missing');
      return;
    }
    const previous = getSelectedFs();
    let applied = false;
    formatOptions.innerHTML = '';
    filesystems.forEach((fs, index) => {
      const optId = `fstype-${fs.id || index}`;
      const wrapper = document.createElement('div');
      wrapper.className = 'form-check border rounded-3 px-3 py-2 position-relative';
      const input = document.createElement('input');
      input.type = 'radio';
      input.className = 'form-check-input position-absolute top-50 translate-middle-y';
      input.style.left = '0.85rem';
      input.name = 'fstype';
      input.id = optId;
      input.value = fs.id || '';
      const label = document.createElement('label');
      label.className = 'form-check-label d-block ms-4';
      label.setAttribute('for', optId);
      label.innerHTML = `<span class="fw-semibold">${fs.label || fs.id || 'Filesystem'}</span><br><span class="text-secondary small">${fs.description || ''}</span>`;
      if (!applied && previous && previous === input.value) {
        input.checked = true;
        applied = true;
      } else if (!applied && (fs.recommended || index === 0)) {
        input.checked = true;
        applied = true;
      }
      if (fs.recommended) {
        const badge = document.createElement('span');
        badge.className = 'badge text-bg-success position-absolute top-0 end-0 mt-2 me-2';
        badge.textContent = 'Recommended';
        wrapper.appendChild(badge);
      }
      wrapper.appendChild(input);
      wrapper.appendChild(label);
      formatOptions.appendChild(wrapper);
    });
    if (!formatOptions.querySelector('input[name="fstype"]')) {
      const fallback = document.createElement('div');
      fallback.className = 'alert alert-secondary mb-0';
      fallback.textContent = 'No filesystem options available.';
      formatOptions.appendChild(fallback);
    } else if (!formatOptions.querySelector('input[name="fstype"]:checked')) {
      const first = formatOptions.querySelector('input[name="fstype"]');
      if (first) first.checked = true;
    }
  }

  function applyState(data = {}) {
    lastState = data;
    // Hide the initial status message now that we have resolved the SD card state
    if (statusEl) {
      statusEl.classList.add('d-none');
    }
    const present = !!data.has_sdcard;
    noCardPanel.classList.toggle('d-none', present);
    cardContent.classList.toggle('d-none', !present);
    populateFilesystems(data.filesystems || []);
    if (!present) {
      partitionOutput.textContent = 'Insert an SD card to inspect df output.';
      mountOutput.textContent = 'Insert an SD card to inspect mounts.';
      formatLogWrap.classList.add('d-none');
      copyFormatLog.disabled = true;
      setCardEnabled(false);
      return;
    }

    setCardEnabled(true);
    dispatchAlert('success', 'SD card detected and ready.');
    renderDeviceSummary(data.device || {});
    const partitionsText = readTextField(data.reports, 'partitions');
    const mountsText = readTextField(data.reports, 'mounts');
    partitionOutput.textContent = partitionsText || 'No df entries found for /dev/mmc.';
    mountOutput.textContent = mountsText || 'No active mounts for /dev/mmc.';
    const lastOutput = readTextField(data.format, 'last_output');
    const logHtml = ansiToHtml(lastOutput);
    const plainLog = stripAnsi(lastOutput);
    formatLogWrap.classList.toggle('d-none', !lastOutput);
    formatLog.innerHTML = logHtml || 'Formatter output will appear here.';
    formatLog.dataset.rawLog = plainLog || lastOutput || '';
    copyFormatLog.disabled = !lastOutput;
  }

  async function loadState() {
    // Show status message and hide content while loading
    if (statusEl) {
      statusEl.textContent = 'Waiting for SD card status...';
      statusEl.className = 'alert alert-info flex-grow-1 mb-0 status-overlay';
      statusEl.classList.remove('d-none');
    }
    cardContent.classList.add('d-none');
    noCardPanel.classList.add('d-none');

    showBusy('Checking SD card...');
    if (refreshBtn) refreshBtn.disabled = true;
    try {
      const response = await fetch(API_URL, { cache: 'no-store' });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error && payload.error.message ? payload.error.message : 'Unable to load SD card state.';
        throw new Error(message);
      }
      applyState(payload.data || {});
    } catch (err) {
      console.error('Failed to refresh SD card state', err);
      dispatchAlert('danger', err && err.message ? err.message : 'Failed to query SD card state.');
      const statusMessage = err && err.message ? `Unable to load SD card information: ${err.message}` : 'Unable to load SD card information.';
      setStatus(statusMessage, 'danger');
    } finally {
      hideBusy();
      if (refreshBtn) refreshBtn.disabled = false;
      setFormBusy(false);
    }
  }

  formatForm.addEventListener('submit', ev => {
    ev.preventDefault();
    if (!lastState || !lastState.has_sdcard) {
      dispatchAlert('warning', 'Insert an SD card before attempting to format.');
      return;
    }
    const filesystem = getSelectedFs() || 'exfat';
    showFormatConfirmModal(filesystem);
  });

  if (refreshBtn) {
    refreshBtn.addEventListener('click', () => {
      loadState();
    });
  }

  if (formatConfirmBtn) {
    formatConfirmBtn.addEventListener('click', () => {
      formatConfirmBtn.disabled = true;
      hideFormatConfirmModal();
      executeFormat(pendingFilesystem).finally(() => {
        formatConfirmBtn.disabled = false;
      });
    });
  }

  if (formatConfirmCancelBtn && (!window.bootstrap || !window.bootstrap.Modal)) {
    formatConfirmCancelBtn.addEventListener('click', () => {
      hideFormatConfirmModal();
    });
  }

  if (copyFormatLog) {
    copyFormatLog.addEventListener('click', () => {
      const rawLog = (formatLog && formatLog.dataset && formatLog.dataset.rawLog) ? formatLog.dataset.rawLog : formatLog.textContent;
      if (copyFormatLog.disabled || !rawLog) return;
      const clipboard = window.thinginoClipboard;
      if (!clipboard || typeof clipboard.copy !== 'function') {
        dispatchAlert('warning', 'Clipboard support is not available in this browser.');
        return;
      }
      clipboard.copy(rawLog)
        .then(() => {
          copyFormatLog.innerHTML = '<i class="bi bi-clipboard-check me-1"></i>Copied';
          copyFormatLog.classList.replace('btn-outline-secondary', 'btn-success');
          setTimeout(() => {
            copyFormatLog.innerHTML = '<i class="bi bi-clipboard me-1"></i>Copy raw';
            copyFormatLog.classList.replace('btn-success', 'btn-outline-secondary');
          }, 1500);
        })
        .catch(() => {
          dispatchAlert('warning', 'Unable to copy log output.');
        });
    });
  }

  loadState();
})();
