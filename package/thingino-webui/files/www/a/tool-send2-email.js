(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#emailForm');
  const reloadButton = $('#email-reload');

  async function loadConfig() {
    showBusy('Loading email settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });
      
      if (!response.ok) throw new Error('Failed to load configuration');
      
      const data = await response.json();
      const email = data.email || {};
      
      // Apply email settings
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

    } catch (err) {
      console.error('Failed to load email config:', err);
      showAlert('danger', `Failed to load email settings: ${err.message || err}`);
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

    showBusy('Saving email settings...');
    
    try {
      const payload = {
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

      showAlert('success', 'Email settings saved successfully.', 3000);
      form.classList.remove('was-validated');
      
    } catch (err) {
      console.error('Failed to save email settings:', err);
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
        showAlert('info', 'Email settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload email settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  // Test button handler is in tool-send2.js (handles all service test buttons)
  
  loadConfig();
})();
