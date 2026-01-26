(function() {
  'use strict';

  const endpoint = '/x/json-prudynt.cgi';
  const audioParams = [
    'mic_enabled', 'mic_format', 'mic_sample_rate', 'mic_bitrate',
    'mic_vol', 'mic_gain', 'mic_alc_gain', 'mic_agc_enabled',
    'mic_high_pass_filter', 'mic_noise_suppression',
    'mic_agc_compression_gain_db', 'mic_agc_target_level_dbfs',
    'spk_enabled', 'spk_vol', 'spk_gain', 'spk_sample_rate', 'force_stereo'
  ];

  const alertArea = $('#audio-alerts');
  const reloadButton = $('#audio-reload');
  const form = $('#audio-form');

  function parseNumber(value) {
    if (value === undefined) return null;
    const num = Number(value);
    return Number.isFinite(num) ? num : null;
  }

  function buildRangeValues(select) {
    const min = parseNumber(select?.dataset?.rangeMin);
    const max = parseNumber(select?.dataset?.rangeMax);
    if (min === null || max === null) return null;
    const stepRaw = parseNumber(select.dataset.rangeStep);
    const step = stepRaw && stepRaw > 0 ? stepRaw : 1;
    const values = [];
    for (let val = min; val <= max; val += step) {
      values.push(val);
    }
    return values;
  }

  function buildListValues(select) {
    const raw = select?.dataset?.optionValues;
    if (!raw) return null;
    return raw.split(',').map(item => item.trim()).filter(Boolean);
  }

  function preparePlaceholder(select) {
    const placeholder = select.querySelector('option[value=""]');
    select.innerHTML = '';
    if (placeholder) {
      placeholder.textContent = placeholder.textContent || '- Select -';
      select.appendChild(placeholder);
    } else {
      const opt = document.createElement('option');
      opt.value = '';
      opt.textContent = '- Select -';
      select.appendChild(opt);
    }
  }

  function populateDynamicSelect(select) {
    if (!select || select.dataset.dynamicOptionsReady === '1') return;
    const values = buildRangeValues(select) || buildListValues(select);
    if (!values || !values.length) return;
    preparePlaceholder(select);
    const frag = document.createDocumentFragment();
    values.forEach(item => {
      const option = document.createElement('option');
      option.value = item;
      option.textContent = item;
      frag.appendChild(option);
    });
    select.appendChild(frag);
    select.dataset.dynamicOptionsReady = '1';
  }

  function initDynamicSelects() {
    const dynamicSelects = document.querySelectorAll('select[data-range-min], select[data-option-values]');
    dynamicSelects.forEach(populateDynamicSelect);
  }

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

  function toggleInitialLoading(active) {
    if (!form) return;
    if (active) {
      showBusy('Loading audio settings...');
    } else {
      hideBusy();
    }
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle('disabled', !!state);
  }

  function disableAudioControls() {
    audioParams.forEach(param => {
      const input = $(`#audio_${param}`);
      if (input) input.disabled = true;
      const slider = $(`#audio_${param}-slider`);
      if (slider) slider.disabled = true;
    });
  }

  function applyAudioConfig(audio = {}) {
    audioParams.forEach(param => {
      if (Object.prototype.hasOwnProperty.call(audio, param)) {
        setValue(audio, 'audio', param);
      }
    });
  }

  function buildReadPayload() {
    const audio = {};
    audioParams.forEach(param => {
      audio[param] = null;
    });
    return { audio };
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

  async function loadAudioConfig(options = {}) {
    const { silent = false } = options;
    let success = false;
    if (!silent) {
      disableAudioControls();
      toggleInitialLoading(true);
    } else {
      setReloadBusy(true);
    }
    try {
      const data = await requestPrudynt(buildReadPayload());
      if (!data || !data.audio) {
        throw new Error('Missing audio payload');
      }
      applyAudioConfig(data.audio);
      success = true;
      return true;
    } catch (err) {
      console.error('Failed to load audio config', err);
      showAlert('danger', `Unable to load audio settings: ${err.message || err}`);
      return false;
    } finally {
      if (!silent) {
        toggleInitialLoading(false);
      } else {
        setReloadBusy(false);
        if (success) showAlert('info', 'Audio settings reloaded.', 3000);
      }
    }
  }

  async function sendAudioUpdate(payload) {
    try {
      const data = await requestPrudynt(payload);
      if (data && data.audio) {
        applyAudioConfig(data.audio);
      }
    } catch (err) {
      console.error('Failed to update audio setting', err);
      throw err;
    }
  }

  async function saveAudioValue(param) {
    const el = $(`#audio_${param}`);
    if (!el) return;
    let value;
    if (el.type === 'checkbox') {
      value = el.checked;
    } else {
      value = el.value;
      if (value !== '' && param !== 'mic_format' && !Number.isNaN(Number(value))) {
        value = Number(value);
      }
    }
    const payload = { audio: { [param]: value } };
    if (typeof ThreadAudio !== 'undefined') {
      payload.action = { restart_thread: ThreadAudio };
    }
    try {
      await sendAudioUpdate(payload);
    } catch (err) {
      showAlert('danger', `Failed to update ${param.replace(/_/g, ' ')}: ${err.message || err}`);
    }
  }

  function bindAudioControls() {
    // Bind change events to all audio controls for real-time updates
    audioParams.forEach(param => {
      const el = $(`#audio_${param}`);
      if (el) {
        el.addEventListener('change', () => saveAudioValue(param));
      }

      // Also handle modal slider if it exists
      const slider = $(`#audio_${param}-slider`);
      if (slider) {
        slider.addEventListener('input', ev => {
          // Update the text input while dragging
          if (el) el.value = ev.target.value;
          const sliderValue = $(`#audio_${param}-slider-value`);
          if (sliderValue) sliderValue.textContent = ev.target.value;
        });
        slider.addEventListener('change', () => saveAudioValue(param));
      }
    });
  }

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        const success = await loadAudioConfig({ silent: true });
        if (success) {
          showAlert('info', 'Audio settings reloaded from camera.', 3000);
        }
      } catch (err) {
        showAlert('danger', 'Failed to reload audio settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  initDynamicSelects();
  disableAudioControls();
  bindAudioControls();
  loadAudioConfig();
})();

(function initAudioSliders() {
  const sliderIds = [
    'audio_mic_vol',
    'audio_mic_gain',
    'audio_mic_alc_gain',
    'audio_mic_noise_suppression',
    'audio_mic_agc_compression_gain_db',
    'audio_mic_agc_target_level_dbfs',
    'audio_spk_vol',
    'audio_spk_gain'
  ];
  const run = () => {
    if (typeof window !== 'undefined' && typeof window.initSliders === 'function') {
      window.initSliders(sliderIds);
    }
  };
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', run, { once: true });
  } else {
    run();
  }
})();
