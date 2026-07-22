(function () {
  "use strict";

  const endpoint = "/x/json-prudynt.cgi";
  const streamIds = [0, 1];

  const alertArea = $("#privacy-alerts");
  const contentWrap = $("#privacy-content");
  const reloadButton = $("#privacy-reload");
  const saveButton = $("#privacy-save");
  const form = $("#privacy-form");

  function toggleInitialLoading(active) {
    if (!contentWrap) return;
    if (active) {
      showBusy("Loading privacy settings...");
      contentWrap.classList.add("d-none");
    } else {
      hideBusy();
      contentWrap.classList.remove("d-none");
    }
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle("disabled", !!state);
  }

  async function persistPrudyntConfig() {
    const confirmed = await confirm(
      "Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.",
    );
    if (!confirmed) return false;
    if (saveButton) saveButton.disabled = true;
    try {
      const payload = { action: { save_config: null } };
      const response = await fetch(endpoint, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify(payload),
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data?.action || data.action.save_config !== "ok") {
        throw new Error("Save failed");
      }
      showAlert("success", "Configuration saved to /etc/prudynt.json.");
      return true;
    } catch (err) {
      showAlert(
        "danger",
        `Failed to save privacy settings: ${err.message || err}`,
      );
      return false;
    } finally {
      if (saveButton) saveButton.disabled = false;
    }
  }

  function disablePrivacyControls() {
    streamIds.forEach((streamId) => {
      ["enabled"].forEach((field) => {
        const el = $(`#privacy${streamId}_${field}`);
        if (el) el.disabled = true;
      });
    });
  }

  function buildRequestPayload() {
    return {
      stream0: { osd: { privacy: { enabled: null } } },
      stream1: { osd: { privacy: { enabled: null } } },
    };
  }

  async function requestPrudynt(payload) {
    const body =
      typeof payload === "string" ? payload : JSON.stringify(payload);
    const response = await fetch(endpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body,
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (err) {
      throw new Error("Invalid JSON from prudynt");
    }
  }

  function setPrivacyField(streamId, field, value) {
    const el = $(`#privacy${streamId}_${field}`);
    if (!el) return;
    el.disabled = false;
    if (el.type === "checkbox") {
      el.checked = Boolean(value);
    } else if (value === null || typeof value === "undefined") {
      el.value = "";
    } else {
      el.value = value;
    }
  }

  function applyPrivacyConfig(streamId, privacy = {}) {
    if (!privacy) return;
    if (Object.prototype.hasOwnProperty.call(privacy, "enabled")) {
      setPrivacyField(streamId, "enabled", privacy.enabled);
    }
  }

  async function loadPrivacyConfig(options = {}) {
    const { silent = false } = options;
    let success = false;
    if (!silent) {
      toggleInitialLoading(true);
    } else {
      setReloadBusy(true);
    }
    try {
      const data = await requestPrudynt(buildRequestPayload());
      const stream0 = data?.stream0?.osd?.privacy;
      const stream1 = data?.stream1?.osd?.privacy;
      applyPrivacyConfig(0, stream0);
      applyPrivacyConfig(1, stream1);
      success = true;
      return true;
    } catch (err) {
      showAlert(
        "danger",
        `Unable to load privacy settings: ${err.message || err}`,
      );
      return false;
    } finally {
      if (!silent) {
        toggleInitialLoading(false);
      } else {
        setReloadBusy(false);
        if (success) {
          showAlert("info", "Privacy settings reloaded from camera.", 3000);
        }
      }
    }
  }

  async function sendPrivacyUpdate(streamId, payload) {
    try {
      const body = {
        [`stream${streamId}`]: { osd: { privacy: payload } },
        action: { restart_thread: ThreadVideo | ThreadOSD },
      };
      const data = await requestPrudynt(body);
      const updated = data?.[`stream${streamId}`]?.osd?.privacy;
      if (updated) {
        applyPrivacyConfig(streamId, updated);
      }
    } catch (err) {
      showAlert(
        "danger",
        `Failed to update stream ${streamId} privacy: ${err.message || err}`,
      );
    }
  }

  function handleEnabledChange(streamId) {
    const el = $(`#privacy${streamId}_enabled`);
    if (!el) return;
    sendPrivacyUpdate(streamId, { enabled: el.checked });
  }

  function bindPrivacyControls() {
    streamIds.forEach((streamId) => {
      const el = $(`#privacy${streamId}_enabled`);
      if (el) {
        el.addEventListener("change", () =>
          handleEnabledChange(streamId),
        );
      }
    });
  }

  async function handleFormSubmit(event) {
    event.preventDefault();
    await persistPrudyntConfig();
  }

  function initPrivacyPage() {
    if (form) {
      form.addEventListener("submit", handleFormSubmit);
    }
    if (reloadButton) {
      reloadButton.addEventListener("click", () =>
        loadPrivacyConfig({ silent: true }),
      );
    }
    disablePrivacyControls();
    bindPrivacyControls();
    loadPrivacyConfig();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initPrivacyPage, {
      once: true,
    });
  } else {
    initPrivacyPage();
  }
})();
