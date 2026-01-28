(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#telegramForm');
  const reloadButton = $('#telegram-reload');

  async function loadConfig() {
    showBusy('Loading Telegram settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const telegram = data.telegram || {};

      $('#telegram_token').value = telegram.token || '';
      $('#telegram_channel').value = telegram.channel || '';
      $('#telegram_caption').value = telegram.caption || '';
      $('#telegram_send_photo').checked = telegram.send_photo !== false && telegram.send_photo !== 'false';
      $('#telegram_send_video').checked = telegram.send_video === true || telegram.send_video === 'true';

    } catch (err) {
      console.error('Failed to load Telegram config:', err);
      showAlert('danger', `Failed to load Telegram settings: ${err.message || err}`);
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

    showBusy('Saving Telegram settings...');

    try {
      const payload = {
        telegram: {
          token: $('#telegram_token').value.trim(),
          channel: $('#telegram_channel').value.trim(),
          caption: $('#telegram_caption').value.trim(),
          send_photo: $('#telegram_send_photo').checked,
          send_video: $('#telegram_send_video').checked,
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

      showAlert('success', 'Telegram settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save Telegram settings:', err);
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
        showAlert('info', 'Telegram settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Telegram settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
