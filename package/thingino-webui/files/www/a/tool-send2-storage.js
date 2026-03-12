(function() {
  'use strict';

  const form = $('#storageForm');
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
    await send2Load('Storage', async data => {
      await loadMountpoints();
      const storage = data.storage || {};
      $('#storage_mount').value = storage.mount || '';
      $('#storage_device_path').value = storage.device_path || '%hostname/motion';
      $('#storage_template').value = storage.template || '%Y%m%d/%H/%Y%m%dT%H%M%S';
      $('#storage_send_photo').checked = storage.send_photo !== false && storage.send_photo !== 'false';
      $('#storage_send_video').checked = storage.send_video === true || storage.send_video === 'true';
    });
  }

  if (form) {
    form.addEventListener('submit', (event) =>
      send2Save('Storage', form, event, () => {
        const devicePath = $('#storage_device_path').value.trim() || '%hostname/motion';
        const template = $('#storage_template').value.trim() || '%Y%m%d/%H/%Y%m%dT%H%M%S';
        return {
          storage: {
            mount: $('#storage_mount').value.trim(),
            device_path: devicePath,
            template: template,
            send_photo: $('#storage_send_photo').checked,
            send_video: $('#storage_send_video').checked,
            enabled: true
          }
        };
      })
    );
  }

  send2SetupReload($('#storage-reload'), 'Storage', loadConfig);
  loadConfig();
})();
