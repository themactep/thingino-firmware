/**
 * Agent-backed OSD page for raptor (ROD timestamp burn-in).
 */
(function () {
  "use strict";

  const burninEnabled = document.getElementById("burnin_enabled");
  const burninFormat = document.getElementById("burnin_format");
  const burninFontSize = document.getElementById("burnin_font_size");
  const burninPosition = document.getElementById("burnin_position");
  const burninFillColor = document.getElementById("burnin_fill_color");
  const burninOutlineColor = document.getElementById("burnin_outline_color");
  const swatchFill = document.getElementById("swatch_fill");
  const swatchOutline = document.getElementById("swatch_outline");
  const pickerFill = document.getElementById("picker_fill");
  const pickerOutline = document.getElementById("picker_outline");
  const alphaFill = document.getElementById("alpha_fill");
  const alphaOutline = document.getElementById("alpha_outline");
  const saveBtn = document.getElementById("save-osd-config");

  function updateSwatch(input, swatch) {
    let v = (input.value || "").trim();
    if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
      if (v[0] !== "#") v = "#" + v;
      const r = parseInt(v.substring(1, 3), 16);
      const g = parseInt(v.substring(3, 5), 16);
      const b = parseInt(v.substring(5, 7), 16);
      const a = parseInt(v.substring(7, 9), 16) / 255;
      swatch.style.backgroundColor =
        "rgba(" + r + "," + g + "," + b + "," + a + ")";
    } else {
      swatch.style.backgroundColor = "";
    }
  }

  function wireColor(swatch, picker, input, alphaSlider) {
    swatch.addEventListener("click", function () {
      picker.click();
    });
    picker.addEventListener("input", function () {
      let cur = input.value.trim();
      let alpha = "ff";
      if (cur && /^#?[0-9a-fA-F]{8}$/.test(cur)) {
        if (cur[0] !== "#") cur = "#" + cur;
        alpha = cur.substring(7, 9);
      }
      input.value = picker.value + alpha;
      updateSwatch(input, swatch);
    });
    input.addEventListener("input", function () {
      updateSwatch(input, swatch);
      let v = input.value.trim();
      if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
        if (v[0] !== "#") v = "#" + v;
        alphaSlider.value = parseInt(v.substring(7, 9), 16);
      }
    });
    alphaSlider.addEventListener("input", function () {
      let v = input.value.trim();
      if (!v || !/^#?[0-9a-fA-F]{8}$/.test(v)) {
        v = "#ffffffff";
      } else if (v[0] !== "#") {
        v = "#" + v;
      }
      const alpha = ("0" + parseInt(alphaSlider.value, 10).toString(16)).slice(
        -2,
      );
      input.value = v.substring(0, 7) + alpha;
      updateSwatch(input, swatch);
    });
  }

  function syncAlphaFromInput(input, alphaSlider) {
    let v = (input.value || "").trim();
    if (v && /^#?[0-9a-fA-F]{8}$/.test(v)) {
      if (v[0] !== "#") v = "#" + v;
      alphaSlider.value = parseInt(v.substring(7, 9), 16);
    }
  }

  function showAlert(type, message, duration) {
    if (window.showAlert) {
      window.showAlert(type, message, duration);
      return;
    }
    alert(message);
  }

  async function loadOsdConfig() {
    const helper = window.thinginoStreamer;
    if (!helper || !helper.agentRequest) return;
    try {
      const cfg = await helper.agentRequest("/api/v1/config", {
        cache: "no-store",
      });
      const stream0 = (cfg && cfg.streams && cfg.streams[0]) || {};
      const osd = stream0.osd || {};
      const time = osd.time || {};

      burninEnabled.checked = time.enabled === true || osd.enabled === true;
      if (time.format) burninFormat.value = time.format;
      if (osd.font_size != null) burninFontSize.value = osd.font_size;
      if (time.position) burninPosition.value = time.position;
      burninFillColor.value = time.fill_color || "#ffffffff";
      burninOutlineColor.value = time.stroke_color || "#000000ff";
      updateSwatch(burninFillColor, swatchFill);
      updateSwatch(burninOutlineColor, swatchOutline);
      syncAlphaFromInput(burninFillColor, alphaFill);
      syncAlphaFromInput(burninOutlineColor, alphaOutline);
    } catch (err) {
      console.warn("Failed to load OSD config", err);
    }
  }

  async function saveOsdConfig() {
    const helper = window.thinginoStreamer;
    if (!helper || !helper.applyPayload) {
      showAlert("danger", "Streamer agent helper unavailable", 6000);
      return;
    }
    const confirmed = await window.confirm(
      (helper.saveConfirmMessage && helper.saveConfirmMessage()) ||
        "Save the current OSD configuration to /etc/raptor.conf?",
    );
    if (!confirmed) return;

    saveBtn.disabled = true;
    try {
      const time = {
        enabled: !!burninEnabled.checked,
      };
      if (burninFormat.value.trim()) time.format = burninFormat.value.trim();
      if (burninPosition.value.trim())
        time.position = burninPosition.value.trim();
      if (burninFillColor.value.trim())
        time.fill_color = burninFillColor.value.trim();
      if (burninOutlineColor.value.trim())
        time.stroke_color = burninOutlineColor.value.trim();

      const osd = { enabled: !!burninEnabled.checked, time };
      const fontSize = Number(burninFontSize.value);
      if (Number.isFinite(fontSize) && fontSize > 0) {
        osd.font_size = fontSize;
      }

      await helper.applyPayload({ stream0: { osd } });
      if (helper.saveConfig) await helper.saveConfig();
      showAlert(
        "success",
        (helper.saveSuccessMessage && helper.saveSuccessMessage()) ||
          "OSD configuration saved",
        4000,
      );
    } catch (err) {
      console.error("Failed to save OSD config", err);
      showAlert("danger", "Failed to save OSD: " + err.message, 6000);
    } finally {
      saveBtn.disabled = false;
    }
  }

  wireColor(swatchFill, pickerFill, burninFillColor, alphaFill);
  wireColor(swatchOutline, pickerOutline, burninOutlineColor, alphaOutline);
  saveBtn.addEventListener("click", saveOsdConfig);
  loadOsdConfig();
})();
