(function () {
  "use strict";

  const API_URL = "/x/json-webtorrent.cgi";
  const statusEl = $("#statusMessage");
  const wtForm = $("#webtorrentForm");
  const wtEnabled = $("#webtorrentEnabled");
  const wtTracker = $("#webtorrentTracker");
  const wtStunServer = $("#webtorrentStunServer");
  const wtStunPort = $("#webtorrentStunPort");
  const wtTlsVerify = $("#webtorrentTlsVerify");
  const wtViewerUrl = $("#webtorrentViewerUrl");
  const wtShareKey = $("#webtorrentShareKey");
  const wtShareUrl = $("#webtorrentShareUrl");
  const wtShareNote = $("#webtorrentShareNote");
  const wtCopy = $("#webtorrent-copy");
  const wtRotate = $("#webtorrent-rotate");
  const wtRestart = $("#webtorrent-restart");
  const wtReload = $("#webtorrent-reload");
  const wtSubmit = $("#webtorrentSubmit");

  const buttonLabels = new Map();
  if (wtSubmit) buttonLabels.set(wtSubmit, wtSubmit.innerHTML);
  if (wtRotate) buttonLabels.set(wtRotate, wtRotate.innerHTML);
  if (wtRestart) buttonLabels.set(wtRestart, wtRestart.innerHTML);

  function getValue(el) {
    return el && typeof el.value === "string" ? el.value.trim() : "";
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

  function toggleButton(button, loading, loadingText) {
    if (!button) return;
    if (loading) {
      button.disabled = true;
      button.innerHTML = loadingText
        ? `<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>${loadingText}`
        : '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Working...';
    } else {
      button.disabled = false;
      button.innerHTML = buttonLabels.get(button) || "Save changes";
    }
  }

  function boolFromValue(value) {
    return value === true || value === "true" || value === 1 || value === "1";
  }

  function applyState(data = {}) {
    const wt = data.webtorrent || {};
    if (wtEnabled) wtEnabled.checked = boolFromValue(wt.enabled);
    if (wtTracker) wtTracker.value = wt.tracker || "";
    if (wtStunServer) wtStunServer.value = wt.stun_server || "";
    if (wtStunPort) wtStunPort.value = wt.stun_port ?? "";
    if (wtTlsVerify) wtTlsVerify.checked = boolFromValue(wt.tls_verify);
    if (wtViewerUrl) wtViewerUrl.value = wt.viewer_url || "";
    if (wtShareKey) wtShareKey.value = wt.share_key || "";
    applyShare(data.share || {});
  }

  function applyShare(share = {}) {
    const url = share.url || "";
    if (wtShareUrl) wtShareUrl.value = url;
    if (!wtShareNote) return;
    if (!url) {
      wtShareNote.textContent =
        "No share URL available. The streamer generates one at startup when sharing is enabled.";
      return;
    }
    if (share.pending_restart) {
      wtShareNote.textContent =
        "Saved settings are not live yet: this URL is still the key the streamer started with. Restart the streamer to apply.";
    } else if (share.pinned) {
      wtShareNote.textContent =
        "Pinned key in use: this URL survives streamer restarts.";
    } else {
      wtShareNote.textContent =
        "Auto-generated key in use: this URL changes at every streamer start. Rotate to switch to a new pinned key.";
    }
  }

  async function loadState() {
    showBusy("Loading WebTorrent settings...");
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
      showAlert("danger", err.message || "WebTorrent API request failed.");
    } finally {
      hideBusy();
    }
  }

  function buildParams(overrides = {}) {
    const params = new URLSearchParams({ action: "save" });
    params.set("enabled", isChecked(wtEnabled) ? "true" : "false");
    params.set("tracker", getValue(wtTracker));
    params.set("stun_server", getValue(wtStunServer));
    params.set("stun_port", getValue(wtStunPort));
    params.set("tls_verify", isChecked(wtTlsVerify) ? "true" : "false");
    params.set("viewer_url", getValue(wtViewerUrl));
    params.set("share_key", getValue(wtShareKey));
    for (const [key, value] of Object.entries(overrides)) {
      params.set(key, value);
    }
    return params;
  }

  async function post(params, busyMessage) {
    showBusy(busyMessage);
    try {
      const response = await fetch(API_URL, {
        method: "POST",
        headers: { "Content-Type": "application/x-www-form-urlencoded" },
        body: params.toString(),
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message =
          payload && payload.error
            ? payload.error.message
            : `Request failed with status ${response.status}`;
        throw new Error(message || "Request failed");
      }
      applyState(payload.data || {});
      const successMessage = payload.message || "Done.";
      setStatus(successMessage, "success");
      showAlert("success", successMessage);
      setTimeout(hideStatus, 2000);
      return true;
    } catch (err) {
      setStatus("Request failed.", "danger");
      showAlert("danger", err.message || "Unexpected error.");
      return false;
    } finally {
      hideBusy();
    }
  }

  function shareKeyProblem(value) {
    if (!value) return "";
    if (!/^[A-Za-z0-9_-]+$/.test(value)) {
      return "Share key may only contain letters, digits, hyphen and underscore.";
    }
    if (value.length < 4 || value.length > 26) {
      return "Share key length must be between 4 and 26 characters.";
    }
    return "";
  }

  async function submitForm(event) {
    event.preventDefault();
    const keyProblem = shareKeyProblem(getValue(wtShareKey));
    if (keyProblem) {
      setStatus(keyProblem, "danger");
      showAlert("danger", keyProblem);
      return;
    }
    toggleButton(wtSubmit, true, "Saving...");
    try {
      await post(buildParams(), "Saving WebTorrent settings...");
    } finally {
      toggleButton(wtSubmit, false);
    }
  }

  async function rotateShare() {
    toggleButton(wtRotate, true, "Rotating...");
    try {
      await post(
        buildParams({ action: "rotate" }),
        "Rotating share key..."
      );
    } finally {
      toggleButton(wtRotate, false);
    }
  }

  async function restartStreamer() {
    const confirmed = confirm(
      "Restart the streamer now? Live viewers are disconnected and " +
        "reconnect when it is back (about 30 seconds)."
    );
    if (!confirmed) return;
    toggleButton(wtRestart, true, "Restarting...");
    try {
      await post(
        buildParams({ action: "restart" }),
        "Restarting the streamer (up to 30 seconds)..."
      );
    } finally {
      toggleButton(wtRestart, false);
    }
  }

  async function copyShareUrl() {
    if (!wtShareUrl || !wtShareUrl.value) return;
    try {
      await navigator.clipboard.writeText(wtShareUrl.value);
      wtCopy.innerHTML = '<i class="bi bi-check-lg"></i> Copied';
      setTimeout(() => {
        if (wtCopy) wtCopy.innerHTML = '<i class="bi bi-clipboard"></i> Copy';
      }, 2000);
    } catch {
      wtShareUrl.select();
      document.execCommand("copy");
    }
  }

  if (wtForm) wtForm.addEventListener("submit", submitForm);
  if (wtReload)
    wtReload.addEventListener("click", (event) => {
      event.preventDefault();
      loadState();
    });
  if (wtRotate)
    wtRotate.addEventListener("click", (event) => {
      event.preventDefault();
      rotateShare();
    });
  if (wtCopy)
    wtCopy.addEventListener("click", (event) => {
      event.preventDefault();
      copyShareUrl();
    });
  if (wtRestart)
    wtRestart.addEventListener("click", (event) => {
      event.preventDefault();
      restartStreamer();
    });

  loadState();
})();
