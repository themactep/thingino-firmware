(function() {
  const form = $('#adminForm');
  const nameInput = $('#admin_name');
  const emailInput = $('#admin_email');
  const telegramInput = $('#admin_telegram');
  const discordInput = $('#admin_discord');
  const submitButton = $('#admin_submit');

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
    nameInput.disabled = state;
    emailInput.disabled = state;
    telegramInput.disabled = state;
    discordInput.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading admin settings...');
    }
    try {
      const response = await fetch('/x/json-config-admin.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load admin profile');
      const data = await response.json();
      nameInput.value = data.name || '';
      emailInput.value = data.email || '';
      telegramInput.value = data.telegram || '';
      discordInput.value = data.discord || '';
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load admin profile.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving admin settings...');
    try {
      const response = await fetch('/x/json-config-admin.cgi', {
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
      showOverlayMessage('Admin profile saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save admin profile.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const payload = {
      name: nameInput.value.trim(),
      email: emailInput.value.trim(),
      telegram: telegramInput.value.trim(),
      discord: discordInput.value.trim()
    };
    saveConfig(payload);
  });

  const reloadButton = $('#admin-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Admin settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload admin settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
