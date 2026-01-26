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

  function initStreamerConfig() {
    const saveButton = $('#save-prudynt-config');
    if (saveButton) {
      saveButton.addEventListener('click', savePrudyntConfig);
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initStreamerConfig, { once: true });
  } else {
    initStreamerConfig();
  }
})();
