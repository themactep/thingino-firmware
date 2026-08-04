(function () {
  const ENDPOINT = '/x/json-config-snmpd.cgi';

  const form = $('#snmpdForm');
  const submitButton = $('#snmpd_submit');
  const statusBadge = $('#snmpd_status');

  const fields = {
    community: $('#snmpd_community'),
    port: $('#snmpd_port'),
    listen: $('#snmpd_listen'),
    location: $('#snmpd_location'),
    contact: $('#snmpd_contact'),
    description: $('#snmpd_description'),
    traps: $('#snmpd_traps'),
    disks: $('#snmpd_disks'),
    interfaces: $('#snmpd_interfaces'),
    timeout: $('#snmpd_timeout'),
    loglevel: $('#snmpd_loglevel')
  };
  const switches = {
    enabled: $('#snmpd_enabled'),
    auth: $('#snmpd_auth')
  };

  function sanitizeValue(value) {
    if (typeof value !== 'string') return value;
    const trimmed = value.trim();
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.slice(1, -1);
    }
    return trimmed;
  }

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    showAlert(variant === 'danger' ? 'danger' : 'info', message);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    Object.values(fields).forEach(function (el) { el.disabled = state; });
    Object.values(switches).forEach(function (el) { el.disabled = state; });
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function renderStatus(status) {
    const running = status && status.running === true;
    statusBadge.textContent = running ? 'running' : 'stopped';
    statusBadge.className = 'badge align-middle ' + (running ? 'bg-success' : 'bg-secondary');
  }

  async function loadConfig(options) {
    options = options || {};
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading SNMP settings...');
    }
    try {
      const response = await fetch(ENDPOINT, {
        headers: { 'Accept': 'application/json' }
      });
      if (!response.ok) throw new Error('Failed to load SNMP settings');
      const data = await response.json();
      const c = data.config || {};

      fields.community.value = sanitizeValue(c.community || '') || 'public';
      fields.port.value = sanitizeValue(String(c.port || '')) || '161';
      fields.listen.value = sanitizeValue(c.listen || '') || '';
      fields.location.value = sanitizeValue(c.location || '') || '';
      fields.contact.value = sanitizeValue(c.contact || '') || '';
      fields.description.value = sanitizeValue(c.description || '') || '';
      fields.traps.value = sanitizeValue(c.traps || '') || '';
      fields.disks.value = sanitizeValue(c.disks || '') || '/';
      fields.interfaces.value = sanitizeValue(c.interfaces || '') || '';
      fields.timeout.value = sanitizeValue(String(c.timeout || '')) || '1';
      fields.loglevel.value = sanitizeValue(c.loglevel || '') || 'notice';

      switches.enabled.checked = c.enabled === true;
      switches.auth.checked = c.auth === true;

      renderStatus(data.status);
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load SNMP settings.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving SNMP settings...');
    try {
      const response = await fetch(ENDPOINT, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const msg = result && result.error && result.error.message
          ? result.error.message : 'Failed to save settings';
        throw new Error(msg);
      }
      showAlert('', '');
      showOverlayMessage('SNMP settings saved.', 'success');
      // The daemon is restarted in the background, give it a moment to settle
      await new Promise(function (resolve) { setTimeout(resolve, 1500); });
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save SNMP settings.');
    } finally {
      toggleBusy(false);
    }
  }

  function normalizeList(value) {
    return sanitizeValue(value)
      .split(',')
      .map(function (item) { return item.trim(); })
      .filter(function (item) { return item.length > 0; })
      .join(',');
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();

    saveConfig({
      enabled: switches.enabled.checked,
      auth: switches.auth.checked,
      community: sanitizeValue(fields.community.value) || 'public',
      port: parseInt(sanitizeValue(fields.port.value), 10) || 161,
      timeout: parseInt(sanitizeValue(fields.timeout.value), 10) || 1,
      loglevel: sanitizeValue(fields.loglevel.value) || 'notice',
      location: sanitizeValue(fields.location.value) || '',
      contact: sanitizeValue(fields.contact.value) || '',
      description: sanitizeValue(fields.description.value) || '',
      listen: sanitizeValue(fields.listen.value) || '',
      interfaces: normalizeList(fields.interfaces.value),
      disks: normalizeList(fields.disks.value) || '/',
      traps: normalizeList(fields.traps.value)
    });
  });

  const reloadButton = $('#snmpd-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async function () {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'SNMP settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload SNMP settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
