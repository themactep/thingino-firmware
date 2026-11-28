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

  const BASE_MODES = ["CBR", "VBR", "FIXQP"];
  const SMART_MODES = ["SMART"];
  const CAPPED_MODES = ["CAPPED_VBR", "CAPPED_QUALITY"];
  // get-enc-caps has no H.265 flag, so formats come from the SoC family.
  const SOC_FORMATS = {
    t10: ["H264"],
    t20: ["H264"],
    t21: ["H264"],
    t23: ["H264"],
  };

  function populateSelect(selector, values, label) {
    $$(selector).forEach((select) => {
      const current = select.value;
      select.innerHTML = '<option value="">- Select -</option>';
      values.forEach((value) => {
        const option = document.createElement("option");
        option.value = value;
        option.textContent = label ? label(value) : value;
        select.appendChild(option);
      });
      if (values.includes(current)) select.value = current;
    });
  }

  function populateModeSelects(modes) {
    populateSelect("#stream0_mode, #stream1_mode", modes, (mode) =>
      mode.replace(/_/g, " "),
    );
  }

  // Every mode rvd parses goes in first so the loaded value is kept, then
  // the list is narrowed to what this SoC's encoder supports.
  async function populateEncoderSelects() {
    const soc = String(
      window.thinginoUIConfig?.device?.soc || "",
    ).toLowerCase();
    const family = (soc.match(/^(t\d+|c\d+)/) || [])[1];
    populateSelect(
      "#stream0_format, #stream1_format",
      SOC_FORMATS[family] || ["H264", "H265"],
    );
    populateModeSelects([...BASE_MODES, ...SMART_MODES, ...CAPPED_MODES]);
    if (!window.agentJsonRequest) return;
    try {
      const caps = await window.agentJsonRequest("/api/v1/runtime/encoder", {
        cache: "no-store",
      });
      populateModeSelects([
        ...BASE_MODES,
        ...(caps.smart_rc ? SMART_MODES : []),
        ...(caps.capped_rc ? CAPPED_MODES : []),
      ]);
    } catch (err) {
      console.warn("encoder capabilities unavailable:", err);
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    populateEncoderSelects();
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
