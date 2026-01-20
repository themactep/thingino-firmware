(function() {
  const form = $('#gpioForm');
  const container = $('#gpio-container');
  const submitButton = $('#gpio_submit');  let gpioData = {};
  let pwmPins = [];

  const gpioConfigs = [
    { name: 'led_r', label: 'Red LED' },
    { name: 'led_g', label: 'Green LED' },
    { name: 'led_b', label: 'Blue LED' },
    { name: 'led_y', label: 'Yellow LED' },
    { name: 'led_o', label: 'Orange LED' },
    { name: 'led_w', label: 'White LED' },
    { name: 'ir850', label: '850 nm IR LED' },
    { name: 'ir940', label: '940 nm IR LED' },
    { name: 'white', label: 'White LED' }
  ];

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    container.querySelectorAll('input, button.led-status').forEach(el => el.disabled = state);
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function isPWMPin(pin) {
    return pwmPins.includes(parseInt(pin));
  }

  function createGPIOCard(config) {
    const { name, label } = config;
    const pinData = gpioData[name];

    if (!pinData) return null;

    let pin, isActiveLow, activeOnBoot, pwmCh, pwmLvl;

    if (typeof pinData === 'object' && pinData.pin !== undefined) {
      pin = pinData.pin;
      isActiveLow = pinData.active_low === true || pinData.active_low === 'true';
      activeOnBoot = pinData.active_on_boot === true || pinData.active_on_boot === 'true';
      pwmCh = pinData.pwm_channel || '';
      pwmLvl = pinData.pwm_level || '';
    } else {
      let pinValue = String(pinData);
      let activeSuffix = 'O';

      if (!/^\d+$/.test(pinValue)) {
        activeSuffix = pinValue.slice(-1);
        pin = pinValue.slice(0, -1);
      } else {
        pin = pinValue;
      }

      isActiveLow = activeSuffix === 'o';
      activeOnBoot = false;
      pwmCh = '';
      pwmLvl = '';
    }

    const card = document.createElement('div');
    card.className = 'col';
    card.innerHTML = `
<div class="card h-100 gpio ${name}">
  <div class="card-header">${label}
    <div class="switch float-end">
      <button class="btn btn-sm btn-outline-secondary m-0 led-status" type="button" id="${name}_toggle">Test</button>
    </div>
  </div>
  <div class="card-body">
    <div class="row">
      <label class="col-9" for="${name}_pin">GPIO pin #</label>
      <div class="col">
        <input type="text" class="form-control text-end" id="${name}_pin" name="${name}_pin" pattern="[0-9]{1,3}" title="a number" value="${pin}" required>
      </div>
    </div>
${isPWMPin(pin) ? `
    <div class="row">
      <label class="col-9" for="${name}_ch">GPIO PWM channel</label>
      <div class="col">
        <input type="text" class="form-control text-end" id="${name}_ch" name="${name}_ch" pattern="[0-9]{1,3}" title="empty or a number" value="${pwmCh}" readonly>
      </div>
    </div>
    <div class="row">
      <label class="col-9" for="${name}_lvl">GPIO PWM level</label>
      <div class="col">
        <input type="text" class="form-control text-end" id="${name}_lvl" name="${name}_lvl" pattern="[0-9]{1,3}" title="empty or a number" value="${pwmLvl}">
      </div>
    </div>
` : '<div class="text-warning">NOT A PWM PIN</div>'}
    <div class="row">
      <label class="col-9" for="${name}_inv">Active low</label>
      <div class="col">
        <input class="form-check-input" type="checkbox" id="${name}_inv" name="${name}_inv" value="true"${isActiveLow ? ' checked' : ''}>
      </div>
    </div>
    <div class="row mb-0">
      <label class="col-9" for="${name}_lit">Active on boot</label>
      <div class="col">
        <input class="form-check-input" type="checkbox" id="${name}_lit" name="${name}_lit" value="true"${activeOnBoot ? ' checked' : ''}>
      </div>
    </div>
  </div>
</div>
`;

    return card;
  }

  function createIRCutCard() {
    const ircut = gpioData.ircut || [];
    const pin1 = Array.isArray(ircut) ? ircut[0] : (ircut.split ? ircut.split(' ')[0] : '');
    const pin2 = Array.isArray(ircut) ? ircut[1] : (ircut.split ? ircut.split(' ')[1] : '');

    const card = document.createElement('div');
    card.className = 'col';
    card.innerHTML = `
<div class="card h-100">
  <div class="card-header">IR cut filter
    <div class="switch float-end">
      <button type="button" class="btn btn-sm btn-outline-secondary m-0" data-bs-toggle="modal" data-bs-target="#helpModal" alt="Help">
        <i class="bi bi-info-circle"></i>
      </button>
    </div>
  </div>
  <div class="card-body">
    <div class="row mb-2">
      <label class="col-9" for="ircut_pin1">GPIO pin 1 #</label>
      <div class="col">
        <input type="text" class="form-control text-end" id="ircut_pin1" name="ircut_pin1" pattern="[0-9]{1,3}" value="${pin1 || ''}">
      </div>
    </div>
    <div class="row mb-2">
      <label class="col-9" for="ircut_pin2">GPIO pin 2 #</label>
      <div class="col">
        <input type="text" class="form-control text-end" id="ircut_pin2" name="ircut_pin2" pattern="[0-9]{1,3}" value="${pin2 || ''}">
      </div>
    </div>
  </div>
</div>
`;

    return card;
  }

  function setupTestButtons() {
    gpioConfigs.forEach(({ name }) => {
      const toggle = $('#' + name + '_toggle');
      if (toggle) {
        toggle.addEventListener('click', () => {
          fetch('/x/json-gpio.cgi', {
            method: 'POST',
            headers: {
              'Content-Type': 'application/x-www-form-urlencoded',
            },
            body: new URLSearchParams({ 'n': name, 's': '~' }).toString()
          })
            .then(res => res.json())
            .then(data => {
              if (data.error) {
                console.error('GPIO toggle error:', data.error.message);
              } else {
                console.log('GPIO toggled:', data.message);
              }
            })
            .catch(err => console.error('Failed to toggle GPIO:', err));
        });
      }
    });
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading GPIO settings...');
    }
    try {
      const response = await fetch('/x/json-config-gpio.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load GPIO configuration');
      const data = await response.json();

      gpioData = data.gpio || {};
      pwmPins = (data.pwm_pins || '').split(',').map(p => parseInt(p)).filter(p => !isNaN(p));

      container.innerHTML = '';
      gpioConfigs.forEach(config => {
        const card = createGPIOCard(config);
        if (card) container.appendChild(card);
      });
      container.appendChild(createIRCutCard());

      setupTestButtons();
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load GPIO configuration.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving GPIO settings...');
    try {
      const response = await fetch('/x/json-config-gpio.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message = result && result.error && result.error.message ? result.error.message : 'Failed to save settings';
        throw new Error(message);
      }
      showAlert('', '');
      showOverlayMessage(result.message || 'GPIO configuration saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save GPIO configuration.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();

    const payload = {};
    gpioConfigs.forEach(({ name }) => {
      const pinEl = $(`#${name}_pin`);
      if (pinEl && pinEl.value) {
        payload[name] = {
          pin: pinEl.value.trim(),
          inv: $(`#${name}_inv`)?.checked || false,
          lit: $(`#${name}_lit`)?.checked || false
        };
        const chEl = $(`#${name}_ch`);
        const lvlEl = $(`#${name}_lvl`);
        if (chEl && chEl.value) payload[name].ch = chEl.value.trim();
        if (lvlEl && lvlEl.value) payload[name].lvl = lvlEl.value.trim();
      }
    });

    const ircut_pin1 = $('#ircut_pin1')?.value.trim();
    const ircut_pin2 = $('#ircut_pin2')?.value.trim();
    if (ircut_pin1 && ircut_pin2) {
      payload.ircut_pin1 = ircut_pin1;
      payload.ircut_pin2 = ircut_pin2;
    }

    saveConfig(payload);
  });

  const reloadButton = $('#gpio-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'GPIO settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload GPIO settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
