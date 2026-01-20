(function() {
  const API_URL = '/x/tool-record.cgi';
  const statusEl = $('#statusMessage');
  const timelapseForm = $('#timelapseForm');
  const timelapseMount = $('#timelapseMount');
  const timelapseMountLink = $('#timelapseMountLink');
  const timelapseFilepath = $('#timelapseFilepath');
  const timelapseFilename = $('#timelapseFilename');
  const timelapseInterval = $('#timelapseInterval');
  const timelapseKeepDays = $('#timelapseKeepDays');
  const timelapseEnabled = $('#timelapseEnabled');
  const timelapsePreset = $('#timelapsePreset');
  const presetIrcut = $('#presetIrcut');
  const presetIr850 = $('#presetIr850');
  const presetIr940 = $('#presetIr940');
  const presetWhite = $('#presetWhite');
  const presetColor = $('#presetColor');
  const timelapseSubmit = $('#timelapseSubmit');
  const timelapseStrftimeHint = $('#timelapseStrftimeHint');

  const debugTimelapse = $('#debugTimelapse');
  const debugCrontab = $('#debugCrontab');

  const buttonLabels = new Map();
  if (timelapseSubmit) buttonLabels.set(timelapseSubmit, timelapseSubmit.innerHTML);

  function getValue(el) {
    return el && typeof el.value === 'string' ? el.value : '';
  }

  function isChecked(el) {
    return !!(el && el.checked);
  }

  function setStatus(message, variant = 'info') {
    if (!statusEl) return;
    statusEl.textContent = message;
    statusEl.className = `alert alert-${variant} status-overlay`;
    statusEl.classList.remove('d-none');
  }

  function hideStatus() {
    if (!statusEl) return;
    statusEl.classList.add('d-none');
  }

  function toggleButton(button, loading) {
    if (!button) return;
    if (loading) {
      button.disabled = true;
      button.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Saving...';
    } else {
      button.disabled = false;
      button.innerHTML = buttonLabels.get(button) || 'Save changes';
    }
  }

  function populateMountSelect(select, mounts = [], current = '') {
    if (!select) return;
    select.innerHTML = '';
    const placeholder = document.createElement('option');
    placeholder.value = '';
    placeholder.textContent = mounts.length ? 'Select a mount' : 'No mounts detected';
    select.appendChild(placeholder);
    mounts.forEach(value => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      select.appendChild(option);
    });
    if (current && !mounts.includes(current)) {
      const fallback = document.createElement('option');
      fallback.value = current;
      fallback.textContent = `${current} (missing)`;
      select.appendChild(fallback);
    }
    select.value = current || '';
  }

  function boolFromValue(value) {
    return value === true || value === 'true' || value === 1 || value === '1';
  }

  function updateLink(link, path) {
    if (!link) return;
    if (!path) {
      link.classList.add('disabled');
      link.setAttribute('aria-disabled', 'true');
      link.removeAttribute('href');
      return;
    }
    const normalized = path.startsWith('/') ? path : `/${path}`;
    const url = normalized === '/' ? '/tool-file-manager.html' : `/tool-file-manager.html?cd=${encodeURIComponent(normalized)}`;
    link.classList.remove('disabled');
    link.removeAttribute('aria-disabled');
    link.href = url;
  }

  function updateTimelapseLink() {
    const mount = getValue(timelapseMount).trim();
    const folder = getValue(timelapseFilepath).trim();
    let target = mount;
    if (mount && folder) {
      target = `${mount.replace(/\/+$/, '')}/${folder.replace(/^\/+/, '')}`;
    }
    updateLink(timelapseMountLink, target);
  }

  function applyTimelapseState(tl = {}) {
    if (timelapseEnabled) timelapseEnabled.checked = boolFromValue(tl.enabled);
    if (timelapseFilepath) timelapseFilepath.value = tl.filepath || '';
    if (timelapseFilename) timelapseFilename.value = tl.filename || '';
    if (timelapseInterval) timelapseInterval.value = tl.interval || 1;
    if (timelapseKeepDays) timelapseKeepDays.value = typeof tl.keep_days === 'number' ? tl.keep_days : (tl.keep_days || 7);
    if (timelapsePreset) timelapsePreset.checked = boolFromValue(tl.preset_enabled);
    const presets = tl.presets || {};
    if (presetIrcut) presetIrcut.checked = boolFromValue(presets.ircut);
    if (presetIr850) presetIr850.checked = boolFromValue(presets.ir850);
    if (presetIr940) presetIr940.checked = boolFromValue(presets.ir940);
    if (presetWhite) presetWhite.checked = boolFromValue(presets.white);
    if (presetColor) presetColor.checked = boolFromValue(presets.color);
  }

  function renderDebug(debug = {}) {
    if (debugTimelapse) debugTimelapse.textContent = debug.timelapse || 'No timelapse data available.';
    if (debugCrontab) debugCrontab.textContent = debug.crontab || 'No crontab entries available.';
  }

  function updateHints(hint) {
    const text = hint || 'Supports strftime-style placeholders such as %Y or %H.';
    if (timelapseStrftimeHint) timelapseStrftimeHint.textContent = text;
  }

  function applyState(data = {}) {
    const mounts = Array.isArray(data.mounts) ? data.mounts : [];
    populateMountSelect(timelapseMount, mounts, data.timelapse && data.timelapse.mount);
    applyTimelapseState(data.timelapse || {});
    updateTimelapseLink();
    updateHints(data.messages && data.messages.strftime_hint);
    renderDebug(data.debug || {});
  }

  async function loadState() {
    showBusy('Loading timelapse settings...');
    try {
      const response = await fetch(API_URL, { headers: { 'Accept': 'application/json' } });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error ? payload.error.message : `Request failed with status ${response.status}`;
        throw new Error(message || 'Unable to load settings');
      }
      applyState(payload.data || {});
      setStatus('Settings loaded.', 'success');
      setTimeout(hideStatus, 2000);
    } catch (err) {
      setStatus('Unable to load settings.', 'danger');
      showAlert('danger', err.message || 'Recorder API request failed.');
    } finally {
      hideBusy();
    }
  }

  function buildTimelapseParams() {
    const params = new URLSearchParams();
    params.set('form', 'timelapse');
    params.set('tl_enabled', isChecked(timelapseEnabled) ? 'true' : 'false');
    params.set('tl_mount', getValue(timelapseMount).trim());
    params.set('tl_filepath', getValue(timelapseFilepath).trim());
    params.set('tl_filename', getValue(timelapseFilename).trim());
    params.set('tl_interval', getValue(timelapseInterval));
    params.set('tl_keep_days', getValue(timelapseKeepDays));
    params.set('tl_preset_enabled', isChecked(timelapsePreset) ? 'true' : 'false');
    params.set('tl_ircut', isChecked(presetIrcut) ? 'true' : 'false');
    params.set('tl_ir850', isChecked(presetIr850) ? 'true' : 'false');
    params.set('tl_ir940', isChecked(presetIr940) ? 'true' : 'false');
    params.set('tl_white', isChecked(presetWhite) ? 'true' : 'false');
    params.set('tl_color', isChecked(presetColor) ? 'true' : 'false');
    return params;
  }

  async function submitForm(event) {
    event.preventDefault();
    toggleButton(timelapseSubmit, true);
    showBusy('Saving timelapse settings...');
    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: buildTimelapseParams().toString()
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error ? payload.error.message : `Request failed with status ${response.status}`;
        throw new Error(message || 'Unable to save changes');
      }
      applyState(payload.data || {});
      const successMessage = payload.message || 'Timelapse recorder updated.';
      setStatus(successMessage, 'success');
      showAlert('success', successMessage);
      setTimeout(hideStatus, 2000);
    } catch (err) {
      setStatus('Unable to save changes.', 'danger');
      showAlert('danger', err.message || 'Unexpected error while saving.');
    } finally {
      hideBusy();
      toggleButton(timelapseSubmit, false);
    }
  }

  if (timelapseForm) timelapseForm.addEventListener('submit', submitForm);
  if (timelapseMount) timelapseMount.addEventListener('change', updateTimelapseLink);
  if (timelapseFilepath) timelapseFilepath.addEventListener('input', updateTimelapseLink);

  loadState();
})();
