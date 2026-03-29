(function () {
  const form = $("#wireguardForm");
  const privkeyInput = $("#wg_privkey");
  const localpubInput = $("#wg_localpub");
  const peerpskInput = $("#wg_peerpsk");
  const addressInput = $("#wg_address");
  const portInput = $("#wg_port");
  const dnsInput = $("#wg_dns");
  const endpointInput = $("#wg_endpoint");
  const peerpubInput = $("#wg_peerpub");
  const mtuInput = $("#wg_mtu");
  const keepaliveInput = $("#wg_keepalive");
  const allowedInput = $("#wg_allowed");
  const enabledSwitch = $("#wg_enabled");
  const submitButton = $("#wg_submit");
  const generateKeypairButton = $("#wg-generate-keypair");
  const generatePskButton = $("#wg-generate-psk");
  const importProfileButton = $("#wg-import-profile");
  const provisionUrlInput = $("#wg_provision_url");
  const provisionPeerInput = $("#wg_provision_peer");
  const provisionTokenInput = $("#wg_provision_token");
  const toggleButton = $("#btn-wg-toggle");
  const wgCtrl = $("#wg-ctrl");
  const wgCtrlMessage = $("#wg-ctrl-message");
  const wgToggleLabel = $("#wg-toggle-label");
  const wgNotSupported = $("#wg-not-supported");
  let wgStatus = 0;
  let wgSupported = false;
  let isBusy = false;

  function setKeyInputVisibility(input, visible) {
    input.type = visible ? "text" : "password";
  }

  function updateKeyActionButton(button, input, options) {
    if (!button) {
      return;
    }

    const hasValue = input.value.trim().length !== 0;
    const icon = button.querySelector("i");
    const isVisible = input.type === "text";

    button.disabled = isBusy;

    if (!hasValue) {
      setKeyInputVisibility(input, false);
      button.title = options.generateTitle;
      button.setAttribute("aria-label", options.generateTitle);
      if (icon) {
        icon.className = `bi ${options.generateIcon}`;
      }
      return;
    }

    button.title = isVisible ? options.hideTitle : options.showTitle;
    button.setAttribute("aria-label", button.title);
    if (icon) {
      icon.className = `bi ${isVisible ? "bi-eye-slash" : "bi-eye"}`;
    }
  }

  function updateKeyActionButtons() {
    updateKeyActionButton(generateKeypairButton, privkeyInput, {
      generateTitle: "Generate key pair",
      generateIcon: "bi-key",
      showTitle: "Show private key",
      hideTitle: "Hide private key",
    });
    updateKeyActionButton(generatePskButton, peerpskInput, {
      generateTitle: "Generate PSK",
      generateIcon: "bi-shield-lock",
      showTitle: "Show pre-shared key",
      hideTitle: "Hide pre-shared key",
    });
  }

  function toggleBusy(state, label) {
    isBusy = state;
    submitButton.disabled = state;
    if (importProfileButton) importProfileButton.disabled = state;
    privkeyInput.disabled = state;
    if (provisionUrlInput) provisionUrlInput.disabled = state;
    if (provisionPeerInput) provisionPeerInput.disabled = state;
    if (provisionTokenInput) provisionTokenInput.disabled = state;
    if (localpubInput) localpubInput.disabled = state;
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
    updateKeyActionButtons();
    if (state) {
      showBusy(label || "Working...");
    } else {
      hideBusy();
    }
  }

  function updateWgControl(status) {
    wgStatus = status;
    wgCtrl.classList.remove("d-none", "alert-success", "alert-danger");
    toggleButton.classList.remove("btn-success", "btn-danger");

    if (wgStatus === 1) {
      wgCtrl.classList.add("alert-danger");
      toggleButton.classList.add("btn-danger");
      wgCtrlMessage.textContent =
        "Attention! Switching WireGuard off while working over the VPN connection will render this camera inaccessible! Make sure you have a backup plan.";
      wgToggleLabel.textContent = "OFF";
    } else {
      wgCtrl.classList.add("alert-success");
      toggleButton.classList.add("btn-success");
      wgCtrlMessage.textContent =
        "Please click the button below to switch WireGuard VPN on. Make sure all settings are correct!";
      wgToggleLabel.textContent = "ON";
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, "Loading WireGuard settings...");
    }
    try {
      const response = await fetch("/x/json-config-wireguard.cgi", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok)
        throw new Error("Failed to load WireGuard configuration");
      const data = await response.json();

      wgSupported = data.wg_supported === true;
      if (!wgSupported) {
        wgNotSupported.classList.remove("d-none");
        form.classList.add("d-none");
        return;
      }

      privkeyInput.value = data.privkey || "";
      if (localpubInput) localpubInput.value = data.localpub || "";
      peerpskInput.value = data.peerpsk || "";
      addressInput.value = data.address || "";
      portInput.value = data.port || "";
      dnsInput.value = data.dns || "";
      endpointInput.value = data.endpoint || "";
      if (provisionUrlInput) provisionUrlInput.value = data.provision_url || "";
      if (provisionPeerInput)
        provisionPeerInput.value = data.provision_peer || "";
      if (provisionTokenInput)
        provisionTokenInput.value = data.provision_token || "";
      peerpubInput.value = data.peerpub || "";
      mtuInput.value = data.mtu || "";
      keepaliveInput.value = data.keepalive || "";
      allowedInput.value = data.allowed || "";
      enabledSwitch.checked = data.enabled === true;

      updateWgControl(data.wg_status || 0);
      updateKeyActionButtons();
    } catch (err) {
      showAlert(
        "danger",
        err.message || "Unable to load WireGuard configuration.",
      );
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function generateWireGuardKeys(action) {
    toggleBusy(
      true,
      action === "generate_keypair"
        ? "Generating WireGuard key pair..."
        : "Generating pre-shared key...",
    );
    try {
      const response = await fetch("/x/json-config-wireguard.cgi", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ action }),
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message =
          result && result.error && result.error.message
            ? result.error.message
            : "Failed to generate WireGuard keys";
        throw new Error(message);
      }

      const data = (result && result.data) || {};
      if (action === "generate_keypair") {
        privkeyInput.value = data.privkey || "";
        if (localpubInput) localpubInput.value = data.localpub || "";
      }
      if (typeof data.peerpsk === "string") {
        peerpskInput.value = data.peerpsk;
      }

      showOverlayMessage(
        result.message ||
          (action === "generate_keypair"
            ? "WireGuard key pair generated."
            : "WireGuard pre-shared key generated."),
        "success",
      );
    } catch (err) {
      showAlert("danger", err.message || "Failed to generate WireGuard keys.");
    } finally {
      toggleBusy(false);
    }
  }

  async function handleKeyAction(action, input) {
    if (input.value.trim().length === 0) {
      await generateWireGuardKeys(action);
      return;
    }

    setKeyInputVisibility(input, input.type === "password");
    updateKeyActionButtons();
  }

  async function importProvisionedProfile() {
    toggleBusy(true, "Importing WireGuard profile...");
    try {
      const response = await fetch("/x/json-config-wireguard.cgi", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "provision_import",
          provision_url: provisionUrlInput
            ? provisionUrlInput.value.trim()
            : "",
          provision_peer: provisionPeerInput
            ? provisionPeerInput.value.trim()
            : "",
          provision_token: provisionTokenInput
            ? provisionTokenInput.value.trim()
            : "",
        }),
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message =
          result && result.error && result.error.message
            ? result.error.message
            : "Failed to import WireGuard profile";
        throw new Error(message);
      }

      showOverlayMessage(
        result.message || "WireGuard profile imported.",
        "success",
      );
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert("danger", err.message || "Failed to import WireGuard profile.");
    } finally {
      toggleBusy(false);
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, "Saving WireGuard settings...");
    try {
      const response = await fetch("/x/json-config-wireguard.cgi", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message =
          result && result.error && result.error.message
            ? result.error.message
            : "Failed to save settings";
        throw new Error(message);
      }
      showAlert("", "");
      showOverlayMessage(
        result.message || "WireGuard configuration saved.",
        "success",
      );
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert(
        "danger",
        err.message || "Failed to save WireGuard configuration.",
      );
    } finally {
      toggleBusy(false);
    }
  }

  async function toggleWireGuard() {
    const targetState = wgStatus === 1 ? 0 : 1;
    toggleButton.disabled = true;
    showBusy("Switching WireGuard...");

    try {
      const response = await fetch(
        "/x/json-wireguard.cgi?iface=wg0&state=" + targetState,
      );
      const result = await response.json();

      if (result.error) {
        showAlert(
          "danger",
          result.error.message || "Failed to toggle WireGuard",
        );
      } else {
        updateWgControl(result.message.status || 0);
        showAlert("", "");
        showOverlayMessage(
          result.message.message || "WireGuard status updated",
          "success",
        );
      }
    } catch (err) {
      showAlert("danger", err.message || "Failed to toggle WireGuard");
    } finally {
      hideBusy();
      toggleButton.disabled = false;
    }
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    const payload = {
      enabled: enabledSwitch.checked,
      privkey: privkeyInput.value.trim(),
      peerpsk: peerpskInput.value.trim(),
      address: addressInput.value.trim(),
      port: portInput.value.trim(),
      dns: dnsInput.value.trim(),
      endpoint: endpointInput.value.trim(),
      provision_url: provisionUrlInput ? provisionUrlInput.value.trim() : "",
      provision_peer: provisionPeerInput ? provisionPeerInput.value.trim() : "",
      provision_token: provisionTokenInput
        ? provisionTokenInput.value.trim()
        : "",
      peerpub: peerpubInput.value.trim(),
      mtu: mtuInput.value.trim(),
      keepalive: keepaliveInput.value.trim(),
      allowed: allowedInput.value.trim(),
    };
    saveConfig(payload);
  });

  toggleButton.addEventListener("click", toggleWireGuard);

  if (generateKeypairButton) {
    generateKeypairButton.addEventListener("click", () =>
      handleKeyAction("generate_keypair", privkeyInput),
    );
  }

  if (generatePskButton) {
    generatePskButton.addEventListener("click", () =>
      handleKeyAction("generate_psk", peerpskInput),
    );
  }

  if (importProfileButton) {
    importProfileButton.addEventListener("click", () =>
      importProvisionedProfile(),
    );
  }

  privkeyInput.addEventListener("input", updateKeyActionButtons);
  peerpskInput.addEventListener("input", updateKeyActionButtons);

  const reloadButton = $("#wireguard-reload");
  if (reloadButton) {
    reloadButton.addEventListener("click", async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert("info", "WireGuard settings reloaded from camera.", 3000);
      } catch (err) {
        showAlert("danger", "Failed to reload WireGuard settings.");
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
