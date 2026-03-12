(function() {
  'use strict';

  const form = $('#emailForm');

  async function loadConfig() {
    await send2Load('Email', data => {
      const email = data.email || {};
      $('#email_host').value = email.host || '';
      $('#email_port').value = email.port || '587';
      $('#email_username').value = email.username || '';
      $('#email_password').value = email.password || '';
      $('#email_use_ssl').checked = email.use_ssl === true || email.use_ssl === 'true';
      $('#email_trust_cert').checked = email.trust_cert === true || email.trust_cert === 'true';
      $('#email_from_name').value = email.from_name || '';
      $('#email_from_address').value = email.from_address || '';
      $('#email_to_name').value = email.to_name || '';
      $('#email_to_address').value = email.to_address || '';
      $('#email_send_photo').checked = email.send_photo !== false && email.send_photo !== 'false';
      $('#email_send_video').checked = email.send_video === true || email.send_video === 'true';
      $('#email_subject').value = email.subject || 'Motion detected';
      $('#email_body').value = email.body || '';
    });
  }

  if (form) {
    form.addEventListener('submit', (event) =>
      send2Save('Email', form, event, () => ({
        email: {
          host: $('#email_host').value.trim(),
          port: Number($('#email_port').value) || 587,
          username: $('#email_username').value.trim(),
          password: $('#email_password').value.trim(),
          use_ssl: $('#email_use_ssl').checked,
          trust_cert: $('#email_trust_cert').checked,
          from_name: $('#email_from_name').value.trim(),
          from_address: $('#email_from_address').value.trim(),
          to_name: $('#email_to_name').value.trim(),
          to_address: $('#email_to_address').value.trim(),
          send_photo: $('#email_send_photo').checked,
          send_video: $('#email_send_video').checked,
          subject: $('#email_subject').value.trim(),
          body: $('#email_body').value.trim(),
          enabled: true
        }
      }))
    );
  }

  // Test button handler is in tool-send2.js (handles all service test buttons)
  send2SetupReload($('#email-reload'), 'Email', loadConfig);
  loadConfig();
})();
