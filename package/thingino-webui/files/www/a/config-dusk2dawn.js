(function () {
  'use strict';

  const endpoint = '/x/json-daynight-sun.cgi';
  const sunParams = ['enabled', 'latitude', 'longitude', 'sunrise_offset', 'sunset_offset'];

  const reloadButton = $('#dusk2dawn-reload');
  const saveButton = $('#dusk2dawn-save');

  function disableInputs() {
    sunParams.forEach(param => {
      const el = $('#daynight_sun_' + param);
      if (el) el.disabled = true;
    });
  }

  function applyConfig(sun) {
    sunParams.forEach(param => {
      const el = $('#daynight_sun_' + param);
      if (!el) return;
      if (el.type === 'checkbox') {
        el.checked = !!sun[param];
      } else {
        const isOffset = param.endsWith('_offset');
        const val = sun[param];
        el.value = (val != null && val !== '') ? val : (isOffset ? '0' : '');
      }
      el.disabled = false;
    });
  }

  async function loadConfig() {
    try {
      showBusy('Loading Dusk2Dawn settings...');
      disableInputs();
      const response = await fetch(endpoint, { method: 'GET' });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      applyConfig(data.sun || {});
    } catch (err) {
      console.error('Failed to load Dusk2Dawn settings', err);
      showAlert('danger', `Unable to load settings: ${err.message || err}`);
    } finally {
      hideBusy();
    }
  }

  async function saveConfig() {
    const sun = {};
    sunParams.forEach(param => {
      const el = $('#daynight_sun_' + param);
      if (!el) return;
      if (el.type === 'checkbox') {
        sun[param] = el.checked;
      } else {
        const numeric = Number(el.value);
        sun[param] = (param.endsWith('_offset') && !Number.isNaN(numeric)) ? numeric : (el.value || '');
      }
    });

    saveButton.disabled = true;
    try {
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ sun })
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (data.error) throw new Error(data.error);
      showAlert('success', 'Dusk2Dawn settings saved.', 3000);
    } catch (err) {
      console.error('Failed to save Dusk2Dawn settings', err);
      showAlert('danger', `Failed to save: ${err.message || err}`);
    } finally {
      saveButton.disabled = false;
    }
  }

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      reloadButton.disabled = true;
      await loadConfig();
      reloadButton.disabled = false;
      showAlert('info', 'Settings reloaded.', 3000);
    });
  }

  if (saveButton) {
    saveButton.addEventListener('click', saveConfig);
  }

  const geoBtn = $('#geolocate-btn');
  if (geoBtn) {
    const setBusy = () => {
      geoBtn.disabled = true;
      geoBtn.innerHTML = '<i class="bi bi-hourglass-split"></i> Locating…';
    };
    const setDone = () => {
      geoBtn.disabled = false;
      geoBtn.innerHTML = '<i class="bi bi-geo-alt-fill"></i> Location set';
    };
    const setReady = () => {
      geoBtn.disabled = false;
      geoBtn.innerHTML = '<i class="bi bi-geo-alt"></i> Use my location';
    };
    const applyCoords = (lat, lng, note) => {
      const latEl = $('#daynight_sun_latitude');
      const lngEl = $('#daynight_sun_longitude');
      if (latEl) latEl.value = parseFloat(lat).toFixed(6);
      if (lngEl) lngEl.value = parseFloat(lng).toFixed(6);
      setDone();
      if (note) showAlert('info', note, 5000);
    };
    const tryIPGeo = async () => {
      try {
        const res = await fetch('https://ipapi.co/json/');
        if (!res.ok) throw new Error('ipapi error');
        const data = await res.json();
        if (!data.latitude || !data.longitude) throw new Error('no coordinates');
        applyCoords(data.latitude, data.longitude, 'Location set from IP address (city-level accuracy). Adjust if needed.');
      } catch (e) {
        setReady();
        showAlert('warning', 'Could not determine location automatically. Use the "Find manually" link.');
      }
    };
    geoBtn.addEventListener('click', () => {
      setBusy();
      if (navigator.geolocation) {
        navigator.geolocation.getCurrentPosition(
          pos => applyCoords(pos.coords.latitude, pos.coords.longitude),
          () => tryIPGeo(),
          { timeout: 8000 }
        );
      } else {
        tryIPGeo();
      }
    });
  }

  loadConfig();
})();
