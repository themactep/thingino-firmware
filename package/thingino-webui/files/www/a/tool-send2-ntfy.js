(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#ntfyForm');
  const reloadButton = $('#ntfy-reload');

  async function loadConfig() {
    showBusy('Loading Ntfy settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const ntfy = data.ntfy || {};

      $('#ntfy_host').value = ntfy.host || '';
      $('#ntfy_port').value = ntfy.port || '443';
      $('#ntfy_topic').value = ntfy.topic || '';
      $('#ntfy_username').value = ntfy.username || '';
      $('#ntfy_password').value = ntfy.password || '';
      $('#ntfy_token').value = ntfy.token || '';
      $('#ntfy_use_ssl').checked = ntfy.use_ssl !== false && ntfy.use_ssl !== 'false';

    } catch (err) {
      console.error('Failed to load Ntfy config:', err);
      showAlert('danger', `Failed to load Ntfy settings: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  async function saveConfig(event) {
    event.preventDefault();

    if (!form.checkValidity()) {
      event.stopPropagation();
      form.classList.add('was-validated');
      return;
    }

    showBusy('Saving Ntfy settings...');

    try {
      const payload = {
        ntfy: {
          host: $('#ntfy_host').value.trim(),
          port: Number($('#ntfy_port').value) || 443,
          topic: $('#ntfy_topic').value.trim(),
          username: $('#ntfy_username').value.trim(),
          password: $('#ntfy_password').value.trim(),
          token: $('#ntfy_token').value.trim(),
          use_ssl: $('#ntfy_use_ssl').checked,
          enabled: true
        }
      };

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!response.ok) throw new Error('Failed to save settings');

      const result = await response.json();

      if (result.error) {
        throw new Error(result.error.message || 'Failed to save settings');
      }

      showAlert('success', 'Ntfy settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save Ntfy settings:', err);
      showAlert('danger', `Failed to save settings: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  if (form) {
    form.addEventListener('submit', saveConfig);
  }

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Ntfy settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Ntfy settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
