(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#gphotosForm');
  const reloadButton = $('#gphotos-reload');

  async function loadConfig() {
    showBusy('Loading Google Photos settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const gphotos = data.gphotos || {};

      $('#gphotos_client_id').value = gphotos.client_id || '';
      $('#gphotos_client_secret').value = gphotos.client_secret || '';
      $('#gphotos_refresh_token').value = gphotos.refresh_token || '';
      $('#gphotos_album_id').value = gphotos.album_id || '';
      $('#gphotos_description_template').value = gphotos.description_template || '';
      $('#gphotos_photo_name_template').value = gphotos.photo_name_template || '';
      $('#gphotos_video_name_template').value = gphotos.video_name_template || '';

    } catch (err) {
      console.error('Failed to load Google Photos config:', err);
      showAlert('danger', `Failed to load Google Photos settings: ${err.message || err}`);
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

    showBusy('Saving Google Photos settings...');

    try {
      const payload = {
        gphotos: {
          client_id: $('#gphotos_client_id').value.trim(),
          client_secret: $('#gphotos_client_secret').value.trim(),
          refresh_token: $('#gphotos_refresh_token').value.trim(),
          album_id: $('#gphotos_album_id').value.trim(),
          description_template: $('#gphotos_description_template').value.trim(),
          photo_name_template: $('#gphotos_photo_name_template').value.trim(),
          video_name_template: $('#gphotos_video_name_template').value.trim(),
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

      showAlert('success', 'Google Photos settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save Google Photos settings:', err);
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
        showAlert('info', 'Google Photos settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Google Photos settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
