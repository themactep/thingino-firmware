(function () {
  "use strict";

  async function confirm(message) {
    return window.confirm(message);
  }

  function showAlert(type, message, duration) {
    if (window.showAlert && typeof window.showAlert === "function") {
      window.showAlert(type, message, duration);
      return;
    }
    const alertWrapper = document.createElement("div");
    alertWrapper.className =
      "position-fixed top-0 start-50 translate-middle-x p-3";
    alertWrapper.style.zIndex = "9999";
    const alertEl = document.createElement("div");
    alertEl.className = `alert alert-${type} alert-dismissible fade show`;
    alertEl.setAttribute("role", "alert");
    alertEl.innerHTML = `${message}<button type="button" class="btn-close" data-bs-dismiss="alert" aria-label="Close"></button>`;
    alertWrapper.appendChild(alertEl);
    document.body.appendChild(alertWrapper);
    if (duration) setTimeout(() => alertWrapper.remove(), duration);
  }

  async function saveStreamerConfig() {
    const api = window.thinginoStreamer;
    const confirmed = await confirm(
      (api && api.saveConfirmMessage && api.saveConfirmMessage()) ||
        "Save the current streamer configuration?\n\nThis will overwrite the saved configuration file on the camera.",
    );
    if (!confirmed) return;

    const saveButton = $("#save-config");
    if (saveButton) saveButton.disabled = true;

    try {
      if (api && api.saveConfig) {
        await api.saveConfig();
        showAlert(
          "success",
          (api.saveSuccessMessage && api.saveSuccessMessage()) ||
            "Configuration saved successfully",
          4000,
        );
      } else {
        throw new Error("Streamer save helper unavailable");
      }
    } catch (err) {
      console.error("Failed to save config:", err);
      showAlert("danger", "Failed to save configuration: " + err.message, 6000);
    } finally {
      if (saveButton) saveButton.disabled = false;
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    const saveButton = $("#save-config");
    if (saveButton) {
      saveButton.addEventListener("click", saveStreamerConfig);
    }
    const api = window.thinginoStreamer;
    if (api && api.hideUnsupportedControls) {
      api.hideUnsupportedControls(document);
    }
  });
})();
