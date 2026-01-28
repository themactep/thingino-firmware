(function() {
  const form = $('#networkForm');
  const contentWrap = $('#network-content');  const submitButton = $('#network_submit');
  const wifiApToggle = $('#wifi_ap_enabled');
  const hostnameInput = $('#hostname');
  const dnsPrimaryInput = $('#dns_primary');
  const dnsSecondaryInput = $('#dns_secondary');
  const wifiSsidInput = $('#wifi_ssid');
  const wifiPassInput = $('#wifi_pass');
  const wifiBssidInput = $('#wifi_bssid');
  const wifiApSsidInput = $('#wifi_ap_ssid');
  const wifiApPassInput = $('#wifi_ap_pass');

  const ifaceCards = document.querySelectorAll('.iface-card');

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function toggleBusy(state, label) {
    if (state) {
      submitButton.disabled = true;
      showBusy(label || 'Working...');
    } else {
      submitButton.disabled = false;
      hideBusy();
    }
  }

  function toggleCardAvailability(card, enabled) {
    card.classList.toggle('iface-disabled', !enabled);
    card.querySelectorAll('.card-body input, .card-body button, .card-body select').forEach(el => {
      if (el.classList.contains('iface-enabled')) return;
      el.disabled = !enabled;
    });
    card.querySelectorAll('.generate-mac').forEach(btn => {
      btn.disabled = !enabled;
    });
  }

  function toggleDhcpFields(card, dhcpEnabled) {
    card.querySelectorAll('[data-static-fields] input').forEach(input => {
      input.disabled = dhcpEnabled || input.closest('.iface-card').classList.contains('iface-disabled');
    });
  }

  function updateLinkStatus(card, data) {
    const badge = card.querySelector('[data-role="link-status"]');
    if (!badge) return;
    const linkUp = data.link_up === true || data.link_up === 'true';
    badge.textContent = linkUp ? 'Link up' : 'Link down';
    badge.classList.remove('text-bg-secondary', 'text-bg-success', 'text-bg-danger');
    badge.classList.add(linkUp ? 'text-bg-success' : 'text-bg-secondary');
  }

  function generateMacAddress() {
    let mac = '';
    for (let i = 0; i < 6; i++) {
      let byte = Math.floor(Math.random() * 256);
      if (i === 0) {
        byte |= 0x02; // locally administered
        byte &= 0xFE; // unicast
      }
      mac += byte.toString(16).toUpperCase().padStart(2, '0');
      if (i < 5) mac += ':';
    }
    return mac;
  }

  function handleMacGeneration(button) {
    const iface = button.dataset.iface;
    const input = $(`#${iface}_mac`);
    if (!input) return;
    if (input.value.trim()) {
      window.alert('Clear the MAC address before generating a new value.');
      return;
    }
    input.value = generateMacAddress();
  }

  function collectInterfacePayload(card) {
    const iface = card.dataset.iface;
    return {
      enabled: card.querySelector('.iface-enabled').checked,
      dhcp: card.querySelector('.iface-dhcp').checked,
      ipv6: card.querySelector('.iface-ipv6').checked,
      mac: ($(`#${iface}_mac`).value || '').trim(),
      address: ($(`#${iface}_address`).value || '').trim(),
      netmask: ($(`#${iface}_netmask`).value || '').trim(),
      gateway: ($(`#${iface}_gateway`).value || '').trim(),
      broadcast: ($(`#${iface}_broadcast`).value || '').trim()
    };
  }

  function applyInterfaceState(card, data) {
    card.querySelector('.iface-enabled').checked = data.enabled === true || data.enabled === 'true';
    card.querySelector('.iface-dhcp').checked = data.dhcp === true || data.dhcp === 'true';
    card.querySelector('.iface-ipv6').checked = data.ipv6 === true || data.ipv6 === 'true';
    $(`#${card.dataset.iface}_mac`).value = data.mac || '';
    $(`#${card.dataset.iface}_address`).value = data.address || '';
    $(`#${card.dataset.iface}_netmask`).value = data.netmask || '';
    $(`#${card.dataset.iface}_gateway`).value = data.gateway || '';
    $(`#${card.dataset.iface}_broadcast`).value = data.broadcast || '';
    toggleCardAvailability(card, card.querySelector('.iface-enabled').checked);
    toggleDhcpFields(card, card.querySelector('.iface-dhcp').checked);
    updateLinkStatus(card, data);
  }

  function setFormEnabled(state) {
    form.querySelectorAll('input, button, select, textarea').forEach(el => {
      if (el === submitButton) return;
      el.disabled = !state && !el.classList.contains('iface-enabled');
    });
  }

  function updateWifiApValidation() {
    const enabled = wifiApToggle.checked;
    wifiApSsidInput.required = enabled;
    wifiApPassInput.required = enabled;
  }

  wifiApToggle.addEventListener('change', updateWifiApValidation);

  document.querySelectorAll('.generate-mac').forEach(button => {
    button.addEventListener('click', ev => {
      ev.preventDefault();
      handleMacGeneration(button);
    });
  });

  ifaceCards.forEach(card => {
    const enabledToggle = card.querySelector('.iface-enabled');
    const dhcpToggle = card.querySelector('.iface-dhcp');
    enabledToggle.addEventListener('change', () => {
      toggleCardAvailability(card, enabledToggle.checked);
      toggleDhcpFields(card, dhcpToggle.checked);
    });
    dhcpToggle.addEventListener('change', () => {
      toggleDhcpFields(card, dhcpToggle.checked);
    });
  });

  async function loadConfig() {
    toggleBusy(true, 'Loading network settings...');
    showAlert('', '');
    try {
      const response = await fetch('/x/json-config-network.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load network settings');
      const data = await response.json();
      hostnameInput.value = data.hostname || '';
      dnsPrimaryInput.value = (data.dns && data.dns.primary) || '';
      dnsSecondaryInput.value = (data.dns && data.dns.secondary) || '';
      wifiSsidInput.value = (data.wifi && data.wifi.ssid) || '';
      wifiPassInput.value = (data.wifi && data.wifi.password) || '';
      wifiBssidInput.value = (data.wifi && data.wifi.bssid) || '';
      wifiApSsidInput.value = (data.wifi_ap && data.wifi_ap.ssid) || '';
      wifiApPassInput.value = (data.wifi_ap && data.wifi_ap.password) || '';
      wifiApToggle.checked = data.wifi_ap && (data.wifi_ap.enabled === true || data.wifi_ap.enabled === 'true');
      updateWifiApValidation();
      if (data.interfaces) {
        ifaceCards.forEach(card => {
          const ifaceData = data.interfaces[card.dataset.iface] || {};
          applyInterfaceState(card, ifaceData);
        });
      }
      if (contentWrap) contentWrap.classList.remove('d-none');
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load network settings.');
    } finally {
      toggleBusy(false);
    }
  }

  function buildPayload() {
    const payload = {
      hostname: hostnameInput.value.trim(),
      dns: {
        primary: dnsPrimaryInput.value.trim(),
        secondary: dnsSecondaryInput.value.trim()
      },
      wifi: {
        ssid: wifiSsidInput.value.trim(),
        password: wifiPassInput.value.trim(),
        bssid: wifiBssidInput.value.trim()
      },
      wifi_ap: {
        enabled: wifiApToggle.checked,
        ssid: wifiApSsidInput.value.trim(),
        password: wifiApPassInput.value.trim()
      },
      interfaces: {}
    };
    ifaceCards.forEach(card => {
      payload.interfaces[card.dataset.iface] = collectInterfacePayload(card);
    });
    return payload;
  }

  async function saveConfig(ev) {
    ev.preventDefault();
    toggleBusy(true, 'Saving network settings...');
    try {
      const payload = buildPayload();
      const response = await fetch('/x/json-config-network.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message = result && result.error && result.error.message ? result.error.message : 'Failed to save network settings';
        throw new Error(message);
      }
      showAlert('', '');
      showOverlayMessage('Network settings updated. A reboot may be required to apply everything.', 'success');
      await loadConfig();
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save network settings.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', saveConfig);

  const reloadButton = $('#network-reload');
  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Network settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload network settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  setFormEnabled(true);
  loadConfig();
})();
