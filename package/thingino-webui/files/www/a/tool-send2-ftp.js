(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#ftpForm');
  const reloadButton = $('#ftp-reload');

  async function loadConfig() {
    showBusy('Loading FTP settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const ftp = data.ftp || {};

      $('#ftp_host').value = ftp.host || '';
      $('#ftp_port').value = ftp.port || '21';
      $('#ftp_username').value = ftp.username || '';
      $('#ftp_password').value = ftp.password || '';
      $('#ftp_path').value = ftp.path || '';
      $('#ftp_template').value = ftp.template || '';
      $('#ftp_send_photo').checked = ftp.send_photo !== false && ftp.send_photo !== 'false';
      $('#ftp_send_video').checked = ftp.send_video === true || ftp.send_video === 'true';

    } catch (err) {
      console.error('Failed to load FTP config:', err);
      showAlert('danger', `Failed to load FTP settings: ${err.message || err}`);
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

    showBusy('Saving FTP settings...');

    try {
      const payload = {
        ftp: {
          host: $('#ftp_host').value.trim(),
          port: Number($('#ftp_port').value) || 21,
          username: $('#ftp_username').value.trim(),
          password: $('#ftp_password').value.trim(),
          path: $('#ftp_path').value.trim(),
          template: $('#ftp_template').value.trim(),
          send_photo: $('#ftp_send_photo').checked,
          send_video: $('#ftp_send_video').checked,
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

      showAlert('success', 'FTP settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save FTP settings:', err);
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
        showAlert('info', 'FTP settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload FTP settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
