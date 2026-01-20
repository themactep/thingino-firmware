(function() {
  'use strict';

  const endpoint = '/x/json-prudynt.cgi';
  const dayNightParams = ['enabled', 'total_gain_night_threshold', 'total_gain_day_threshold'];
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
    const daynight = { controls };
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

  async function saveAllChanges() {
    showBusy('Saving photosensing settings...');
    try {
      const controls = {};
      dayNightControls.forEach(control => {
        const el = $('#daynight_controls_' + control);
        if (el) {
          controls[control] = el.checked;
        }
      });

      const daynight = { controls };
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

      const payload = { daynight };
      const data = await requestPrudynt(payload);
      
      if (data && data.daynight) {
        applyDaynightConfig(data.daynight);
      }
      
      showAlert('success', 'Photosensing settings saved successfully.', 3000);
    } catch (err) {
      console.error('Failed to save photosensing settings', err);
      showAlert('danger', `Failed to save settings: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  function bindDaynightControls() {
    // Remove auto-save event listeners, controls are now saved on form submit
  }

  if (form) {
    form.addEventListener('submit', ev => {
      ev.preventDefault();
      saveAllChanges();
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

  disablePhotosensingInputs();
  bindDaynightControls();
  loadPhotosensingConfig();
})();
