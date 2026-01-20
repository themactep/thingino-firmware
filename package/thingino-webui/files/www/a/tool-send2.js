(function() {
  'use strict';

  const endpoint = '/x/json-send2.cgi';
  
  const motionEnabledInput = $('#motion_enabled');
  const motionSensitivityInput = $('#motion_sensitivity');
  const motionSensitivityValue = $('#motion_sensitivity_value');
  const motionCooldownInput = $('#motion_cooldown');
  const motionCooldownValue = $('#motion_cooldown_value');
  const saveMotionButton = $('#save_motion');

  // Update slider value displays
  if (motionSensitivityInput) {
    motionSensitivityInput.addEventListener('input', () => {
      if (motionSensitivityValue) {
        motionSensitivityValue.textContent = motionSensitivityInput.value;
      }
    });
  }

  if (motionCooldownInput) {
    motionCooldownInput.addEventListener('input', () => {
      if (motionCooldownValue) {
        motionCooldownValue.textContent = motionCooldownInput.value;
      }
    });
  }

  async function updateMotionValue(service, value) {
    try {
      const payload = {
        motion: {
          [service]: value
        }
      };

      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!response.ok) throw new Error('Failed to update');
      
      const result = await response.json();
      if (result.error) throw new Error(result.error.message);
      
    } catch (err) {
      console.error(`Failed to update ${service}:`, err);
      showAlert('danger', `Failed to update ${service}: ${err.message || err}`);
    }
  }

  async function loadConfig() {
    showBusy('Loading configuration...');
    try {
      const response = await fetch(endpoint, {
        headers: { 'Accept': 'application/json' }
      });
      
      if (!response.ok) throw new Error('Failed to load configuration');
      
      const data = await response.json();
      
      // Apply motion settings
      if (data.motion) {
        if (motionEnabledInput) motionEnabledInput.checked = data.motion.enabled === true || data.motion.enabled === 'true';
        if (motionSensitivityInput) {
          motionSensitivityInput.value = data.motion.sensitivity || 4;
          if (motionSensitivityValue) motionSensitivityValue.textContent = motionSensitivityInput.value;
        }
        if (motionCooldownInput) {
          motionCooldownInput.value = data.motion.cooldown_time || 15;
          if (motionCooldownValue) motionCooldownValue.textContent = motionCooldownInput.value;
        }
        
        // Update motion service checkboxes
        const services = ['email', 'ftp', 'telegram', 'mqtt', 'webhook', 'storage', 'ntfy', 'gphotos'];
        services.forEach(service => {
          const checkbox = $(`#motion_send2${service}`);
          if (checkbox) {
            checkbox.checked = data.motion[`send2${service}`] === true || data.motion[`send2${service}`] === 'true';
          }
        });
      }

      // Update service status badges (photo/video support)
      const services = ['email', 'ftp', 'telegram', 'mqtt', 'webhook', 'storage', 'ntfy', 'gphotos'];
      services.forEach(service => {
        const serviceData = data[service];
        const photoStatus = $(`#status-${service}-photo`);
        const videoStatus = $(`#status-${service}-video`);
        
        if (photoStatus && serviceData) {
          const sendPhoto = serviceData.send_photo !== false && serviceData.send_photo !== 'false';
          photoStatus.textContent = sendPhoto ? '✓' : '✗';
          photoStatus.className = sendPhoto ? 'badge bg-success' : 'badge bg-secondary';
        }
        
        if (videoStatus && serviceData) {
          const sendVideo = serviceData.send_video === true || serviceData.send_video === 'true';
          videoStatus.textContent = sendVideo ? '✓' : '✗';
          videoStatus.className = sendVideo ? 'badge bg-success' : 'badge bg-secondary';
        }
      });

    } catch (err) {
      console.error('Failed to load config:', err);
      showAlert('danger', `Failed to load configuration: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  async function saveMotionSettings() {
    if (!saveMotionButton) return;
    
    showBusy('Saving motion settings...');
    saveMotionButton.disabled = true;
    
    try {
      const payload = {
        motion: {
          enabled: motionEnabledInput ? motionEnabledInput.checked : false,
          sensitivity: motionSensitivityInput ? Number(motionSensitivityInput.value) : 4,
          cooldown_time: motionCooldownInput ? Number(motionCooldownInput.value) : 15
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

      showAlert('success', 'Motion settings saved successfully.', 3000);
      
    } catch (err) {
      console.error('Failed to save motion settings:', err);
      showAlert('danger', `Failed to save settings: ${err.message || err}`);
    } finally {
      hideBusy();
      saveMotionButton.disabled = false;
    }
  }

  // Handle motion service toggles
  $$('.motion-sendto').forEach(checkbox => {
    checkbox.addEventListener('change', (ev) => {
      const service = ev.target.dataset.service;
      const value = ev.target.checked;
      updateMotionValue(service, value);
    });
  });

  // Handle test buttons
  const testModalEl = $('#send2-test-modal');
  const testModal = testModalEl ? new bootstrap.Modal(testModalEl) : null;
  const testOutput = $('#send2-test-output');
  const testTitle = $('#send2-test-title');
  const testVerbose = $('#send2-test-verbose');

  const renderTestResult = data => {
    if (!testOutput) return;
    let text = '';
    const stripAnsi = s => typeof s === 'string' ? s.replace(/\u001b\[[0-9;]*[A-Za-z]/g, '') : s;
    
    if (!data) {
      text = 'No response received.';
    } else if (data.error) {
      const err = data.error.message || data.error.code || data.error;
      text = `Error: ${err}`;
    } else if (data.message && typeof data.message === 'object') {
      const msg = data.message;
      if (msg.output_b64) {
        try {
          text = stripAnsi(decodeBase64String(msg.output_b64));
        } catch (e) {
          text = `Failed to decode output: ${e}`;
        }
      } else {
        text = stripAnsi(msg.output || JSON.stringify(msg, null, 2));
      }
      if (msg.status && msg.status !== 'success') {
        text = `[${msg.status}] ${text}`;
      }
    } else if (typeof data.message === 'string') {
      text = stripAnsi(data.message);
    } else {
      text = stripAnsi(JSON.stringify(data, null, 2));
    }
    
    testOutput.textContent = text || '(no output)';
  };

  $$('button[data-sendto]').forEach(btn => {
    btn.addEventListener('click', ev => {
      ev.preventDefault();
      const target = btn.dataset.sendto;
      if (!target) return;
      
      if (testTitle) testTitle.textContent = `Test: ${target}`;
      if (testOutput) testOutput.textContent = 'Running...';
      if (testModal) testModal.show();
      
      btn.disabled = true;
      
      const params = new URLSearchParams({ to: target });
      if (!testVerbose || testVerbose.checked) {
        params.set('verbose', '1');
      }
      
      fetch(`/x/send.cgi?${params.toString()}`)
        .then(res => res.json())
        .then(renderTestResult)
        .catch(err => {
          if (testOutput) testOutput.textContent = `Request failed: ${err}`;
        })
        .finally(() => {
          btn.disabled = false;
        });
    });
  });

  if (saveMotionButton) {
    saveMotionButton.addEventListener('click', saveMotionSettings);
  }

  loadConfig();
})();
