(function () {
  "use strict";

  const endpoint = "/x/json-prudynt.cgi";

  const alertArea = $("#privacy-alerts");
  const reloadButton = $("#privacy-reload");
  const saveButton = $("#privacy-save");
  const form = $("#privacy-form");

  /* ── Busy-state helpers ─────────────────────────────────────── */

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle("disabled", !!state);
  }

  /* ── JSON API helpers ────────────────────────────────────────── */

  async function requestPrudynt(payload) {
    const response = await fetch(endpoint, {
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
      throw new Error("Invalid JSON from prudynt");
    }
  }

  /* ── Persist config to flash ────────────────────────────────── */

  async function saveConfigToFlash() {
    if (!saveButton) return;
    saveButton.disabled = true;
    try {
      const resp = await requestPrudynt({ action: { save_config: null } });
      if (!resp?.action || resp.action.save_config !== "ok") {
        throw new Error("save_config returned unexpected response");
      }
      showAlert("success", "Configuration saved to /etc/prudynt.json.");
    } catch (err) {
      showAlert(
        "danger",
        `Failed to save configuration: ${err.message || err}`,
      );
    } finally {
      saveButton.disabled = false;
    }
  }

  /* ── Load & populate form ───────────────────────────────────── */

  async function loadConfig() {
    setReloadBusy(true);
    try {
      const data = await requestPrudynt({
        privacy: {
          enabled: null,
          save_state: null,
        },
      });

      // privacy.enabled
      const enabledEl = $("#privacy-enabled");
      if (enabledEl) {
        if (data?.privacy?.enabled !== undefined) {
          enabledEl.checked = !!data.privacy.enabled;
        }
        enabledEl.disabled = false;
      }

      // privacy.save_state
      const saveStateEl = $("#privacy-save-state");
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

  /* ── Live-update toggles ────────────────────────────────────── */

  function sendUpdate(field, checked) {
    requestPrudynt({
      privacy: {
        [field]: checked,
      },
    }).catch((err) => {
      showAlert(
        "danger",
        `Failed to update privacy.${field}: ${err.message || err}`,
      );
      // Revert the toggle on failure
      const el = $(`#privacy-${field.replace(/_/g, "-")}`);
      if (el) el.checked = !checked;
    });
  }

  /* ── Event wiring ───────────────────────────────────────────── */

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

  /* ── Init ───────────────────────────────────────────────────── */

  function init() {
    // Disable toggles until config is loaded
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
