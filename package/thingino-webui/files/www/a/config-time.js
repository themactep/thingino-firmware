(function() {
  const form = $('#timeForm');
  const tzNameInput = $('#tz_name');
  const tzDataInput = $('#tz_data');
  const ntpServer0 = $('#ntp_server_0');
  const ntpServer1 = $('#ntp_server_1');
  const ntpServer2 = $('#ntp_server_2');
  const ntpServer3 = $('#ntp_server_3');
  const submitButton = $('#time_submit');
  const syncButton = $('#sync-time');
  const syncResult = $('#sync-time-result');

  let TZ = [];

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function showSyncResult(type, text) {
    syncResult.innerHTML = '';
    if (!text) return;
    const wrapper = document.createElement('div');
    wrapper.className = `alert alert-${type}`;
    wrapper.textContent = text;
    syncResult.appendChild(wrapper);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    tzNameInput.disabled = state;
    ntpServer0.disabled = state;
    ntpServer1.disabled = state;
    ntpServer2.disabled = state;
    ntpServer3.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function findTimezone(tzName) {
    return TZ.find(tz => tz.n === tzName);
  }

  function updateTimezone() {
    const tz = findTimezone(tzNameInput.value);
    tzDataInput.value = tz ? tz.v : '';
  }

  function useBrowserTimezone(event) {
    event.preventDefault();
    tzNameInput.value = Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_', ' ');
    updateTimezone();
  }

  function populateTimezones() {
    const el = $('#tz_list');
    if (!el) return;
    el.innerHTML = '';
    TZ.forEach((tz) => {
      const option = document.createElement('option');
      option.value = tz.n;
      el.appendChild(option);
    });
  }

  async function loadTimezones() {
    try {
      const response = await fetch('/a/tz.json');
      if (!response.ok) throw new Error('Failed to load timezone data');
      TZ = await response.json();
      populateTimezones();
      updateTimezone();
    } catch (err) {
      console.error('Failed to load timezones:', err);
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading time settings...');
    }
    try {
      const response = await fetch('/x/json-config-time.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load time configuration');
      const data = await response.json();
      tzNameInput.value = data.tz_name || '';
      tzDataInput.value = data.tz_data || '';
      ntpServer0.value = data.ntp_server_0 || '';
      ntpServer1.value = data.ntp_server_1 || '';
      ntpServer2.value = data.ntp_server_2 || '';
      ntpServer3.value = data.ntp_server_3 || '';
      updateTimezone();
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load time configuration.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving time settings...');
    try {
      const response = await fetch('/x/json-config-time.cgi', {
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
      showOverlayMessage(result.message || 'Time configuration saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save time configuration.');
    } finally {
      toggleBusy(false);
    }
  }

  async function syncTime() {
    syncButton.disabled = true;
    syncButton.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Synchronizing...';
    showBusy('Synchronizing time...');
    showSyncResult('', '');

    try {
      const response = await fetch('/x/json-sync-time.cgi?' + new URLSearchParams({ ts: Date.now() }).toString());
      const result = await response.json();

      if (result.error) {
        showSyncResult('danger', result.error.message || 'Synchronization failed');
      } else {
        showSyncResult('success', result.message || 'Time synchronized');
      }
    } catch (err) {
      showSyncResult('danger', err.message || 'Failed to synchronize time');
    } finally {
      hideBusy();
      syncButton.disabled = false;
      syncButton.innerHTML = '<i class="bi bi-arrow-repeat"></i> Synchronize time';
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const payload = {
      action: 'update',
      tz_name: tzNameInput.value.trim(),
      tz_data: tzDataInput.value.trim(),
      ntp_server_0: ntpServer0.value.trim(),
      ntp_server_1: ntpServer1.value.trim(),
      ntp_server_2: ntpServer2.value.trim(),
      ntp_server_3: ntpServer3.value.trim()
    };
    saveConfig(payload);
  });

  tzNameInput.addEventListener('change', updateTimezone);
  tzNameInput.addEventListener('input', updateTimezone);

  $('#frombrowser').addEventListener('click', useBrowserTimezone);
  syncButton.addEventListener('click', syncTime);

  const reloadButton = $('#time-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Time settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload time settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadTimezones();
  loadConfig();
})();
