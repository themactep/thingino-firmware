(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#storageForm');
  const reloadButton = $('#storage-reload');
  const mountSelect = $('#storage_mount');

  async function loadMountpoints() {
    try {
      const cmd = "awk '/cif|fat|nfs|smb/{print $2}' /etc/mtab";
      const encodedCmd = btoa(cmd);
      const response = await fetch(`/x/run.cgi?cmd=${encodedCmd}`);
      const text = await response.text();

      // Extract mountpoints from the HTML response (between <b># command</b> and <b># </b>)
      const lines = text.split('\n');
      const mounts = [];
      let capturing = false;

      for (const line of lines) {
        if (line.includes('</b>') && !line.includes('#')) {
          capturing = true;
          continue;
        }
        if (line.includes('<b>#') && line.includes('</b>')) {
          if (capturing) break;
          continue;
        }
        if (capturing && line.trim() && !line.includes('<')) {
          mounts.push(line.trim());
        }
      }

      mountSelect.innerHTML = '<option value="">Select mount point...</option>';
      mounts.forEach(mount => {
        const option = document.createElement('option');
        option.value = mount;
        option.textContent = mount;
        mountSelect.appendChild(option);
      });
    } catch (err) {
      console.error('Failed to load mountpoints:', err);
    }
  }

  async function loadConfig() {
    showBusy('Loading Storage settings...');
    try {
      await loadMountpoints();

      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error('Failed to load configuration');

      const data = await response.json();
      const storage = data.storage || {};

      $('#storage_mount').value = storage.mount || '';
      $('#storage_device_path').value = storage.device_path || '%hostname/motion';
      $('#storage_template').value = storage.template || '%Y%m%d/%H/%Y%m%dT%H%M%S';
      $('#storage_send_photo').checked = storage.send_photo !== false && storage.send_photo !== 'false';
      $('#storage_send_video').checked = storage.send_video === true || storage.send_video === 'true';

    } catch (err) {
      console.error('Failed to load Storage config:', err);
      showAlert('danger', `Failed to load Storage settings: ${err.message || err}`);
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

    showBusy('Saving Storage settings...');

    try {
      // Apply defaults if empty
      let devicePath = $('#storage_device_path').value.trim();
      let template = $('#storage_template').value.trim();

      if (!devicePath) {
        devicePath = '%hostname/motion';
      }
      if (!template) {
        template = '%Y%m%d/%H/%Y%m%dT%H%M%S';
      }

      const payload = {
        storage: {
          mount: $('#storage_mount').value.trim(),
          device_path: devicePath,
          template: template,
          send_photo: $('#storage_send_photo').checked,
          send_video: $('#storage_send_video').checked,
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

      showAlert('success', 'Storage settings saved successfully.', 3000);
      form.classList.remove('was-validated');

    } catch (err) {
      console.error('Failed to save Storage settings:', err);
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
        showAlert('info', 'Storage settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Storage settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
