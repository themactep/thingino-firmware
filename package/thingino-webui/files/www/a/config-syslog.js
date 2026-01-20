(function() {
  const form = $('#syslogForm');
  const hostInput = $('#rsyslog_host');
  const portInput = $('#rsyslog_port');
  const enabledSwitch = $('#rsyslog_enabled');
  const fileSwitch = $('#rsyslog_file');
  const submitButton = $('#rsyslog_submit');
  function sanitizeValue(value) {
    if (typeof value !== 'string') return value;
    const trimmed = value.trim();
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) || (trimmed.startsWith('\'') && trimmed.endsWith('\''))) {
      return trimmed.slice(1, -1);
    }
    return trimmed;
  }

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    hostInput.disabled = state;
    portInput.disabled = state;
    enabledSwitch.disabled = state;
    fileSwitch.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading syslog settings...');
    }
    try {
      const response = await fetch('/x/json-config-syslog.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load remote logging settings');
      const data = await response.json();
      hostInput.value = sanitizeValue(data.host) || '';
      portInput.value = sanitizeValue(data.port) || '514';
      enabledSwitch.checked = data.enabled === true;
      fileSwitch.checked = data.file === true;
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load remote logging settings.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving syslog settings...');
    try {
      const response = await fetch('/x/json-config-syslog.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message = result && result.error && result.error.message ? result.error.message : 'Failed to save settings';
        throw new Error(message);
      }
      showAlert('', '');
      showOverlayMessage('Remote logging settings saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save remote logging settings.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const cleanHost = sanitizeValue(hostInput.value);
    const cleanPort = sanitizeValue(portInput.value);
    const payload = {
      host: cleanHost || '',
      port: cleanPort || '514',
      enabled: enabledSwitch.checked,
      file: fileSwitch.checked
    };
    saveConfig(payload);
  });

  const reloadButton = $('#syslog-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Syslog settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload syslog settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
