(function () {
  "use strict";

  const motorsConfigEndpoint = "/x/json-motors-config.cgi";
  const alertContainer = $("#motors-alerts");
  const contentWrap = $("#motors-content");
  const form = $("#motors-form");
  const reloadButton = $("#motors-reload");
  const submitButton = form
    ? form.querySelector('button[type="submit"]')
    : null;
  const submitSpinner = submitButton
    ? submitButton.querySelector(".spinner-border")
    : null;
  const submitLabel = submitButton
    ? submitButton.querySelector(".label")
    : null;
  const submitDefaultText = submitLabel
    ? submitLabel.textContent
    : "Save motors";
  const typeBadge = $("#motors-type-badge");
  let initialLoadComplete = false;
  let motorIsSpi = false;

  function normalizeMotionDriver(value) {
    return value === "profiled" ? "profiled" : "legacy";
  }

  function normalizePreviewControlMode(value) {
    return value === "continuous" ? "continuous" : "step";
  }

  function updateMotionDriverInputs() {
    const motionDriverEl = $("#motion_driver");
    const accelWrap = $("#motion-accel-fields");
    const help = $("#motion-driver-help");
    const accelPan = $("#accel_pan");
    const accelTilt = $("#accel_tilt");
    if (!motionDriverEl) return;

    const mode = normalizeMotionDriver(motionDriverEl.value);
    const profiled = mode === "profiled";

    if (accelWrap) {
      accelWrap.classList.toggle("opacity-50", !profiled);
    }
    if (accelPan) {
      accelPan.disabled = !profiled;
      if (!profiled) accelPan.value = "0";
    }
    if (accelTilt) {
      accelTilt.disabled = !profiled;
      if (!profiled) accelTilt.value = "0";
    }
    if (help) {
      if (profiled) {
        help.className = "alert alert-info small mb-2";
        help.textContent =
          "Profiled mode active: acceleration fields control ramping in motors-daemon.";
      } else {
        help.className = "alert alert-secondary small mb-2";
        help.textContent =
          "Legacy mode active: acceleration values are ignored and saved as 0.";
      }
    }
  }

  function showAlert(variant, message, timeout = 6000) {
    if (!message) return;

    // Use global alert system from main.js
    if (window.showAlert && typeof window.showAlert === "function") {
      window.showAlert(variant, message, timeout);
      return;
    }

    // Fallback to local alert container if it exists
    if (!alertContainer) return;
    const alert = document.createElement("div");
    alert.className = `alert alert-${variant || "secondary"} alert-dismissible fade show`;
    alert.setAttribute("role", "alert");
    alert.innerHTML = message;
    const dismissBtn = document.createElement("button");
    dismissBtn.type = "button";
    dismissBtn.className = "btn-close";
    dismissBtn.setAttribute("aria-label", "Close");
    dismissBtn.addEventListener("click", () => alert.remove());
    alert.appendChild(dismissBtn);
    alertContainer.appendChild(alert);
    if (timeout > 0) {
      setTimeout(() => {
        alert.classList.remove("show");
        setTimeout(() => alert.remove(), 200);
      }, timeout);
    }
  }

  function parseMotorPins(raw) {
    if (typeof raw !== "string") return [];
    return raw.trim().split(/\s+/).filter(Boolean);
  }

  function setMotorPins(prefix, pins) {
    if (!Array.isArray(pins)) return;
    for (let i = 1; i <= 4; i += 1) {
      const input = $(`#gpio_${prefix}_${i}`);
      if (input) input.value = pins[i - 1] || "";
    }
  }

  function setMotorFieldValue(id, value) {
    const input = $(`#${id}`);
    if (!input) return;
    input.value = value === undefined || value === null ? "" : value;
  }

  function setMotorPinInputsEnabled(enabled) {
    const disablePins = !enabled;
    $$('#motors-form input[id^="gpio_"]').forEach((input) => {
      input.disabled = disablePins;
    });
    $$(".flip_motor").forEach((btn) => {
      btn.disabled = disablePins;
      btn.classList.toggle("disabled", disablePins);
    });
  }

  function updateBadge(isSpi) {
    if (!typeBadge) return;
    if (isSpi) {
      typeBadge.textContent = "SPI motor board";
      typeBadge.className = "badge text-bg-info";
      typeBadge.title = "Pins are controlled over SPI, GPIO inputs disabled";
    } else {
      typeBadge.textContent = "Discrete GPIO driver";
      typeBadge.className = "badge text-bg-dark";
      typeBadge.title = "Pins driven directly via GPIO";
    }
  }

  function updateHomingInputs() {
    const homing = $("#homing");
    const x = $("#pos_0_x");
    const y = $("#pos_0_y");
    if (!homing) return;
    const disabled = !homing.checked;
    if (x) x.disabled = disabled;
    if (y) y.disabled = disabled;
  }

  function applyMotorsConfig(config = {}) {
    if (typeof config !== "object" || !config) return;
    setMotorPins("pan", parseMotorPins(config.gpio_pan));
    setMotorPins("tilt", parseMotorPins(config.gpio_tilt));
    setMotorFieldValue("steps_pan", config.steps_pan);
    setMotorFieldValue("steps_tilt", config.steps_tilt);
    setMotorFieldValue("speed_pan", config.speed_pan);
    setMotorFieldValue("speed_tilt", config.speed_tilt);
    setMotorFieldValue("accel_pan", config.accel_pan);
    setMotorFieldValue("accel_tilt", config.accel_tilt);
    const motionDriverEl = $("#motion_driver");
    if (motionDriverEl) {
      const mode = normalizeMotionDriver(config.motion_driver);
      motionDriverEl.value = mode;
    }
    const previewControlModeEl = $("#preview_control_mode");
    if (previewControlModeEl) {
      previewControlModeEl.value = normalizePreviewControlMode(
        config.preview_control_mode,
      );
    }
    const homingEl = $("#homing");
    if (homingEl) {
      homingEl.checked = config.homing === true || config.homing === "true";
    }
    const firstPreset =
      Array.isArray(config.presets) && config.presets.length
        ? config.presets[0]
        : null;
    setMotorFieldValue("pos_0_x", firstPreset ? firstPreset.x : "");
    setMotorFieldValue("pos_0_y", firstPreset ? firstPreset.y : "");
    updateHomingInputs();
    motorIsSpi = config.is_spi === true || config.is_spi === "true";
    setMotorPinInputsEnabled(!motorIsSpi);
    updateBadge(motorIsSpi);
    updateMotionDriverInputs();
  }

  async function loadMotorsConfig(options = {}) {
    const { silent = false } = options;
    if (!silent) showBusy("Loading motor settings...");
    try {
      const response = await fetch(motorsConfigEndpoint, {
        headers: { Accept: "application/json" },
        cache: "no-store",
      });
      let payload = null;
      try {
        payload = await response.json();
      } catch (parseErr) {
        console.error("JSON parse error:", parseErr);
        payload = null;
      }
      if (!response.ok || !payload || payload.result !== "success") {
        const message = payload && payload.error && payload.error.message;
        throw new Error(message || `HTTP ${response.status}`);
      }
      try {
        applyMotorsConfig(payload.message || {});
      } catch (applyErr) {
        console.error("applyMotorsConfig error:", applyErr);
        throw applyErr;
      }
      if (!initialLoadComplete) {
        if (contentWrap) contentWrap.classList.remove("d-none");
        initialLoadComplete = true;
      }
      return true;
    } catch (err) {
      console.error("Failed to load motors config", err);
      showAlert(
        "danger",
        `Unable to load motor settings: ${err.message || err}`,
      );
      return false;
    } finally {
      if (!silent) hideBusy();
    }
  }

  async function saveMotorsConfig() {
    const form = $("#motors-form");
    if (!form) return;

    // Client-side validation to prevent 412 errors
    const requiredPanFields = [
      "gpio_pan_1",
      "gpio_pan_2",
      "gpio_pan_3",
      "gpio_pan_4",
    ];
    const requiredTiltFields = [
      "gpio_tilt_1",
      "gpio_tilt_2",
      "gpio_tilt_3",
      "gpio_tilt_4",
    ];

    const formData = new FormData(form);
    const errors = [];

    // Check GPIO fields (skip for SPI motor boards where pins are irrelevant)
    if (!motorIsSpi) {
      for (const field of requiredPanFields) {
        const value = formData.get(field);
        if (!value || value.trim() === "") {
          errors.push(
            `${field.replace(/_/g, " ").replace(/\b\w/g, (l) => l.toUpperCase())} is required`,
          );
        }
      }

      // Detect whether the tilt axis is present: all GPIOs set to -1
      // means the hardware has no tilt motor and tilt validation should
      // be skipped entirely.
      const tiltGpioValues = requiredTiltFields.map((f) =>
        (formData.get(f) || "").trim(),
      );
      const tiltDisabled = tiltGpioValues.every((v) => v === "-1");

      if (!tiltDisabled) {
        for (const field of requiredTiltFields) {
          const value = formData.get(field);
          if (!value || value.trim() === "") {
            errors.push(
              `${field.replace(/_/g, " ").replace(/\b\w/g, (l) => l.toUpperCase())} is required`,
            );
          }
        }
      }
    }

    // Check steps fields
    const stepsPan = formData.get("steps_pan");
    const stepsTilt = formData.get("steps_tilt");
    if (!stepsPan || parseInt(stepsPan) <= 0) {
      errors.push("Pan max steps must be a positive number");
    }

    // Skip tilt steps validation when the tilt axis is disabled (all GPIOs -1).
    // Pan-only cameras legitimately have steps_tilt = 0.
    const tiltGpioVals = requiredTiltFields.map((f) =>
      (formData.get(f) || "").trim(),
    );
    const tiltAxisMissing = tiltGpioVals.every((v) => v === "-1");
    if (!tiltAxisMissing && (!stepsTilt || parseInt(stepsTilt) <= 0)) {
      errors.push("Tilt max steps must be a positive number");
    }

    const accelPan = formData.get("accel_pan");
    const accelTilt = formData.get("accel_tilt");
    if (accelPan !== null && accelPan !== "" && parseInt(accelPan) < 0) {
      errors.push("Pan acceleration must be zero or positive");
    }
    if (accelTilt !== null && accelTilt !== "" && parseInt(accelTilt) < 0) {
      errors.push("Tilt acceleration must be zero or positive");
    }

    const motionDriver = formData.get("motion_driver");
    if (motionDriver !== "legacy" && motionDriver !== "profiled") {
      errors.push("Motion driver must be legacy or profiled");
    }

    const previewControlMode = formData.get("preview_control_mode");
    if (previewControlMode !== "step" && previewControlMode !== "continuous") {
      errors.push("Preview PTZ controls must be step or continuous");
    }

    if (motionDriver !== "profiled") {
      formData.set("accel_pan", "0");
      formData.set("accel_tilt", "0");
    }

    if (errors.length > 0) {
      showAlert("danger", "Please fix the following errors:", 0);
      errors.forEach((err) => showAlert("warning", err, 0));
      return;
    }

    showBusy("Saving motor settings...");
    try {
      const homingEl = $("#homing");
      const params = new URLSearchParams();
      params.append("form", "motors");
      params.append("homing", homingEl && homingEl.checked ? "true" : "false");
      formData.forEach((value, key) => {
        if (key !== "form" && key !== "homing") {
          params.append(key, value == null ? "" : value);
        }
      });
      const response = await fetch(motorsConfigEndpoint, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: params.toString(),
        cache: "no-store",
      });
      let payload = null;
      try {
        payload = await response.json();
      } catch (_) {
        payload = null;
      }
      if (!response.ok || !payload || payload.result !== "success") {
        const message = payload && payload.error && payload.error.message;
        throw new Error(message || `HTTP ${response.status}`);
      }
      applyMotorsConfig(payload.message || {});
      showAlert("success", "Motor settings updated.");
    } catch (err) {
      console.error("Failed to save motors config", err);
      showAlert(
        "danger",
        `Failed to save motor settings: ${err.message || err}`,
      );
    } finally {
      hideBusy();
    }
  }

  async function readMotorsPosition() {
    try {
      const res = await fetch(
        "/x/json-motor.cgi?" + new URLSearchParams({ d: "j" }).toString(),
      );
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const { message } = await res.json();
      if (message) {
        if ($("#pos_0_x")) $("#pos_0_x").value = message.xpos;
        if ($("#pos_0_y")) $("#pos_0_y").value = message.ypos;
      }
      if ($("#homing")) $("#homing").checked = true;
      updateHomingInputs();
      showAlert("success", "Captured current position as new reference.", 4000);
    } catch (err) {
      console.error("Failed to read motors position", err);
      showAlert(
        "danger",
        `Unable to read current position: ${err.message || err}`,
      );
    }
  }

  if (form) {
    form.addEventListener("submit", (ev) => {
      ev.preventDefault();
      saveMotorsConfig();
    });
  }

  if (reloadButton) {
    reloadButton.addEventListener("click", async () => {
      try {
        reloadButton.disabled = true;
        const success = await loadMotorsConfig({ silent: true });
        if (success) {
          showAlert("info", "Motor settings reloaded from camera.", 3000);
        }
      } catch (err) {
        showAlert("danger", "Failed to reload motors settings.");
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  $$(".flip_motor").forEach((el) => {
    el.addEventListener("click", (ev) => {
      ev.preventDefault();
      const dir = el.dataset.direction;
      if (!dir) return;
      const base = "#gpio_" + dir + "_";
      const pins = [1, 2, 3, 4].map((i) => $(base + i)?.value).reverse();
      [1, 2, 3, 4].forEach((i, idx) => {
        const field = $(base + i);
        if (field && pins[idx] !== undefined) field.value = pins[idx];
      });
    });
  });

  $$(".read-motors").forEach((el) => {
    el.addEventListener("click", (ev) => {
      ev.preventDefault();
      readMotorsPosition();
    });
  });

  const homingSwitch = $("#homing");
  if (homingSwitch) {
    homingSwitch.addEventListener("change", updateHomingInputs);
    updateHomingInputs();
  }

  const motionDriverSelect = $("#motion_driver");
  if (motionDriverSelect) {
    motionDriverSelect.addEventListener("change", updateMotionDriverInputs);
  }

  // ------------------------------------------------------------------
  // PTZ presets
  // ------------------------------------------------------------------
  const presetNameInput = $("#ptz-preset-name");
  const presetSaveButton = $("#ptz-preset-save");
  const presetsList = $("#ptz-presets-list");
  const presetsEmpty = $("#ptz-presets-empty");

  function renderPresets(presets) {
    if (!presetsList) return;
    presetsList.innerHTML = "";
    if (presetsEmpty) {
      presetsEmpty.classList.toggle("d-none", presets.length > 0);
    }
    presets.forEach((p) => {
      const li = document.createElement("li");
      li.className = "list-group-item d-flex align-items-center gap-2";

      const nameInput = document.createElement("input");
      nameInput.type = "text";
      nameInput.className = "form-control form-control-sm flex-grow-1 preset-name";
      nameInput.value = p.description || "";
      nameInput.maxLength = 64;
      nameInput.placeholder = `Preset ${p.id}`;

      const xInput = document.createElement("input");
      xInput.type = "number";
      xInput.className = "form-control form-control-sm preset-x";
      xInput.style.width = "4.5rem";
      xInput.value = p.x;
      xInput.min = "0";

      const yInput = document.createElement("input");
      yInput.type = "number";
      yInput.className = "form-control form-control-sm preset-y";
      yInput.style.width = "4.5rem";
      yInput.value = p.y;
      yInput.min = "0";

      const saveBtn = document.createElement("button");
      saveBtn.type = "button";
      saveBtn.className = "btn btn-sm btn-outline-success";
      saveBtn.title = "Save description and coordinates";
      saveBtn.innerHTML = '<i class="bi bi-check-lg"></i>';
      saveBtn.addEventListener("click", () => {
        const description = nameInput.value.trim();
        if (!description) {
          showAlert("warning", "Enter a description for the preset.", 3000);
          return;
        }
        const x = xInput.value.trim();
        const y = yInput.value.trim();
        if (!/^\d+$/.test(x) || !/^\d+$/.test(y)) {
          showAlert("warning", "Coordinates must be whole numbers.", 3000);
          return;
        }
        presetAction("pu", { n: p.id, description, x, y });
      });

      const moveBtn = document.createElement("button");
      moveBtn.type = "button";
      moveBtn.className = "btn btn-sm btn-outline-primary";
      moveBtn.title = "Move to this preset";
      moveBtn.innerHTML = '<i class="bi bi-play-fill"></i>';
      moveBtn.addEventListener("click", () => presetAction("pr", { n: p.id }));

      const delBtn = document.createElement("button");
      delBtn.type = "button";
      delBtn.className = "btn btn-sm btn-outline-danger";
      delBtn.title = "Delete preset";
      delBtn.innerHTML = '<i class="bi bi-trash"></i>';
      delBtn.addEventListener("click", () => presetAction("pd", { n: p.id }));

      li.append(nameInput, xInput, yInput, saveBtn, moveBtn, delBtn);
      presetsList.appendChild(li);
    });
  }

  async function loadPresets() {
    try {
      const res = await fetch(
        "/x/json-motor.cgi?" + new URLSearchParams({ d: "pg" }).toString(),
      );
      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const payload = await res.json().catch(() => null);
      if (!payload || payload.result !== "success") {
        throw new Error(
          (payload && payload.error && payload.error.message) ||
            "Failed to load presets",
        );
      }
      renderPresets(
        payload.message && Array.isArray(payload.message.presets)
          ? payload.message.presets
          : [],
      );
    } catch (err) {
      console.error("Failed to load PTZ presets", err);
    }
  }

  async function presetAction(action, extra) {
    try {
      const params = new URLSearchParams({ d: action });
      Object.entries(extra || {}).forEach(([k, v]) => params.set(k, v));
      const res = await fetch("/x/json-motor.cgi?" + params.toString());
      const payload = await res.json().catch(() => null);
      if (!res.ok || !payload || payload.result !== "success") {
        const message = payload && payload.error && payload.error.message;
        throw new Error(message || `HTTP ${res.status}`);
      }
      const status =
        (payload.message && payload.message.status) || "OK";
      showAlert("success", status, 3000);
      await loadPresets();
    } catch (err) {
      console.error(`Preset action ${action} failed`, err);
      showAlert(
        "danger",
        `Preset action failed: ${err.message || err}`,
      );
    }
  }

  if (presetSaveButton) {
    presetSaveButton.addEventListener("click", async () => {
      const description = (presetNameInput ? presetNameInput.value : "").trim();
      if (!description) {
        showAlert("warning", "Enter a description for the preset first.", 3000);
        return;
      }
      await presetAction("ps", { description });
      if (presetNameInput) presetNameInput.value = "";
    });
  }

  loadPresets();

  loadMotorsConfig();
})();
