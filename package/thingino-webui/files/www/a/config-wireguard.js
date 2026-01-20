(function() {
  const form = $('#wireguardForm');
  const privkeyInput = $('#wg_privkey');
  const peerpskInput = $('#wg_peerpsk');
  const addressInput = $('#wg_address');
  const portInput = $('#wg_port');
  const dnsInput = $('#wg_dns');
  const endpointInput = $('#wg_endpoint');
  const peerpubInput = $('#wg_peerpub');
  const mtuInput = $('#wg_mtu');
  const keepaliveInput = $('#wg_keepalive');
  const allowedInput = $('#wg_allowed');
  const enabledSwitch = $('#wg_enabled');
  const submitButton = $('#wg_submit');
  const toggleButton = $('#btn-wg-toggle');
  const wgCtrl = $('#wg-ctrl');
  const wgCtrlMessage = $('#wg-ctrl-message');
  const wgToggleLabel = $('#wg-toggle-label');
  const wgNotSupported = $('#wg-not-supported');let wgStatus = 0;
  let wgSupported = false;

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
    privkeyInput.disabled = state;
    peerpskInput.disabled = state;
    addressInput.disabled = state;
    portInput.disabled = state;
    dnsInput.disabled = state;
    endpointInput.disabled = state;
    peerpubInput.disabled = state;
    mtuInput.disabled = state;
    keepaliveInput.disabled = state;
    allowedInput.disabled = state;
    enabledSwitch.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function updateWgControl(status) {
    wgStatus = status;
    wgCtrl.classList.remove('d-none', 'alert-success', 'alert-danger');
    toggleButton.classList.remove('btn-success', 'btn-danger');

    if (wgStatus === 1) {
      wgCtrl.classList.add('alert-danger');
      toggleButton.classList.add('btn-danger');
      wgCtrlMessage.textContent = 'Attention! Switching WireGuard off while working over the VPN connection will render this camera inaccessible! Make sure you have a backup plan.';
      wgToggleLabel.textContent = 'OFF';
    } else {
      wgCtrl.classList.add('alert-success');
      toggleButton.classList.add('btn-success');
      wgCtrlMessage.textContent = 'Please click the button below to switch WireGuard VPN on. Make sure all settings are correct!';
      wgToggleLabel.textContent = 'ON';
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading WireGuard settings...');
    }
    try {
      const response = await fetch('/x/json-config-wireguard.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load WireGuard configuration');
      const data = await response.json();

      wgSupported = data.wg_supported === true;
      if (!wgSupported) {
        wgNotSupported.classList.remove('d-none');
        form.classList.add('d-none');
        return;
      }

      privkeyInput.value = data.privkey || '';
      peerpskInput.value = data.peerpsk || '';
      addressInput.value = data.address || '';
      portInput.value = data.port || '';
      dnsInput.value = data.dns || '';
      endpointInput.value = data.endpoint || '';
      peerpubInput.value = data.peerpub || '';
      mtuInput.value = data.mtu || '';
      keepaliveInput.value = data.keepalive || '';
      allowedInput.value = data.allowed || '';
      enabledSwitch.checked = data.enabled === true;

      updateWgControl(data.wg_status || 0);
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load WireGuard configuration.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, 'Saving WireGuard settings...');
    try {
      const response = await fetch('/x/json-config-wireguard.cgi', {
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
      showOverlayMessage(result.message || 'WireGuard configuration saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save WireGuard configuration.');
    } finally {
      toggleBusy(false);
    }
  }

  async function toggleWireGuard() {
    const targetState = wgStatus === 1 ? 0 : 1;
    toggleButton.disabled = true;
    showBusy('Switching WireGuard...');

    try {
      const response = await fetch('/x/json-wireguard.cgi?iface=wg0&state=' + targetState);
      const result = await response.json();

      if (result.error) {
        showAlert('danger', result.error.message || 'Failed to toggle WireGuard');
      } else {
        updateWgControl(result.message.status || 0);
        showAlert('', '');
        showOverlayMessage(result.message.message || 'WireGuard status updated', 'success');
      }
    } catch (err) {
      showAlert('danger', err.message || 'Failed to toggle WireGuard');
    } finally {
      hideBusy();
      toggleButton.disabled = false;
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    const payload = {
      enabled: enabledSwitch.checked,
      privkey: privkeyInput.value.trim(),
      peerpsk: peerpskInput.value.trim(),
      address: addressInput.value.trim(),
      port: portInput.value.trim(),
      dns: dnsInput.value.trim(),
      endpoint: endpointInput.value.trim(),
      peerpub: peerpubInput.value.trim(),
      mtu: mtuInput.value.trim(),
      keepalive: keepaliveInput.value.trim(),
      allowed: allowedInput.value.trim()
    };
    saveConfig(payload);
  });

  toggleButton.addEventListener('click', toggleWireGuard);

  $$('.password input[type="checkbox"]').forEach(checkbox => {
    checkbox.addEventListener('change', function() {
      const targetId = this.getAttribute('data-for');
      const targetInput = $('#' + targetId);
      if (targetInput) {
        targetInput.type = this.checked ? 'text' : 'password';
      }
    });
  });

  const reloadButton = $('#wireguard-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'WireGuard settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload WireGuard settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
