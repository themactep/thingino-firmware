(function() {
  const form = $('#rtspForm');
  const usernameInput = $('#rtsp_username');
  const passwordInput = $('#rtsp_password');
  const passwordReveal = $('#rtsp_password_reveal');
  const submitButton = $('#rtsp_submit');  const defaultHost = window.network_address || window.location.hostname || 'localhost';
  const rtspDefaults = {
    username: 'thingino',
    password: 'thingino',
    onvif_port: '80',
    rtsp_port: '554',
    rtsp_ch0: 'ch0',
    rtsp_ch1: 'ch1',
    rtsp_mic: 'mic'
  };

  function ipv6Wrap(host) {
    return host && host.includes(':') && !host.startsWith('[') ? `[${host}]` : host;
  }

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function toggleBusy(state, label) {
    passwordInput.disabled = state;
    submitButton.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function buildCredential(user, pass) {
    return `${encodeURIComponent(user)}:${encodeURIComponent(pass)}`;
  }

  function updatePasswordFieldVisibility() {
    if (!passwordReveal) return;
    passwordInput.type = passwordReveal.checked ? 'text' : 'password';
  }

  function formatHostWithPort(host, port, defaultPorts = []) {
    const numericPort = parseInt(port, 10);
    if (!port || Number.isNaN(numericPort) || defaultPorts.includes(numericPort)) {
      return host;
    }
    return `${host}:${numericPort}`;
  }

  function applyDefault(value, fallback) {
    return value === undefined || value === null || value === '' ? fallback : value;
  }

  function updateSamples(data) {
    const host = ipv6Wrap(defaultHost);
    const auth = buildCredential(data.username, data.password);
    const onvifTarget = formatHostWithPort(host, data.onvif_port, [80, 443]);
    const rtspTarget = formatHostWithPort(host, data.rtsp_port, [554]);
    const onvifUrl = `onvif://${auth}@${onvifTarget}/onvif/device_service`;
    const rtspMain = `rtsp://${auth}@${rtspTarget}/${data.rtsp_ch0}`;
    const rtspSub = `rtsp://${auth}@${rtspTarget}/${data.rtsp_ch1}`;
    const rtspMic = `rtsp://${auth}@${rtspTarget}/${data.rtsp_mic}`;

    $('#url-onvif').textContent = onvifUrl;
    $('#url-rtsp-main').textContent = rtspMain;
    $('#url-rtsp-sub').textContent = rtspSub;
    $('#url-rtsp-mic').textContent = rtspMic;
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading RTSP settings...');
    }
    try {
      const response = await fetch('/x/json-config-rtsp.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load RTSP configuration');
      const data = await response.json();
      const normalized = {
        username: applyDefault(data.username, rtspDefaults.username),
        password: applyDefault(data.password, rtspDefaults.password),
        onvif_port: applyDefault(data.onvif_port, rtspDefaults.onvif_port),
        rtsp_port: applyDefault(data.rtsp_port, rtspDefaults.rtsp_port),
        rtsp_ch0: applyDefault(data.rtsp_ch0, rtspDefaults.rtsp_ch0),
        rtsp_ch1: applyDefault(data.rtsp_ch1, rtspDefaults.rtsp_ch1),
        rtsp_mic: applyDefault(data.rtsp_mic, rtspDefaults.rtsp_mic)
      };
      usernameInput.value = normalized.username;
      passwordInput.value = normalized.password;
      updateSamples(normalized);
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load RTSP configuration.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(password) {
    toggleBusy(true, 'Saving RTSP settings...');
    try {
      const response = await fetch('/x/json-config-rtsp.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ password })
      });
      const result = await response.json();
      if (!response.ok || result.error) {
        throw new Error(result.message || 'Failed to update password');
      }
      showAlert('', '');
      showOverlayMessage('RTSP/ONVIF password updated. Services restarted.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to update password.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const newPassword = passwordInput.value.trim();
    if (!newPassword) {
      showAlert('warning', 'Please provide a password.');
      return;
    }
    saveConfig(newPassword);
  });

  if (passwordReveal) {
    passwordReveal.addEventListener('change', () => {
      updatePasswordFieldVisibility();
      passwordInput.focus();
    });
    updatePasswordFieldVisibility();
  }

  const reloadButton = $('#rtsp-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'RTSP settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload RTSP settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
