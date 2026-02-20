(function () {
  'use strict';

  const endpoint = '/x/json-prudynt.cgi';

  function $(selector) {
    return document.querySelector(selector);
  }

  async function confirm(message) {
    return new Promise((resolve) => {
      const result = window.confirm(message);
      resolve(result);
    });
  }

  function showAlert(type, message, duration) {
    const alertWrapper = document.createElement('div');
    alertWrapper.className = 'position-fixed top-0 start-50 translate-middle-x p-3';
    alertWrapper.style.zIndex = '9999';

    const alert = document.createElement('div');
    alert.className = `alert alert-${type} alert-dismissible fade show`;
    alert.setAttribute('role', 'alert');
    alert.innerHTML = `
      ${message}
      <button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>
    `;

    alertWrapper.appendChild(alert);
    document.body.appendChild(alertWrapper);

    if (duration) {
      setTimeout(() => {
        alert.classList.remove('show');
        setTimeout(() => alertWrapper.remove(), 150);
      }, duration);
    }
  }

  async function savePrudyntConfig() {
    const confirmed = await confirm('Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.');
    if (!confirmed) return;

    const saveButton = $('#save-prudynt-config');
    if (saveButton) saveButton.disabled = true;

    try {
      const payload = { action: { save_config: null } };
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }

      const data = await response.json();
      if (!data?.action || data.action.save_config !== 'ok') {
        throw new Error('Save failed');
      }

      showAlert('success', 'Configuration saved successfully to /etc/prudynt.json', 3000);
    } catch (err) {
      console.error('Failed to save prudynt config:', err);
      showAlert('danger', `Failed to save configuration: ${err.message || err}`);
    } finally {
      if (saveButton) saveButton.disabled = false;
    }
  }

  const SOC_MODE_MAP = {
    t10: ['CBR', 'VBR', 'FIXQP', 'SMART'],
    t20: ['CBR', 'VBR', 'FIXQP', 'SMART'],
    t21: ['CBR', 'VBR', 'FIXQP', 'SMART'],
    t23: ['CBR', 'VBR', 'FIXQP', 'SMART'],
    t30: ['CBR', 'VBR', 'FIXQP', 'SMART'],
    t31: ['CBR', 'VBR', 'FIXQP', 'CAPPED_VBR', 'CAPPED_QUALITY'],
    t40: ['CBR', 'VBR', 'FIXQP', 'CAPPED_VBR', 'CAPPED_QUALITY'],
    t41: ['CBR', 'VBR', 'FIXQP', 'CAPPED_VBR', 'CAPPED_QUALITY'],
    c100: ['CBR', 'VBR', 'FIXQP', 'CAPPED_VBR', 'CAPPED_QUALITY']
  };

  const SOC_FORMAT_MAP = {
    t10: ['H264'],
    t20: ['H264'],
    t21: ['H264'],
    t23: ['H264'],
    t30: ['H264', 'H265'],
    t31: ['H264', 'H265'],
    t40: ['H264', 'H265'],
    t41: ['H264', 'H265'],
    c100: ['H264', 'H265']
  };

  function getSocFamily(soc) {
    if (!soc) return null;
    const match = soc.toLowerCase().match(/^(t\d+|c\d+)/);
    return match ? match[1] : null;
  }

  function getSupportedModes(soc) {
    const socFamily = getSocFamily(soc);
    return socFamily && SOC_MODE_MAP[socFamily] 
      ? SOC_MODE_MAP[socFamily]
      : ['CBR', 'VBR', 'FIXQP', 'CAPPED_VBR', 'CAPPED_QUALITY'];
  }

  function getSupportedFormats(soc) {
    const socFamily = getSocFamily(soc);
    return socFamily && SOC_FORMAT_MAP[socFamily]
      ? SOC_FORMAT_MAP[socFamily]
      : ['H264', 'H265'];
  }

  function populateModeSelectors(soc) {
    const supportedModes = getSupportedModes(soc);
    const selectors = document.querySelectorAll('#stream0_mode, #stream1_mode');
    
    selectors.forEach(select => {
      if (!select) return;
      
      const currentValue = select.value;
      select.innerHTML = '<option value="">- Select -</option>';
      
      supportedModes.forEach(mode => {
        const option = document.createElement('option');
        option.value = mode;
        option.textContent = mode.replace(/_/g, ' ');
        select.appendChild(option);
      });
      
      if (currentValue && supportedModes.includes(currentValue)) {
        select.value = currentValue;
      }
    });
  }

  function populateFormatSelectors(soc) {
    const supportedFormats = getSupportedFormats(soc);
    const selectors = document.querySelectorAll('#stream0_format, #stream1_format');
    
    selectors.forEach(select => {
      if (!select) return;
      
      const currentValue = select.value;
      select.innerHTML = '<option value="">- Select -</option>';
      
      supportedFormats.forEach(format => {
        const option = document.createElement('option');
        option.value = format;
        option.textContent = format;
        select.appendChild(option);
      });
      
      if (currentValue && supportedFormats.includes(currentValue)) {
        select.value = currentValue;
      }
    });
  }

  async function detectSocAndPopulateModes() {
    try {
      const soc = window.thinginoUIConfig?.device?.soc;
      if (soc) {
        populateModeSelectors(soc);
        populateFormatSelectors(soc);
        return;
      }

      const response = await fetch('/etc/os-release');
      if (response.ok) {
        const text = await response.text();
        const socMatch = text.match(/^SOC=(.+)$/m);
        if (socMatch && socMatch[1]) {
          populateModeSelectors(socMatch[1]);
          populateFormatSelectors(socMatch[1]);
          return;
        }
      }
    } catch (err) {
      console.warn('Failed to detect SOC, using default modes:', err);
    }
    
    populateModeSelectors(null);
    populateFormatSelectors(null);
  }

  function initStreamerConfig() {
    const saveButton = $('#save-prudynt-config');
    if (saveButton) {
      saveButton.addEventListener('click', savePrudyntConfig);
    }
    
    detectSocAndPopulateModes();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initStreamerConfig, { once: true });
  } else {
    initStreamerConfig();
  }
})();
