(function() {
  const API_URL = '/x/tool-record.cgi';
  const statusEl = $('#statusMessage');
  const videoForm = $('#videoForm');
  const videoMount = $('#videoMount');
  const videoMountLink = $('#videoMountLink');
  const videoDevicePath = $('#videoDevicePath');
  const videoFilename = $('#videoFilename');
  const videoChannel = $('#videoChannel');
  const videoDuration = $('#videoDuration');
  const videoLimit = $('#videoLimit');
  const videoAutostart = $('#videoAutostart');
  const videoSubmit = $('#videoSubmit');
  const videoStrftimeHint = $('#videoStrftimeHint');

  const debugVideo = $('#debugVideo');
  const debugCrontab = $('#debugCrontab');

  const buttonLabels = new Map();
  if (videoSubmit) buttonLabels.set(videoSubmit, videoSubmit.innerHTML);
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

  function updateVideoLink() {
    const mount = getValue(videoMount).trim();
    updateLink(videoMountLink, mount);
  }

  function applyVideoState(video = {}) {
    if (videoDevicePath) videoDevicePath.value = video.device_path || '';
    if (videoFilename) videoFilename.value = video.filename || '';
    if (videoChannel) videoChannel.value = typeof video.channel === 'number' ? String(video.channel) : (video.channel || '0');
    if (videoDuration) videoDuration.value = video.duration || 60;
    if (videoLimit) videoLimit.value = video.limit || 15;
    if (videoAutostart) videoAutostart.checked = boolFromValue(video.autostart);
  }

  function renderDebug(debug = {}) {
    if (debugVideo) debugVideo.textContent = debug.video || 'No recorder data available.';
    if (debugCrontab) debugCrontab.textContent = debug.crontab || 'No crontab entries available.';
  }

  function updateHints(hint) {
    const text = hint || 'Supports strftime-style placeholders such as %Y or %H.';
    if (videoStrftimeHint) videoStrftimeHint.textContent = text;
  }

  function applyState(data = {}) {
    const mounts = Array.isArray(data.mounts) ? data.mounts : [];
    populateMountSelect(videoMount, mounts, data.video && data.video.mount);
    applyVideoState(data.video || {});
    updateVideoLink();
    updateHints(data.messages && data.messages.strftime_hint);
    renderDebug(data.debug || {});
  }

  async function loadState() {
    showBusy('Loading recorder settings...');
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

  function buildVideoParams() {
    const params = new URLSearchParams();
    params.set('form', 'video');
    params.set('vr_mount', getValue(videoMount).trim());
    params.set('vr_device_path', getValue(videoDevicePath).trim());
    params.set('vr_filename', getValue(videoFilename).trim());
    params.set('vr_channel', getValue(videoChannel) || '0');
    params.set('vr_duration', getValue(videoDuration));
    params.set('vr_limit', getValue(videoLimit));
    params.set('vr_autostart', isChecked(videoAutostart) ? 'true' : 'false');
    return params;
  }

  async function submitForm(event) {
    event.preventDefault();
    toggleButton(videoSubmit, true);
    showBusy('Saving recorder settings...');
    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: buildVideoParams().toString()
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error ? payload.error.message : `Request failed with status ${response.status}`;
        throw new Error(message || 'Unable to save changes');
      }
      applyState(payload.data || {});
      const successMessage = payload.message || 'Video recorder updated.';
      setStatus(successMessage, 'success');
      showAlert('success', successMessage);
      setTimeout(hideStatus, 2000);
    } catch (err) {
      setStatus('Unable to save changes.', 'danger');
      showAlert('danger', err.message || 'Unexpected error while saving.');
    } finally {
      hideBusy();
      toggleButton(videoSubmit, false);
    }
  }

  if (videoForm) videoForm.addEventListener('submit', submitForm);
  if (videoMount) videoMount.addEventListener('change', updateVideoLink);

  loadState();
})();
