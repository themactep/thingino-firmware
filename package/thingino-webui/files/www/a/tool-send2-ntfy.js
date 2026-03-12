(function() {
  'use strict';

  const form = $('#ntfyForm');

  async function loadConfig() {
    await send2Load('Ntfy', data => {
      const ntfy = data.ntfy || {};
      $('#ntfy_host').value = ntfy.host || '';
      $('#ntfy_port').value = ntfy.port || '443';
      $('#ntfy_topic').value = ntfy.topic || '';
      $('#ntfy_username').value = ntfy.username || '';
      $('#ntfy_password').value = ntfy.password || '';
      $('#ntfy_token').value = ntfy.token || '';
      $('#ntfy_use_ssl').checked = ntfy.use_ssl !== false && ntfy.use_ssl !== 'false';
    });
  }

  if (form) {
    form.addEventListener('submit', (event) =>
      send2Save('Ntfy', form, event, () => ({
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
      }))
    );
  }

  send2SetupReload($('#ntfy-reload'), 'Ntfy', loadConfig);
  loadConfig();
})();
