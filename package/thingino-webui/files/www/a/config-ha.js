(function () {
  const form = $('#haForm');
  const submitButton = $('#ha_submit');

  // MQTT broker
  const mqttHost     = $('#ha_mqtt_host');
  const mqttPort     = $('#ha_mqtt_port');
  const mqttUsername = $('#ha_mqtt_username');
  const mqttPassword = $('#ha_mqtt_password');
  const mqttClientId = $('#ha_mqtt_client_id_prefix');
  const mqttSsl      = $('#ha_mqtt_use_ssl');

  // Device & timing
  const deviceName       = $('#ha_device_name');
  const deviceModel      = $('#ha_device_model');
  const discoveryPrefix  = $('#ha_discovery_prefix');
  const stateInterval    = $('#ha_state_interval');
  const discoveryInterval = $('#ha_discovery_interval');
  const haEnabled        = $('#ha_enabled');

  // Entity toggles
  const entities = [
    'motion', 'motion_guard', 'ircut', 'daynight', 'privacy',
    'color', 'ir850', 'ir940', 'white_light', 'gain', 'rssi',
    'snapshot', 'reboot', 'ota'
  ];

  function sanitizeValue(value) {
    if (typeof value !== 'string') return value;
    const trimmed = value.trim();
    if ((trimmed.startsWith('"') && trimmed.endsWith('"')) ||
        (trimmed.startsWith("'") && trimmed.endsWith("'"))) {
      return trimmed.slice(1, -1);
    }
    return trimmed;
  }

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    showAlert(variant === 'danger' ? 'danger' : 'info', message);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    [mqttHost, mqttPort, mqttUsername, mqttPassword, mqttClientId, mqttSsl,
     deviceName, deviceModel, discoveryPrefix, stateInterval, discoveryInterval,
     haEnabled].forEach(function (el) { el.disabled = state; });
    entities.forEach(function (e) {
      const el = $('#ha_enable_' + e);
      if (el) el.disabled = state;
    });
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  async function loadConfig(options) {
    options = options || {};
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading Home Assistant settings...');
    }
    try {
      const response = await fetch('/x/json-config-ha.cgi', {
        headers: { 'Accept': 'application/json' }
      });
      if (!response.ok) throw new Error('Failed to load Home Assistant settings');
      const d = await response.json();
      const mqtt = d.mqtt || {};

      mqttHost.value     = sanitizeValue(mqtt.host || '') || '';
      mqttPort.value     = sanitizeValue(String(mqtt.port || '')) || '1883';
      mqttUsername.value = sanitizeValue(mqtt.username || '') || '';
      mqttPassword.value = sanitizeValue(mqtt.password || '') || '';
      mqttClientId.value = sanitizeValue(mqtt.client_id_prefix || '') || 'thingino-ha';
      mqttSsl.checked    = mqtt.use_ssl === true;

      deviceName.value        = sanitizeValue(d.device_name || '') || '';
      deviceModel.value       = sanitizeValue(d.device_model || '') || '';
      discoveryPrefix.value   = sanitizeValue(d.discovery_prefix || '') || 'homeassistant';
      stateInterval.value     = sanitizeValue(String(d.state_interval || '')) || '15';
      discoveryInterval.value = sanitizeValue(String(d.discovery_interval || '')) || '3600';
      haEnabled.checked       = d.enabled === true;

      entities.forEach(function (e) {
        const el = $('#ha_enable_' + e);
        if (el) {
          const key = 'enable_' + e;
          el.checked = d[key] !== false;
        }
      });
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load Home Assistant settings.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving Home Assistant settings...');
    try {
      const response = await fetch('/x/json-config-ha.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const msg = result && result.error && result.error.message
          ? result.error.message : 'Failed to save settings';
        throw new Error(msg);
      }
      showAlert('', '');
      showOverlayMessage('Home Assistant settings saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save Home Assistant settings.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();

    const payload = {
      enabled: haEnabled.checked,
      device_name: sanitizeValue(deviceName.value) || '',
      device_model: sanitizeValue(deviceModel.value) || '',
      discovery_prefix: sanitizeValue(discoveryPrefix.value) || 'homeassistant',
      state_interval: parseInt(sanitizeValue(stateInterval.value), 10) || 15,
      discovery_interval: parseInt(sanitizeValue(discoveryInterval.value), 10) || 3600,
      mqtt: {
        host: sanitizeValue(mqttHost.value) || '',
        port: parseInt(sanitizeValue(mqttPort.value), 10) || 1883,
        username: sanitizeValue(mqttUsername.value) || '',
        password: sanitizeValue(mqttPassword.value) || '',
        client_id_prefix: sanitizeValue(mqttClientId.value) || 'thingino-ha',
        use_ssl: mqttSsl.checked
      }
    };

    entities.forEach(function (e) {
      const el = $('#ha_enable_' + e);
      payload['enable_' + e] = el ? el.checked : false;
    });

    saveConfig(payload);
  });

  const reloadButton = $('#ha-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async function () {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Home Assistant settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload Home Assistant settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
