(function () {
  const API = "/x/json-config-floodlight.cgi";

  function $(sel) {
    return document.querySelector(sel);
  }

  async function apiFetch(body) {
    const opts = { headers: { Accept: "application/json" } };
    if (body) {
      opts.method = "POST";
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(API, opts);
    const data = await res.json();
    if (data.error) throw new Error(data.error.message);
    return data;
  }

  function showMsg(text, type, timeout) {
    if (typeof showAlert === "function") {
      showAlert(type, text, timeout);
      return;
    }
    const el = $("#floodlight-msg");
    if (!el) return;
    el.className = "alert alert-" + type + " mt-2";
    el.textContent = text;
    el.hidden = false;
    if (timeout) setTimeout(() => (el.hidden = true), timeout);
  }

  const stateSwitch = $("#floodlight-switch");
  const brightness = $("#floodlight-brightness");
  const brightnessValue = $("#floodlight-brightness-value");
  const motionEnabled = $("#motion-enabled");
  const motionDuration = $("#motion-duration");
  const motionDurationValue = $("#motion-duration-value");

  function durationLabel(seconds) {
    return seconds + (seconds === 1 ? " second" : " seconds");
  }

  function setAvailable(available) {
    stateSwitch.disabled = !available;
    brightness.disabled = !available;
    motionEnabled.disabled = !available;
    motionDuration.disabled = !available;
  }

  function render(data) {
    setAvailable(data.available === true);
    if (data.available !== true) {
      showMsg("Floodlight controller is not available.", "warning");
      return;
    }
    stateSwitch.checked = data.state === "ON";
    brightness.value = String(data.brightness);
    brightnessValue.textContent = data.brightness + "%";
    motionEnabled.checked = data.motion_enabled === true;
    motionDuration.value = String(data.motion_duration);
    motionDurationValue.textContent = durationLabel(data.motion_duration);
  }

  async function loadConfig() {
    try {
      render(await apiFetch());
    } catch (err) {
      showMsg("Failed to load floodlight config: " + err.message, "danger");
    }
  }

  async function setState(on) {
    try {
      render(await apiFetch({ action: on ? "on" : "off" }));
      showMsg(on ? "Floodlight on." : "Floodlight off.", "success", 3000);
    } catch (err) {
      showMsg("Command failed: " + err.message, "danger");
      loadConfig();
    }
  }

  async function setBrightness(value) {
    try {
      render(await apiFetch({ action: "set-brightness", brightness: Number(value) }));
    } catch (err) {
      showMsg("Failed to save brightness: " + err.message, "danger");
      loadConfig();
    }
  }

  async function setMotion(enabled, duration) {
    try {
      render(await apiFetch({ action: "set-motion", enabled: enabled, duration: Number(duration) }));
      showMsg("Motion activation saved.", "success", 3000);
    } catch (err) {
      showMsg("Failed to save motion settings: " + err.message, "danger");
      loadConfig();
    }
  }

  stateSwitch.addEventListener("change", function () {
    setState(this.checked);
  });
  brightness.addEventListener("input", function () {
    brightnessValue.textContent = this.value + "%";
  });
  brightness.addEventListener("change", function () {
    setBrightness(this.value);
  });
  motionEnabled.addEventListener("change", function () {
    setMotion(this.checked, motionDuration.value);
  });
  motionDuration.addEventListener("input", function () {
    motionDurationValue.textContent = durationLabel(Number(this.value));
  });
  motionDuration.addEventListener("change", function () {
    setMotion(motionEnabled.checked, this.value);
  });

  $("#reload-btn").addEventListener("click", function () {
    loadConfig();
    showMsg("Reloaded.", "info", 2000);
  });

  loadConfig();
})();
