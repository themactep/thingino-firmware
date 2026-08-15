(function () {
  "use strict";

  const API_URL = "/x/json-timelapse.cgi";
  const statusEl = $("#statusMessage");
  const timelapseForm = $("#timelapseForm");
  const timelapseStoragePath = $("#timelapseStoragePath");
  const timelapseEnabled = $("#timelapseEnabled");
  const timelapseInterval = $("#timelapseInterval");
  const timelapsePlaybackFps = $("#timelapsePlaybackFps");
  const timelapseFileFrames = $("#timelapseFileFrames");
  const timelapseMaxMb = $("#timelapseMaxMb");
  const timelapseReload = $("#timelapse-reload");
  const timelapseSubmit = $("#timelapseSubmit");

  const buttonLabels = new Map();
  if (timelapseSubmit)
    buttonLabels.set(timelapseSubmit, timelapseSubmit.innerHTML);

  function getValue(el) {
    return el && typeof el.value === "string" ? el.value : "";
  }

  function isChecked(el) {
    return !!(el && el.checked);
  }

  function setStatus(message, variant = "info") {
    if (!statusEl) return;
    statusEl.textContent = message;
    statusEl.className = `alert alert-${variant} status-overlay`;
    statusEl.classList.remove("d-none");
  }

  function hideStatus() {
    if (!statusEl) return;
    statusEl.classList.add("d-none");
  }

  function toggleButton(button, loading) {
    if (!button) return;
    if (loading) {
      button.disabled = true;
      button.innerHTML =
        '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Saving...';
    } else {
      button.disabled = false;
      button.innerHTML = buttonLabels.get(button) || "Save changes";
    }
  }

  function boolFromValue(value) {
    return value === true || value === "true" || value === 1 || value === "1";
  }

  function applyTimelapseState(tl = {}) {
    if (timelapseEnabled) timelapseEnabled.checked = boolFromValue(tl.enabled);
    if (timelapseInterval) timelapseInterval.value = tl.interval ?? 10;
    if (timelapsePlaybackFps)
      timelapsePlaybackFps.value = tl.playback_fps ?? 30;
    if (timelapseFileFrames) timelapseFileFrames.value = tl.file_frames ?? 0;
    if (timelapseMaxMb) timelapseMaxMb.value = tl.max_mb ?? 2048;
  }

  function applyState(data = {}) {
    if (timelapseStoragePath)
      timelapseStoragePath.value = data.storage_path || "";
    applyTimelapseState(data.timelapse || {});
  }

  async function loadState() {
    showBusy("Loading timelapse settings...");
    try {
      const response = await fetch(API_URL, {
        headers: { Accept: "application/json" },
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message =
          payload && payload.error
            ? payload.error.message
            : `Request failed with status ${response.status}`;
        throw new Error(message || "Unable to load settings");
      }
      applyState(payload.data || {});
      setStatus("Settings loaded.", "success");
      setTimeout(hideStatus, 2000);
    } catch (err) {
      setStatus("Unable to load settings.", "danger");
      showAlert("danger", err.message || "Timelapse API request failed.");
    } finally {
      hideBusy();
    }
  }

  function buildTimelapseParams() {
    const params = new URLSearchParams();
    params.set("enabled", isChecked(timelapseEnabled) ? "true" : "false");
    params.set("interval", getValue(timelapseInterval));
    params.set("playback_fps", getValue(timelapsePlaybackFps));
    params.set("file_frames", getValue(timelapseFileFrames));
    params.set("max_mb", getValue(timelapseMaxMb));
    return params;
  }

  async function submitForm(event) {
    event.preventDefault();
    toggleButton(timelapseSubmit, true);
    showBusy("Saving timelapse settings...");
    try {
      const response = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: buildTimelapseParams().toString(),
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message =
          payload && payload.error
            ? payload.error.message
            : `Request failed with status ${response.status}`;
        throw new Error(message || "Unable to save changes");
      }
      applyState(payload.data || {});
      const successMessage = payload.message || "Timelapse recorder updated.";
      setStatus(successMessage, "success");
      showAlert("success", successMessage);
      setTimeout(hideStatus, 2000);
    } catch (err) {
      setStatus("Unable to save changes.", "danger");
      showAlert("danger", err.message || "Unexpected error while saving.");
    } finally {
      hideBusy();
      toggleButton(timelapseSubmit, false);
    }
  }

  if (timelapseForm) timelapseForm.addEventListener("submit", submitForm);
  if (timelapseReload)
    timelapseReload.addEventListener("click", (event) => {
      event.preventDefault();
      loadState();
    });

  loadState();
})();
