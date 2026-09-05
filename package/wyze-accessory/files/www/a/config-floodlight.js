(function () {
  const slider = $('#floodlight-brightness');
  const value = $('#floodlight-brightness-value');
  const status = $('#floodlight-status');
  const unavailable = $('#floodlight-unavailable');
  const buttons = [$('#floodlight-on'), $('#floodlight-off'), $('#floodlight-set')];
  const motionEnabled = $('#floodlight-motion-enabled');
  const motionDuration = $('#floodlight-motion-duration');
  const motionSave = $('#floodlight-motion-save');

  function setControls(enabled) {
    slider.disabled = !enabled;
    buttons.forEach(function (button) { button.disabled = !enabled; });
    unavailable.classList.toggle('d-none', enabled);
  }

  function showStatus(data) {
    const isOn = data.state === 'ON';
    status.textContent = isOn ? 'On' : 'Off';
    status.className = 'badge ' + (isOn ? 'text-bg-warning' : 'text-bg-secondary');
    if (Number.isInteger(data.brightness) && data.brightness >= 1 && data.brightness <= 100) {
      slider.value = String(data.brightness);
      value.textContent = data.brightness + '%';
    }
    if (typeof data.motion_enabled === 'boolean') {
      motionEnabled.checked = data.motion_enabled;
    }
    if (Number.isInteger(data.motion_duration) && data.motion_duration >= 1 && data.motion_duration <= 3600) {
      motionDuration.value = String(data.motion_duration);
    }
    setControls(data.available === true);
  }

  async function refresh() {
    try {
      const response = await fetch('/x/json-config-floodlight.cgi', { headers: { Accept: 'application/json' } });
      if (!response.ok) throw new Error('Unable to read floodlight status');
      showStatus(await response.json());
    } catch (err) {
      status.textContent = 'Unavailable';
      status.className = 'badge text-bg-danger';
      setControls(false);
    }
  }

  async function command(action) {
    const payload = { action: action, brightness: Number(slider.value) };
    setControls(false);
    try {
      const response = await fetch('/x/json-config-floodlight.cgi', {
        method: 'POST', headers: { 'Content-Type': 'application/json' }, body: JSON.stringify(payload)
      });
      const data = await response.json();
      if (!response.ok || data.error) throw new Error(data.error && data.error.message || 'Floodlight command failed');
      showStatus(data);
    } catch (err) {
      if (window.showAlert) showAlert('danger', err.message);
      await refresh();
    }
  }

  async function saveMotionSettings() {
    const duration = Number(motionDuration.value);
    if (!Number.isInteger(duration) || duration < 1 || duration > 3600) {
      if (window.showAlert) showAlert('danger', 'Motion on time must be between 1 and 3600 seconds.');
      return;
    }
    motionSave.disabled = true;
    try {
      const response = await fetch('/x/json-config-floodlight.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({
          action: 'motion-settings',
          motion_enabled: motionEnabled.checked,
          motion_duration: duration
        })
      });
      const data = await response.json();
      if (!response.ok || data.error) throw new Error(data.error && data.error.message || 'Could not save motion settings');
      showStatus(data);
      if (window.showAlert) showAlert('success', 'Motion settings saved.');
    } catch (err) {
      if (window.showAlert) showAlert('danger', err.message);
    } finally {
      motionSave.disabled = false;
    }
  }

  slider.addEventListener('input', function () { value.textContent = slider.value + '%'; });
  $('#floodlight-on').addEventListener('click', function () { command('on'); });
  $('#floodlight-off').addEventListener('click', function () { command('off'); });
  $('#floodlight-set').addEventListener('click', function () { command('on'); });
  motionSave.addEventListener('click', saveMotionSettings);
  refresh();
  window.setInterval(refresh, 5000);
})();
