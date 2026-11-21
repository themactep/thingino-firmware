(function () {
  "use strict";

  const fallbackEndpoint = "/x/json-prudynt.cgi";
  const startupPath = "/api/v1/settings/privacy/enabled";

  const reloadButton = $("#privacy-reload");
  const saveButton = $("#privacy-save");
  const form = $("#privacy-form");

  function agentEnabled() {
    const ui = window.thinginoUIConfig;
    return !!(ui && ui.device && ui.device.agent);
  }

  function preferAgent() {
    const h = window.thinginoStreamer || null;
    if (h && typeof h.preferAgent === "function") {
      return h.preferAgent();
    }
    return agentEnabled();
  }

  function agentRequest(path, options) {
    return window.agentJsonRequest(path, options);
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle("disabled", !!state);
  }

  async function requestPrudynt(payload) {
    const response = await fetch(fallbackEndpoint, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (err) {
      throw new Error("Invalid JSON from streamer");
    }
  }

  // Both switches are saved config, not the live cover: changing them must
  // not engage or lift privacy.
  async function readStartup() {
    if (preferAgent()) {
      const data = await agentRequest(startupPath, { cache: "no-store" });
      return data && data.enabled !== undefined ? !!data.enabled : undefined;
    }
    const data = await requestPrudynt({ privacy: { startup: null } });
    return data?.privacy?.startup;
  }

  async function writeStartup(checked) {
    if (preferAgent()) {
      await agentRequest(startupPath, {
        method: "PATCH",
        body: { enabled: checked },
        cache: "no-store",
      });
      return;
    }
    const data = await requestPrudynt({ privacy: { startup: checked } });
    if (data?.privacy?.startup !== checked) {
      throw new Error("streamer kept a different startup value");
    }
  }

  async function writeSaveState(checked) {
    const data = await requestPrudynt({ privacy: { save_state: checked } });
    if (data?.privacy?.save_state !== checked) {
      throw new Error("streamer kept a different runtime-state value");
    }
  }

  async function loadConfig() {
    setReloadBusy(true);
    try {
      const enabledEl = $("#privacy-enabled");
      if (enabledEl) {
        const startup = await readStartup();
        if (startup !== undefined) enabledEl.checked = !!startup;
        enabledEl.disabled = false;
      }

      const saveStateEl = $("#privacy-save-state");
      if (saveStateEl) {
        const data = await requestPrudynt({ privacy: { save_state: null } });
        if (data?.privacy?.save_state !== undefined) {
          saveStateEl.checked = !!data.privacy.save_state;
        }
        saveStateEl.disabled = false;
      }
    } catch (err) {
      showAlert(
        "danger",
        `Unable to load privacy settings: ${err.message || err}`,
      );
    } finally {
      setReloadBusy(false);
    }
  }

  async function saveConfig() {
    const enabledEl = $("#privacy-enabled");
    const saveStateEl = $("#privacy-save-state");
    if (!saveButton || !enabledEl || !saveStateEl) return;
    saveButton.disabled = true;
    try {
      await writeStartup(enabledEl.checked);
      await writeSaveState(saveStateEl.checked);
      showAlert("success", "Privacy settings saved.");
    } catch (err) {
      showAlert(
        "danger",
        `Failed to save privacy settings: ${err.message || err}`,
      );
    } finally {
      saveButton.disabled = false;
    }
  }

  function bindControls() {
    if (form) {
      form.addEventListener("submit", (e) => {
        e.preventDefault();
        saveConfig();
      });
    }

    if (reloadButton) {
      reloadButton.addEventListener("click", loadConfig);
    }
  }

  function init() {
    const enabledEl = $("#privacy-enabled");
    if (enabledEl) enabledEl.disabled = true;

    const saveStateEl = $("#privacy-save-state");
    if (saveStateEl) saveStateEl.disabled = true;

    bindControls();
    loadConfig();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
