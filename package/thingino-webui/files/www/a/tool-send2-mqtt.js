(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  const form = $('#mqttForm');
  const reloadButton = $('#mqtt-reload');

  async function loadConfig() {
    showBusy('Loading MQTT settings...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });
      
      if (!response.ok) throw new Error('Failed to load configuration');
      
      const data = await response.json();
      const mqtt = data.mqtt || {};
      
      $('#mqtt_client_id').value = mqtt.client_id || '';
      $('#mqtt_host').value = mqtt.host || '';
      $('#mqtt_port').value = mqtt.port || '1883';
      $('#mqtt_username').value = mqtt.username || '';
      $('#mqtt_password').value = mqtt.password || '';
      $('#mqtt_use_ssl').checked = mqtt.use_ssl === true || mqtt.use_ssl === 'true';
      $('#mqtt_topic').value = mqtt.topic || '';
      $('#mqtt_message').value = mqtt.message || '';

    } catch (err) {
      console.error('Failed to load MQTT config:', err);
      showAlert('danger', `Failed to load MQTT settings: ${err.message || err}`);
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

    showBusy('Saving MQTT settings...');
    
    try {
      const payload = {
        mqtt: {
          client_id: $('#mqtt_client_id').value.trim(),
          host: $('#mqtt_host').value.trim(),
          port: Number($('#mqtt_port').value) || 1883,
          username: $('#mqtt_username').value.trim(),
          password: $('#mqtt_password').value.trim(),
          use_ssl: $('#mqtt_use_ssl').checked,
          topic: $('#mqtt_topic').value.trim(),
          message: $('#mqtt_message').value.trim(),
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

      showAlert('success', 'MQTT settings saved successfully.', 3000);
      form.classList.remove('was-validated');
      
    } catch (err) {
      console.error('Failed to save MQTT settings:', err);
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
        showAlert('info', 'MQTT settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload MQTT settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
