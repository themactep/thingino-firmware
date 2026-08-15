(function () {
  "use strict";

  const fallbackEndpoint = "/x/json-prudynt.cgi";

  const reloadButton = $("#privacy-reload");
  const saveButton = $("#privacy-save");
  const form = $("#privacy-form");

  function preferAgent() {
    return typeof window.agentJsonRequest === "function";
  }

  async function agentRequest(path, options) {
    return window.agentJsonRequest(path, options);
  }

  function helper() {
    return window.thinginoStreamer || null;
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle("disabled", !!state);
  }

  async function requestFallback(payload) {
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

  async function saveConfigToFlash() {
    if (!saveButton) return;
    saveButton.disabled = true;
    try {
      const h = helper();
      if (h && h.saveConfig) {
        const confirmed = await confirm(
          (h.saveConfirmMessage && h.saveConfirmMessage()) ||
            "Save the current configuration?\n\nThis will overwrite the saved configuration file on the camera.",
        );
        if (!confirmed) return;
        await h.saveConfig();
        showAlert(
          "success",
          (h.saveSuccessMessage && h.saveSuccessMessage()) ||
            "Configuration saved.",
        );
        return;
      }
      if (preferAgent()) {
        const res = await fetch("/x/json-config-save.cgi", { method: "POST" });
        if (res.ok) {
          showAlert("success", "Configuration saved.");
          return;
        }
      }
      const resp = await requestFallback({ action: { save_config: null } });
      if (!resp?.action || resp.action.save_config !== "ok") {
        throw new Error("save_config returned unexpected response");
      }
      showAlert("success", "Configuration saved.");
    } catch (err) {
      showAlert(
        "danger",
        `Failed to save configuration: ${err.message || err}`,
      );
    } finally {
      saveButton.disabled = false;
    }
  }

  async function loadConfig() {
    setReloadBusy(true);
    try {
      const enabledEl = $("#privacy-enabled");
      const saveStateEl = $("#privacy-save-state");

      if (preferAgent()) {
        const cfg = await agentRequest("/api/v1/config", { cache: "no-store" });
        if (enabledEl) {
          if (cfg?.privacy?.enabled !== undefined) {
            enabledEl.checked = !!cfg.privacy.enabled;
          }
          enabledEl.disabled = false;
        }
        // save_state is not an agent leaf; hide when agent-backed.
        if (saveStateEl) {
          const wrap =
            saveStateEl.closest("p, .mb-3, .form-switch") ||
            saveStateEl.parentElement;
          if (wrap) wrap.classList.add("d-none");
          saveStateEl.disabled = true;
        }
        return;
      }

      const data = await requestFallback({
        privacy: {
          enabled: null,
          save_state: null,
        },
      });

      if (enabledEl) {
        if (data?.privacy?.enabled !== undefined) {
          enabledEl.checked = !!data.privacy.enabled;
        }
        enabledEl.disabled = false;
      }

      if (saveStateEl) {
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

  async function sendUpdate(field, checked) {
    try {
      if (preferAgent() && field === "enabled") {
        await agentRequest("/api/v1/actions/privacy", {
          method: "POST",
          body: { enabled: checked },
          cache: "no-store",
        });
        return;
      }
      await requestFallback({
        privacy: {
          [field]: checked,
        },
      });
    } catch (err) {
      showAlert(
        "danger",
        `Failed to update privacy.${field}: ${err.message || err}`,
      );
      const el = $(`#privacy-${field.replace(/_/g, "-")}`);
      if (el) el.checked = !checked;
    }
  }

  function bindControls() {
    const enabledEl = $("#privacy-enabled");
    if (enabledEl) {
      enabledEl.addEventListener("change", () =>
        sendUpdate("enabled", enabledEl.checked),
      );
    }

    const saveStateEl = $("#privacy-save-state");
    if (saveStateEl) {
      saveStateEl.addEventListener("change", () =>
        sendUpdate("save_state", saveStateEl.checked),
      );
    }

    if (form) {
      form.addEventListener("submit", (e) => {
        e.preventDefault();
        saveConfigToFlash();
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
