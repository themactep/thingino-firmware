(function() {
  'use strict';

  const endpoint = '/x/json-prudynt.cgi';
  const dayNightParams = ['enabled', 'total_gain_night_threshold', 'total_gain_day_threshold'];
  const dayNightScheduleParams = ['enabled', 'start_at', 'stop_at'];
  const dayNightControls = ['color', 'ircut', 'ir850', 'ir940', 'white'];

  const alertArea = $('#photosensing-alerts');
  const contentWrap = $('#photosensing-content');
  const reloadButton = $('#photosensing-reload');
  const form = $('#photosensing-form');
  let initialLoadComplete = false;

  function showAlert(variant, message, timeout = 6000) {
    if (!message) return;

    // Use global alert system from main.js
    if (window.showAlert && typeof window.showAlert === 'function') {
      window.showAlert(variant, message, timeout);
      return;
    }

    // Fallback to local alert container if it exists
    if (!alertArea) return;
    const alert = document.createElement('div');
    alert.className = `alert alert-${variant || 'secondary'} alert-dismissible fade show`;
    alert.setAttribute('role', 'alert');
    alert.textContent = message;
    const dismissBtn = document.createElement('button');
    dismissBtn.type = 'button';
    dismissBtn.className = 'btn-close';
    dismissBtn.setAttribute('aria-label', 'Close');
    dismissBtn.addEventListener('click', () => alert.remove());
    alert.appendChild(dismissBtn);
    alertArea.appendChild(alert);
    if (timeout > 0) {
      setTimeout(() => {
        alert.classList.remove('show');
        setTimeout(() => alert.remove(), 200);
      }, timeout);
    }
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle('disabled', !!state);
  }

  function disablePhotosensingInputs() {
    dayNightParams.forEach(param => {
      const el = $('#daynight_' + param);
      if (el) el.disabled = true;
      const slider = $('#daynight_' + param + '-slider');
      if (slider) slider.disabled = true;
    });
    dayNightControls.forEach(control => {
      const el = $('#daynight_controls_' + control);
      if (el) el.disabled = true;
    });
    dayNightScheduleParams.forEach(param => {
      const el = $('#daynight_schedule_' + param);
      if (el) el.disabled = true;
    });
  }

  async function requestPrudynt(payload) {
    const body = typeof payload === 'string' ? payload : JSON.stringify(payload);
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (err) {
      throw new Error('Invalid JSON from prudynt');
    }
  }

  function buildReadPayload() {
    const controls = {};
    dayNightControls.forEach(control => {
      controls[control] = null;
    });
    const schedule = {};
    dayNightScheduleParams.forEach(param => {
      schedule[param] = null;
    });
    const daynight = { controls, schedule };
    dayNightParams.forEach(param => {
      daynight[param] = null;
    });
    return { daynight };
  }

  let updatingFromBackend = false;

  function applyDaynightConfig(daynight = {}) {
    updatingFromBackend = true;
    try {
      dayNightParams.forEach(param => {
        if (Object.prototype.hasOwnProperty.call(daynight, param)) {
          setValue(daynight, 'daynight', param);
        }
      });
      if (daynight.controls) {
        dayNightControls.forEach(control => {
          const el = $('#daynight_controls_' + control);
          if (!el || !Object.prototype.hasOwnProperty.call(daynight.controls, control)) return;
          el.checked = !!daynight.controls[control];
          el.disabled = false;
          const wrapper = el.closest('.boolean');
          if (wrapper) wrapper.classList.remove('disabled');
        });
      }
      if (daynight.schedule) {
        dayNightScheduleParams.forEach(param => {
          const el = $('#daynight_schedule_' + param);
          if (!el || !Object.prototype.hasOwnProperty.call(daynight.schedule, param)) return;
          if (el.type === 'checkbox') {
            el.checked = !!daynight.schedule[param];
          } else {
            el.value = daynight.schedule[param] || '';
          }
          el.disabled = false;
        });
      }
    } finally {
      updatingFromBackend = false;
    }
  }

  async function loadPhotosensingConfig(options = {}) {
    const { silent = false } = options;
    let success = false;
    if (!silent) {
      showBusy('Loading photosensing settings...');
      disablePhotosensingInputs();
    } else {
      setReloadBusy(true);
    }
    try {
      const data = await requestPrudynt(buildReadPayload());
      if (!data || !data.daynight) {
        throw new Error('Missing daynight payload');
      }
      applyDaynightConfig(data.daynight);
      if (!initialLoadComplete) {
        if (contentWrap) contentWrap.classList.remove('d-none');
        if (typeof window.attachSliderButtons === 'function') {
          window.attachSliderButtons();
        }
        initialLoadComplete = true;
      }
      success = true;
      return true;
    } catch (err) {
      console.error('Failed to load photosensing settings', err);
      showAlert('danger', `Unable to load photosensing settings: ${err.message || err}`);
      return false;
    } finally {
      if (!silent) {
        hideBusy();
      } else {
        setReloadBusy(false);
        if (success) showAlert('info', 'Photosensing settings reloaded.', 3000);
      }
    }
  }

  async function sendDaynightUpdate(payload) {
    try {
      const data = await requestPrudynt(payload);
      if (data && data.daynight) {
        applyDaynightConfig(data.daynight);
      }
    } catch (err) {
      console.error('Failed to update daynight setting', err);
      throw err;
    }
  }

  async function saveDaynightParam(param) {
    const el = $('#daynight_' + param);
    if (!el) return;
    let value;
    if (el.type === 'checkbox') {
      value = el.checked;
    } else {
      const numeric = Number(el.value);
      value = Number.isNaN(numeric) ? 0 : numeric;
    }
    const payload = { daynight: { [param]: value } };
    try {
      await sendDaynightUpdate(payload);
    } catch (err) {
      showAlert('danger', `Failed to update ${param.replace(/_/g, ' ')}: ${err.message || err}`);
    }
  }

  async function saveDaynightControl(control) {
    const el = $('#daynight_controls_' + control);
    if (!el) return;
    const value = el.checked;
    const payload = { daynight: { controls: { [control]: value } } };
    try {
      await sendDaynightUpdate(payload);
    } catch (err) {
      showAlert('danger', `Failed to update ${control}: ${err.message || err}`);
    }
  }

  async function saveDaynightScheduleParam(param) {
    const el = $('#daynight_schedule_' + param);
    if (!el) return;
    let value;
    if (el.type === 'checkbox') {
      value = el.checked;
    } else {
      value = el.value || '';
    }
    const payload = { daynight: { schedule: { [param]: value } } };
    try {
      await sendDaynightUpdate(payload);
    } catch (err) {
      showAlert('danger', `Failed to update schedule ${param.replace(/_/g, ' ')}: ${err.message || err}`);
    }
  }

  function bindDaynightControls() {
    // Handle modal slider UI updates (but don't save)
    dayNightParams.forEach(param => {
      const el = $('#daynight_' + param);
      const slider = $('#daynight_' + param + '-slider');
      if (slider) {
        slider.addEventListener('input', ev => {
          // Update the text input while dragging
          if (el) el.value = ev.target.value;
          const sliderValue = $('#daynight_' + param + '-slider-value');
          if (sliderValue) sliderValue.textContent = ev.target.value;
        });
      }
    });
  }

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        const success = await loadPhotosensingConfig({ silent: true });
        if (success) {
          showAlert('info', 'Photosensing settings reloaded from camera.', 3000);
        }
      } catch (err) {
        showAlert('danger', 'Failed to reload photosensing settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  // Intercept save button to save directly to config file using jct
  const saveButton = $('#save-prudynt-config');
  if (saveButton) {
    // Use capture phase to run BEFORE streamer-config.js handler
    saveButton.addEventListener('click', async (e) => {
      // Stop the default handler from streamer-config.js
      e.stopImmediatePropagation();
      e.preventDefault();

      saveButton.disabled = true;

      try {
        const daynight = {};

        // Collect all daynight parameters (enabled, thresholds)
        dayNightParams.forEach(param => {
          const el = $('#daynight_' + param);
          if (el) {
            if (el.type === 'checkbox') {
              daynight[param] = el.checked;
            } else {
              const numeric = Number(el.value);
              daynight[param] = Number.isNaN(numeric) ? 0 : numeric;
            }
          }
        });

        // Collect schedule values
        const schedule = {};
        dayNightScheduleParams.forEach(param => {
          const el = $('#daynight_schedule_' + param);
          if (el) {
            if (el.type === 'checkbox') {
              schedule[param] = el.checked;
            } else {
              schedule[param] = el.value || '';
            }
          }
        });

        // Collect controls values
        const controls = {};
        dayNightControls.forEach(control => {
          const el = $('#daynight_controls_' + control);
          if (el) {
            controls[control] = el.checked;
          }
        });

        // Build payload - just the config changes, no action needed
        daynight.schedule = schedule;
        daynight.controls = controls;
        const payload = { daynight };

        // Save directly to config file using jct
        const response = await fetch('/x/json-prudynt-save.cgi', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify(payload)
        });

        if (!response.ok) {
          throw new Error(`HTTP ${response.status}`);
        }

        const data = await response.json();
        if (data.error) {
          throw new Error(data.error);
        }

        showAlert('success', data.message || 'Configuration saved successfully to /etc/prudynt.json', 3000);
      } catch (err) {
        console.error('Failed to save prudynt config:', err);
        showAlert('danger', `Failed to save configuration: ${err.message || err}`);
      } finally {
        saveButton.disabled = false;
      }
    }, { capture: true });
  }

  disablePhotosensingInputs();
  bindDaynightControls();
  loadPhotosensingConfig();
})();
