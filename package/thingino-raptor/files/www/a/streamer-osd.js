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

  // Other OSD elements: [osd.camera] (agent "usertext"), [osd.uptime] and
  // [osd.logo]. Each field is one agent setting leaf.
  const ELEMENTS = ["usertext", "uptime", "logo"];
  const elementField = (key, field) =>
    document.getElementById("osd_" + key + "_" + field);

  async function loadElements(helper, osd) {
    for (const key of ELEMENTS) {
      const cfg = osd[key] || {};
      const enabled = elementField(key, "enabled");
      const format = elementField(key, "format");
      const position = elementField(key, "position");
      if (enabled) enabled.checked = cfg.enabled === true;
      if (format && cfg.format) format.value = cfg.format;
      if (position && cfg.position) position.value = cfg.position;
      const maxChars = elementField(key, "max_chars");
      if (!maxChars) continue;
      try {
        const leaf = await helper.agentRequest(
          "/api/v1/settings/streams/0/osd/" + key + "/max-chars",
          { cache: "no-store" },
        );
        if (leaf && leaf.max_chars != null) maxChars.value = leaf.max_chars;
      } catch (err) {
        console.warn("Failed to load " + key + " max chars", err);
      }
    }
  }

  async function saveElements(helper) {
    for (const key of ELEMENTS) {
      const leaves = [];
      const enabled = elementField(key, "enabled");
      const format = elementField(key, "format");
      const position = elementField(key, "position");
      const maxChars = elementField(key, "max_chars");
      if (enabled) leaves.push(["enabled", "enabled", !!enabled.checked]);
      if (format && format.value.trim())
        leaves.push(["format", "format", format.value.trim()]);
      if (position && position.value.trim())
        leaves.push(["position", "position", position.value.trim()]);
      if (maxChars && Number(maxChars.value) > 0)
        leaves.push(["max-chars", "max_chars", Number(maxChars.value)]);
      for (const [path, field, value] of leaves) {
        await helper.agentRequest(
          "/api/v1/settings/streams/0/osd/" + key + "/" + path,
          { method: "PATCH", body: { [field]: value }, cache: "no-store" },
        );
      }
    }
  }

  // Each position input holds the value; a select in front of it offers the
  // named positions and reveals the input only for custom x,y coordinates.
  function positionSelects() {
    return document.querySelectorAll("select[data-position-for]");
  }

  function refreshPositionSelects() {
    positionSelects().forEach((select) => {
      const input = document.getElementById(select.dataset.positionFor);
      const value = input.value.trim();
      const named = [...select.options].some(
        (o) => o.value === value && o.value !== "custom",
      );
      select.value = named ? value : value ? "custom" : "";
      input.classList.toggle("d-none", select.value !== "custom");
    });
  }

  positionSelects().forEach((select) => {
    select.addEventListener("change", () => {
      const input = document.getElementById(select.dataset.positionFor);
      const custom = select.value === "custom";
      input.classList.toggle("d-none", !custom);
      if (custom) {
        if (/^[a-z_]+$/.test(input.value)) input.value = "";
        input.focus();
      } else {
        input.value = select.value;
      }
    });
  });

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
      await loadElements(helper, osd);
      refreshPositionSelects();
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
      await saveElements(helper);
      if (helper.saveConfig) await helper.saveConfig();
      showAlert(
        "success",
        "OSD configuration saved. Reboot the camera to apply it.",
        6000,
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
