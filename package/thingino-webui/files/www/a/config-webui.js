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

  loadConfig();
})();
