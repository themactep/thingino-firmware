(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#webhookForm');
  const reloadButton = $('#webhook-reload');

  async function loadConfig() {
    showBusy('Loading Webhook settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const webhook = data.webhook || {};

      $('#webhook_url').value = webhook.url || '';
      $('#webhook_message').value = webhook.message || '';
      $('#webhook_send_photo').checked = webhook.send_photo !== false && webhook.send_photo !== 'false';
      $('#webhook_send_video').checked = webhook.send_video === true || webhook.send_video === 'true';

    } catch (err) {
      console.error('Failed to load Webhook config:', err);
      showAlert('danger', `Failed to load Webhook settings: ${err.message || err}`);
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

    showBusy('Saving Webhook settings...');

    try {
      const payload = {
        webhook: {
          url: $('#webhook_url').value.trim(),
          message: $('#webhook_message').value.trim(),
          send_photo: $('#webhook_send_photo').checked,
          send_video: $('#webhook_send_video').checked,
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

      showAlert('success', 'Webhook settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save Webhook settings:', err);
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
        showAlert('info', 'Webhook settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Webhook settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
