(function () {
  const form = $("#timeForm");
  const tzNameInput = $("#tz_name");
  const tzDataInput = $("#tz_data");
  const tzCustomName = $("#tz_custom_name");
  const tzCustomPosix = $("#tz_custom_posix");
  const tzCustomSave = $("#tz_custom_save");
  const tzCustomList = $("#tz_custom_list");
  const ntpServer0 = $("#ntp_server_0");
  const ntpServer1 = $("#ntp_server_1");
  const ntpServer2 = $("#ntp_server_2");
  const ntpServer3 = $("#ntp_server_3");
  const dhcpIgnoreTimezone = $("#dhcp_ignore_timezone");
  const submitButton = $("#time_submit");
  const syncButton = $("#sync-time");
  const syncResult = $("#sync-time-result");
  const syncStatusRaw = $("#sync-status-raw");

  let BASE_TZ = [];
  let CUSTOM_TZ = {};
  let TZ = [];

  function showSyncResult(type, text) {
    syncResult.innerHTML = "";
    if (!text) return;
    const wrapper = document.createElement("div");
    wrapper.className = `alert alert-${type}`;
    wrapper.textContent = text;
    syncResult.appendChild(wrapper);
  }

  function renderSyncStatus(rawStatus) {
    if (!syncStatusRaw) return;
    syncStatusRaw.textContent =
      rawStatus || "No runtime NTP status available yet.";
  }

  function decodeSyncStatus(data) {
    if (!data || typeof data !== "object") return "";
    const encoded =
      typeof data.sync_status_raw_base64 === "string"
        ? data.sync_status_raw_base64.trim()
        : "";
    if (!encoded) return "";
    return decodeBase64String(encoded) || "";
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    tzNameInput.disabled = state;
    ntpServer0.disabled = state;
    ntpServer1.disabled = state;
    ntpServer2.disabled = state;
    ntpServer3.disabled = state;
    dhcpIgnoreTimezone.disabled = state;
    if (state) {
      showBusy(label || "Working...");
    } else {
      hideBusy();
    }
  }

  function findTimezone(tzName) {
    return TZ.find((tz) => tz.n === tzName);
  }

  function rebuildTimezones() {
    const merged = new Map(BASE_TZ.map((tz) => [tz.n, tz.v]));
    Object.entries(CUSTOM_TZ || {}).forEach(([name, value]) => {
      merged.set(name, value);
    });
    TZ = Array.from(merged, ([n, v]) => ({ n, v })).sort((a, b) =>
      a.n.localeCompare(b.n),
    );
    populateTimezones();
    renderCustomTimezones();
    updateTimezone();
  }

  function renderCustomTimezones() {
    if (!tzCustomList) return;
    tzCustomList.innerHTML = "";
    const names = Object.keys(CUSTOM_TZ || {}).sort();
    if (!names.length) {
      const empty = document.createElement("div");
      empty.className = "small text-secondary";
      empty.textContent = "No custom time zones.";
      tzCustomList.appendChild(empty);
      return;
    }
    names.forEach((name) => {
      const row = document.createElement("div");
      row.className =
        "d-flex flex-wrap justify-content-between align-items-center gap-2 border-top py-2";
      const text = document.createElement("div");
      text.className = "small";
      const strong = document.createElement("strong");
      strong.textContent = name;
      const code = document.createElement("code");
      code.className = "ms-2";
      code.textContent = CUSTOM_TZ[name];
      text.append(strong, code);
      const button = document.createElement("button");
      button.type = "button";
      button.className = "btn btn-outline-danger btn-sm";
      button.textContent = "Remove";
      button.disabled = name === tzNameInput.value;
      button.title = button.disabled
        ? "The active time zone cannot be removed"
        : "Remove this custom time zone";
      button.addEventListener("click", () => removeCustomTimezone(name));
      row.append(text, button);
      tzCustomList.appendChild(row);
    });
  }

  function updateTimezone() {
    const tz = findTimezone(tzNameInput.value);
    if (tz) {
      tzDataInput.value = tz.v;
    }
  }

  function useBrowserTimezone(event) {
    event.preventDefault();
    tzNameInput.value = Intl.DateTimeFormat()
      .resolvedOptions()
      .timeZone.replaceAll("_", " ");
    updateTimezone();
  }

  function populateTimezones() {
    const el = $("#tz_list");
    if (!el) return;
    el.innerHTML = "";
    TZ.forEach((tz) => {
      const option = document.createElement("option");
      option.value = tz.n;
      el.appendChild(option);
    });
  }

  async function loadTimezones() {
    try {
      const response = await fetch("/a/tz.json");
      if (!response.ok) throw new Error("Failed to load timezone data");
      BASE_TZ = await response.json();
      rebuildTimezones();
    } catch (err) {
      console.error("Failed to load timezones:", err);
    }
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, "Loading time settings...");
    }
    try {
      const response = await fetch("/x/json-config-time.cgi", {
        headers: { Accept: "application/json" },
      });
      if (!response.ok) throw new Error("Failed to load time configuration");
      const data = await response.json();
      tzNameInput.value = data.tz_name || "";
      tzDataInput.value = data.tz_data || "";
      CUSTOM_TZ =
        data.tz_custom &&
        typeof data.tz_custom === "object" &&
        !Array.isArray(data.tz_custom)
          ? data.tz_custom
          : {};
      ntpServer0.value = data.ntp_server_0 || "";
      ntpServer1.value = data.ntp_server_1 || "";
      ntpServer2.value = data.ntp_server_2 || "";
      ntpServer3.value = data.ntp_server_3 || "";
      dhcpIgnoreTimezone.checked =
        data.dhcp_ignore_timezone === "true" ||
        data.dhcp_ignore_timezone === true;
      renderSyncStatus(decodeSyncStatus(data));
      rebuildTimezones();
    } catch (err) {
      renderSyncStatus("");
      showAlert("danger", err.message || "Unable to load time configuration.");
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig(payload) {
    toggleBusy(true, "Saving time settings...");
    try {
      const response = await fetch("/x/json-config-time.cgi", {
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
        result.message || "Time configuration saved.",
        "success",
      );
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert("danger", err.message || "Failed to save time configuration.");
    } finally {
      toggleBusy(false);
    }
  }

  async function saveCustomTimezone() {
    if (!tzCustomName || !tzCustomPosix) return;
    const name = tzCustomName.value.trim();
    const posix = tzCustomPosix.value.trim();
    if (!name || !posix) {
      showAlert("danger", "Name and POSIX TZ string are required.");
      return;
    }

    if (tzCustomSave) tzCustomSave.disabled = true;
    try {
      const response = await fetch("/x/json-config-time.cgi", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "tz_custom_set",
          tz_custom_name: name,
          tz_custom_posix: posix,
        }),
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message =
          result && result.error && result.error.message
            ? result.error.message
            : "Failed to save custom time zone";
        throw new Error(message);
      }
      tzCustomName.value = "";
      tzCustomPosix.value = "";
      showAlert("", "");
      showOverlayMessage(
        result.message || "Custom time zone saved.",
        "success",
      );
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert("danger", err.message || "Failed to save custom time zone.");
    } finally {
      if (tzCustomSave) tzCustomSave.disabled = false;
    }
  }

  async function removeCustomTimezone(name) {
    if (!name) return;
    if (!confirm(`Remove the custom time zone "${name}"?`)) return;

    try {
      const response = await fetch("/x/json-config-time.cgi", {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({
          action: "tz_custom_remove",
          tz_custom_name: name,
        }),
      });
      const result = await response.json();
      if (!response.ok || (result && result.error)) {
        const message =
          result && result.error && result.error.message
            ? result.error.message
            : "Failed to remove custom time zone";
        throw new Error(message);
      }
      showAlert("", "");
      showOverlayMessage(
        result.message || "Custom time zone removed.",
        "success",
      );
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert("danger", err.message || "Failed to remove custom time zone.");
    }
  }

  async function syncTime() {
    syncButton.disabled = true;
    syncButton.innerHTML =
      '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Synchronizing...';
    showBusy("Synchronizing time...");
    showSyncResult("", "");

    try {
      const response = await fetch(
        "/x/json-sync-time.cgi?" +
          new URLSearchParams({ ts: Date.now() }).toString(),
      );
      const result = await response.json();

      if (result.error) {
        showSyncResult(
          "danger",
          result.error.message || "Synchronization failed",
        );
      } else {
        showSyncResult("success", result.message || "Time synchronized");
      }
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showSyncResult("danger", err.message || "Failed to synchronize time");
    } finally {
      hideBusy();
      syncButton.disabled = false;
      syncButton.innerHTML =
        '<i class="bi bi-arrow-repeat"></i> Synchronize time';
    }
  }

  form.addEventListener("submit", function (ev) {
    ev.preventDefault();
    const payload = {
      action: "update",
      tz_name: tzNameInput.value.trim(),
      tz_data: tzDataInput.value.trim(),
      ntp_server_0: ntpServer0.value.trim(),
      ntp_server_1: ntpServer1.value.trim(),
      ntp_server_2: ntpServer2.value.trim(),
      ntp_server_3: ntpServer3.value.trim(),
      dhcp_ignore_timezone: dhcpIgnoreTimezone.checked,
    };
    saveConfig(payload);
  });

  tzNameInput.addEventListener("change", updateTimezone);
  tzNameInput.addEventListener("input", updateTimezone);

  $("#frombrowser").addEventListener("click", useBrowserTimezone);
  syncButton.addEventListener("click", syncTime);
  if (tzCustomSave) {
    tzCustomSave.addEventListener("click", saveCustomTimezone);
  }
  [tzCustomName, tzCustomPosix].forEach((input) => {
    if (!input) return;
    input.addEventListener("keydown", (event) => {
      if (event.key === "Enter") {
        event.preventDefault();
        saveCustomTimezone();
      }
    });
  });

  const reloadButton = $("#time-reload");
  if (reloadButton) {
    reloadButton.addEventListener("click", async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert("info", "Time settings reloaded from camera.", 3000);
      } catch (err) {
        showAlert("danger", "Failed to reload time settings.");
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  loadTimezones();
  loadConfig();
})();
