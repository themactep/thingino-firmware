(function() {
  'use strict';

  const motorsConfigEndpoint = '/x/json-motors-config.cgi';
  const alertContainer = $('#motors-alerts');
  const contentWrap = $('#motors-content');
  const form = $('#motors-form');
  const reloadButton = $('#motors-reload');
  const submitButton = form ? form.querySelector('button[type="submit"]') : null;
  const submitSpinner = submitButton ? submitButton.querySelector('.spinner-border') : null;
  const submitLabel = submitButton ? submitButton.querySelector('.label') : null;
  const submitDefaultText = submitLabel ? submitLabel.textContent : 'Save motors';
  const typeBadge = $('#motors-type-badge');
  let initialLoadComplete = false;

  function showAlert(variant, message, timeout = 6000) {
    if (!message) return;

    // Use global alert system from main.js
    if (window.showAlert && typeof window.showAlert === 'function') {
      window.showAlert(variant, message, timeout);
      return;
    }

    // Fallback to local alert container if it exists
    if (!alertContainer) return;
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
    alertContainer.appendChild(alert);
    if (timeout > 0) {
      setTimeout(() => {
        alert.classList.remove('show');
        setTimeout(() => alert.remove(), 200);
      }, timeout);
    }
  }

  function parseMotorPins(raw) {
    if (typeof raw !== 'string') return [];
    return raw.trim().split(/\s+/).filter(Boolean);
  }

  function setMotorPins(prefix, pins) {
    if (!Array.isArray(pins)) return;
    for (let i = 1; i <= 4; i += 1) {
      const input = $(`#gpio_${prefix}_${i}`);
      if (input) input.value = pins[i - 1] || '';
    }
  }

  function setMotorFieldValue(id, value) {
    const input = $(`#${id}`);
    if (!input) return;
    input.value = value === undefined || value === null ? '' : value;
  }

  function setMotorPinInputsEnabled(enabled) {
    const disablePins = !enabled;
    $$('#motors-form input[id^="gpio_"]').forEach(input => {
      input.disabled = disablePins;
    });
    $$('.flip_motor').forEach(btn => {
      btn.disabled = disablePins;
      btn.classList.toggle('disabled', disablePins);
    });
  }

  function updateBadge(isSpi) {
    if (!typeBadge) return;
    if (isSpi) {
      typeBadge.textContent = 'SPI motor board';
      typeBadge.className = 'badge text-bg-info';
      typeBadge.title = 'Pins are controlled over SPI, GPIO inputs disabled';
    } else {
      typeBadge.textContent = 'Discrete GPIO driver';
      typeBadge.className = 'badge text-bg-dark';
      typeBadge.title = 'Pins driven directly via GPIO';
    }
  }

  function updateHomingInputs() {
    const homing = $('#homing');
    const x = $('#pos_0_x');
    const y = $('#pos_0_y');
    if (!homing) return;
    const disabled = !homing.checked;
    if (x) x.disabled = disabled;
    if (y) y.disabled = disabled;
  }

  function applyMotorsConfig(config = {}) {
    if (typeof config !== 'object' || !config) return;
    setMotorPins('pan', parseMotorPins(config.gpio_pan));
    setMotorPins('tilt', parseMotorPins(config.gpio_tilt));
    setMotorFieldValue('steps_pan', config.steps_pan);
    setMotorFieldValue('steps_tilt', config.steps_tilt);
    setMotorFieldValue('speed_pan', config.speed_pan);
    setMotorFieldValue('speed_tilt', config.speed_tilt);
    const homingEl = $('#homing');
    if (homingEl) {
      homingEl.checked = config.homing === true || config.homing === 'true';
    }
    const posParts = typeof config.pos_0 === 'string' ? config.pos_0.split(/\s*,\s*/) : [];
    setMotorFieldValue('pos_0_x', posParts[0] || '');
    setMotorFieldValue('pos_0_y', posParts[1] || '');
    updateHomingInputs();
    const isSpi = config.is_spi === true || config.is_spi === 'true';
    setMotorPinInputsEnabled(!isSpi);
    updateBadge(isSpi);
  }

  async function loadMotorsConfig(options = {}) {
    const { silent = false } = options;
    if (!silent) showBusy('Loading motor settings...');
    try {
      const response = await fetch(motorsConfigEndpoint, {
        headers: { 'Accept': 'application/json' },
        cache: 'no-store'
      });
      let payload = null;
      try {
        payload = await response.json();
      } catch (parseErr) {
        console.error('JSON parse error:', parseErr);
        payload = null;
      }
      if (!response.ok || !payload || payload.result !== 'success') {
        const message = payload && payload.error && payload.error.message;
        throw new Error(message || `HTTP ${response.status}`);
      }
      try {
        applyMotorsConfig(payload.message || {});
      } catch (applyErr) {
        console.error('applyMotorsConfig error:', applyErr);
        throw applyErr;
      }
      if (!initialLoadComplete) {
        if (contentWrap) contentWrap.classList.remove('d-none');
        initialLoadComplete = true;
      }
      return true;
    } catch (err) {
      console.error('Failed to load motors config', err);
      showAlert('danger', `Unable to load motor settings: ${err.message || err}`);
      return false;
    } finally {
      if (!silent) hideBusy();
    }
  }

  async function saveMotorsConfig() {
    const form = $('#motors-form');
    if (!form) return;

    // Client-side validation to prevent 412 errors
    const requiredFields = [
      'gpio_pan_1', 'gpio_pan_2', 'gpio_pan_3', 'gpio_pan_4',
      'gpio_tilt_1', 'gpio_tilt_2', 'gpio_tilt_3', 'gpio_tilt_4',
      'steps_pan', 'steps_tilt'
    ];

    const formData = new FormData(form);
    const errors = [];

    // Check GPIO fields
    for (let i = 0; i < 8; i++) {
      const field = requiredFields[i];
      const value = formData.get(field);
      if (!value || value.trim() === '') {
        errors.push(`${field.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase())} is required`);
      }
    }

    // Check steps fields
    const stepsPan = formData.get('steps_pan');
    const stepsTilt = formData.get('steps_tilt');
    if (!stepsPan || parseInt(stepsPan) <= 0) {
      errors.push('Pan max steps must be a positive number');
    }
    if (!stepsTilt || parseInt(stepsTilt) <= 0) {
      errors.push('Tilt max steps must be a positive number');
    }

    if (errors.length > 0) {
      showAlert('danger', 'Please fix the following errors:<br>' + errors.join('<br>'));
      return;
    }

    showBusy('Saving motor settings...');
    try {
      const homingEl = $('#homing');
      const params = new URLSearchParams();
      params.append('form', 'motors');
      params.append('homing', homingEl && homingEl.checked ? 'true' : 'false');
      formData.forEach((value, key) => {
        if (key !== 'form' && key !== 'homing') {
          params.append(key, value == null ? '' : value);
        }
      });
      const response = await fetch(motorsConfigEndpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString(),
        cache: 'no-store'
      });
      let payload = null;
      try {
        payload = await response.json();
      } catch (_) {
        payload = null;
      }
      if (!response.ok || !payload || payload.result !== 'success') {
        const message = payload && payload.error && payload.error.message;
        throw new Error(message || `HTTP ${response.status}`);
      }
      applyMotorsConfig(payload.message || {});
      showAlert('success', 'Motor settings updated.');
    } catch (err) {
      console.error('Failed to save motors config', err);
      showAlert('danger', `Failed to save motor settings: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  async function readMotorsPosition() {
    try {
      const res = await fetch('/x/json-motor.cgi?' + new URLSearchParams({ d: 'j' }).toString());
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { message } = await res.json();
      if (message) {
        if ($('#pos_0_x')) $('#pos_0_x').value = message.xpos;
        if ($('#pos_0_y')) $('#pos_0_y').value = message.ypos;
      }
      if ($('#homing')) $('#homing').checked = true;
      updateHomingInputs();
      showAlert('success', 'Captured current position as new reference.', 4000);
    } catch (err) {
      console.error('Failed to read motors position', err);
      showAlert('danger', `Unable to read current position: ${err.message || err}`);
    }
  }

  if (form) {
    form.addEventListener('submit', ev => {
      ev.preventDefault();
      saveMotorsConfig();
    });
  }

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        const success = await loadMotorsConfig({ silent: true });
        if (success) {
          showAlert('info', 'Motor settings reloaded from camera.', 3000);
        }
      } catch (err) {
        showAlert('danger', 'Failed to reload motors settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  $$('.flip_motor').forEach(el => {
    el.addEventListener('click', ev => {
      ev.preventDefault();
      const dir = el.dataset.direction;
      if (!dir) return;
      const base = '#gpio_' + dir + '_';
      const pins = [1, 2, 3, 4].map(i => $(base + i)?.value).reverse();
      [1, 2, 3, 4].forEach((i, idx) => {
        const field = $(base + i);
        if (field && pins[idx] !== undefined) field.value = pins[idx];
      });
    });
  });

  $$('.read-motors').forEach(el => {
    el.addEventListener('click', ev => {
      ev.preventDefault();
      readMotorsPosition();
    });
  });

  const homingSwitch = $('#homing');
  if (homingSwitch) {
    homingSwitch.addEventListener('change', updateHomingInputs);
    updateHomingInputs();
  }

  loadMotorsConfig();
})();
