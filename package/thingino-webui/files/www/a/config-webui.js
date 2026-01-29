(function() {
  const form = $('#webuiForm');
  const usernameInput = $('#webui_username');
  const passwordInput = $('#webui_password');
  const passwordReveal = $('#webui_password_reveal');
  const themeSelect = $('#webui_theme');
  const paranoidSwitch = $('#webui_paranoid');
  const trackFocusSwitch = $('#webui_track_focus');
  const focusTimeoutInput = $('#webui_focus_timeout');
  const submitButton = $('#webui_submit');  const webuiDefaults = {
    username: 'root',
    theme: 'auto',
    paranoid: false,
    track_focus: false,
    focus_timeout: 0
  };

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
    passwordInput.disabled = state;
    if (passwordReveal) {
      passwordReveal.disabled = state;
    }
    themeSelect.disabled = state;
    paranoidSwitch.disabled = state;
    trackFocusSwitch.disabled = state;
    focusTimeoutInput.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function resetPasswordField() {
    passwordInput.value = '';
    passwordInput.type = 'password';
    if (passwordReveal) {
      passwordReveal.checked = false;
    }
  }

  function handlePasswordReveal() {
    passwordInput.type = passwordReveal.checked ? 'text' : 'password';
    passwordInput.focus();
  }

  if (passwordReveal) {
    passwordReveal.addEventListener('change', handlePasswordReveal);
  }

  function resolveActiveTheme(themePreference) {
    if (themePreference === 'light' || themePreference === 'dark') {
      return themePreference;
    }
    const hour = new Date().getHours();
    return hour > 8 && hour < 20 ? 'light' : 'dark';
  }

  function normalizeConfig(raw) {
    const allowedThemes = ['light', 'dark', 'auto'];
    const theme = allowedThemes.includes(raw.theme) ? raw.theme : webuiDefaults.theme;
    const focusTimeout = parseInt(raw.focus_timeout) || webuiDefaults.focus_timeout;
    return {
      username: raw.username || webuiDefaults.username,
      theme,
      paranoid: raw.paranoid === true,
      track_focus: raw.track_focus === true,
      focus_timeout: Math.max(0, Math.min(300, focusTimeout)),
      activeTheme: resolveActiveTheme(theme)
    };
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading WebUI settings...');
    }
    try {
      const response = await fetch('/x/json-config-webui.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load Web UI settings');
      const data = await response.json();
      const normalized = normalizeConfig(data);
      usernameInput.value = normalized.username;
      themeSelect.value = normalized.theme;
      paranoidSwitch.checked = normalized.paranoid;
      trackFocusSwitch.checked = normalized.track_focus;
      focusTimeoutInput.value = normalized.focus_timeout;
      resetPasswordField();
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load Web UI settings.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving WebUI settings...');
    try {
      const response = await fetch('/x/json-config-webui.cgi', {
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
      showOverlayMessage('Web UI settings saved.', 'success');
      resetPasswordField();
      await loadConfig({ preserveBusy: true });
      // Reload preview focus settings if the function is available
      if (window.reloadPreviewFocusSettings && typeof window.reloadPreviewFocusSettings === 'function') {
        await window.reloadPreviewFocusSettings();
      }
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save Web UI settings.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const payload = {
      theme: themeSelect.value,
      paranoid: paranoidSwitch.checked,
      track_focus: trackFocusSwitch.checked,
      focus_timeout: parseInt(focusTimeoutInput.value) || 0
    };
    const newPassword = passwordInput.value.trim();
    if (newPassword) {
      payload.password = newPassword;
    }
    saveConfig(payload);
  });

  const reloadButton = $('#webui-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Web UI settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload web UI settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  // API Key Management
  async function loadApiKey() {
    try {
      const response = await fetch('/x/api-key.cgi');
      const data = await response.json();

      const keyDisplay = document.getElementById('api_key_display');
      const copyBtn = document.getElementById('api_key_copy');
      const deleteBtn = document.getElementById('api_key_delete');
      const exampleDiv = document.getElementById('api_key_example');
      const exampleValue = document.getElementById('api_key_example_value');

      if (data.exists && data.api_key) {
        keyDisplay.value = data.api_key;
        copyBtn.disabled = false;
        deleteBtn.disabled = false;
        exampleDiv.classList.remove('d-none');
        exampleValue.textContent = data.api_key;
      } else {
        keyDisplay.value = '';
        keyDisplay.placeholder = 'No API key generated';
        copyBtn.disabled = true;
        deleteBtn.disabled = true;
        exampleDiv.classList.add('d-none');
      }
    } catch (err) {
      console.error('Failed to load API key:', err);
    }
  }

  const generateBtn = document.getElementById('api_key_generate');
  if (generateBtn) {
    generateBtn.addEventListener('click', async () => {
      if (!confirm('Generate a new API key? This will invalidate the old key if it exists.')) {
        return;
      }

      try {
        const response = await fetch('/x/api-key.cgi', { method: 'POST' });
        const data = await response.json();

        if (data.api_key) {
          await loadApiKey();
          showAlert('success', 'API key generated successfully!');
        } else {
          showAlert('danger', 'Failed to generate API key');
        }
      } catch (err) {
        showAlert('danger', 'Error: ' + err.message);
      }
    });
  }

  const deleteBtn = document.getElementById('api_key_delete');
  if (deleteBtn) {
    deleteBtn.addEventListener('click', async () => {
      if (!confirm('Delete the API key? API access will stop working.')) {
        return;
      }

      try {
        const response = await fetch('/x/api-key.cgi', { method: 'DELETE' });
        await response.json();
        await loadApiKey();
        showAlert('success', 'API key deleted');
      } catch (err) {
        showAlert('danger', 'Error: ' + err.message);
      }
    });
  }

  const copyBtn = document.getElementById('api_key_copy');
  if (copyBtn) {
    copyBtn.addEventListener('click', () => {
      const keyDisplay = document.getElementById('api_key_display');
      keyDisplay.select();
      document.execCommand('copy');

      const originalHtml = copyBtn.innerHTML;
      copyBtn.innerHTML = '<i class="bi bi-check"></i>';
      setTimeout(() => {
        copyBtn.innerHTML = originalHtml;
      }, 2000);
    });
  }

  loadConfig();
  loadApiKey();
})();
