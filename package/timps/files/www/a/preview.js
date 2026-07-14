const ImageBlackMode = 1;
const ImageColorMode = 0;

// preview.js talks to timps directly now (window.timpsApi); the old
// /x/json-prudynt.cgi bridge has been removed.

// The Image Quality page is NATIVE: a/streamer-image.js drives every image
// control straight against timps's own /control API (timps-api.js), so on
// that page this script must not touch the legacy bridge CGIs
// (json-imaging.cgi / json-prudynt.cgi) at all - it only keeps running the
// live preview <img>. The other streamer pages still use the bridges until
// they are converted too.
const nativeImagePage =
  document.body && document.body.id === "page-streamer-image";

// The per-stream OSD pages are NATIVE too: a/streamer-osd.js drives every
// OSD control straight against timps's own /control API (timps-api.js), so
// on those pages this script must not touch the legacy bridge CGIs either -
// it only keeps running the live preview <img>.
const nativeOsdPage =
  document.body && /^page-streamer-osd[01]$/.test(document.body.id);

// The encoder pages (RTSP main/substream) are NATIVE too: a/streamer-encoder.js
// wires the stream0/stream1 controls straight to timps /control. This script
// must NOT also wire them (that would double-submit and re-introduce the
// bridge), so it skips the stream editor + loadConfig on those pages.
const nativeEncoderPage =
  document.body && /^page-streamer-(main|substream)$/.test(document.body.id);

// ---- direct-to-timps media URLs (no proxy CGIs) ----
// The settings pages' small live preview <img>, the fullscreen modal and the
// endpoint list load timps's own HTTP media endpoints directly:
//   live:  http://<host>:<port>/stream.mjpeg?chn=<N>&token=<tok>
//   still: http://<host>:<port>/snapshot.jpg?chn=<N>&token=<tok>
// /x/timps-token.cgi hands the authenticated WebUI session the per-boot
// timps token as {"token":"...","port":8880}. The token unlocks media
// viewing + /control + /events on that port (never RTSP) and travels as
// ?token= because an <img> cannot send headers - it can show up in access
// logs, which is accepted on the LAN. The token is per-boot, so it is
// fetched once and cached; when the stream errors (e.g. 401 after a camera
// reboot minted a new token) it is re-fetched once and the <img> retried,
// and if the token endpoint itself is unavailable the preview falls back to
// the nostream placeholder. Without a token the URLs still work on open
// timps configs (empty http.user) and from localhost.
let timpsMediaInfo = null; // {token, port} after the first fetch
let timpsMediaPending = null; // in-flight fetch (dedup)

function fetchTimpsMediaInfo(force = false) {
  if (timpsMediaInfo && !force) return Promise.resolve(timpsMediaInfo);
  if (!timpsMediaPending) {
    timpsMediaPending = fetch("/x/timps-token.cgi", { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : null))
      .catch(() => null)
      .then((data) => {
        timpsMediaPending = null;
        timpsMediaInfo = {
          token: data && data.token ? String(data.token) : "",
          port: data && data.port ? parseInt(data.port, 10) : 8880,
          tls: !!(data && data.tls),
        };
        return timpsMediaInfo;
      });
  }
  return timpsMediaPending;
}

// kind "live" -> /stream.mjpeg, "still" -> /snapshot.jpg; chn is the numeric
// timps channel (data-stream "ch0" -> 0, "ch1" -> 1). host defaults to the
// address the WebUI itself was opened on.
function timpsMediaUrl(kind, chn, host) {
  const h = wrapIpv6Host(host || window.location.hostname || "127.0.0.1");
  const port = timpsMediaInfo ? timpsMediaInfo.port : 8880;
  const scheme = timpsMediaInfo && timpsMediaInfo.tls ? "https" : "http";
  const path = kind === "still" ? "/snapshot.jpg" : "/stream.mjpeg";
  let url = `${scheme}://${h}:${port}${path}?chn=${chn}`;
  if (timpsMediaInfo && timpsMediaInfo.token) {
    url += `&token=${encodeURIComponent(timpsMediaInfo.token)}`;
  }
  return url;
}

// Create fullscreen preview modal dynamically if preview element exists
(function createPreviewModal() {
  const preview = $("#preview");
  if (!preview) return;

  // Create modal HTML
  const modalHTML = `
    <div class="modal fade" id="mdPreview" tabindex="-1" aria-labelledby="mdlPreview" aria-hidden="true">
      <div class="modal-dialog modal-fullscreen">
        <div class="modal-content">
          <div class="modal-header">
            <h1 class="modal-title fs-4" id="mdlPreview">Full screen preview</h1>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body text-center">
            <img id="preview_fullsize" src="/a/nostream.svg" alt="Image: Stream Preview" class="img-fluid">
          </div>
        </div>
      </div>
    </div>
  `;

  // Append modal to body
  document.body.insertAdjacentHTML("beforeend", modalHTML);

  // Add click event to preview image to open modal
  preview.addEventListener("click", () => {
    const previewModal = new bootstrap.Modal($("#mdPreview"));
    previewModal.show();
  });
})();

const stream_params = [
  "enabled",
  "width",
  "height",
  "fps",
  "bitrate",
  "gop",
  "max_gop",
  "format",
  "mode",
  "buffers",
  "profile",
  "rtsp_endpoint",
  "audio_enabled",
];
const osd_params = ["enabled", "fontsize", "strokesize"];
const previewEndpointState = {
  rtsp: {
    username: "thingino",
    password: "thingino",
    port: "554",
  },
  stream0: {
    rtsp_endpoint: "ch0",
  },
  stream1: {
    rtsp_endpoint: "ch1",
  },
};

function rgba2color(hex8) {
  return hex8.substring(0, 7);
}

function rgba2alpha(hex8) {
  const alphaHex = hex8.substring(7, 9);
  const alpha = parseInt(alphaHex, 16);
  return alpha;
}

// set a color picker (+ its optional "-alpha" slider) from a "#rrggbbaa"
// value. timps OSD colors carry a real alpha byte (0xAARRGGBB), so the alpha
// slider is populated and enabled whenever the streamer echoes 8 hex digits.
function setOsdColorInputs(streamIndex, name, hex8) {
  const el = $(`#osd${streamIndex}_${name}`);
  if (el) {
    el.value = rgba2color(hex8);
    el.disabled = false;
  }
  const alphaEl = $(`#osd${streamIndex}_${name}-alpha`);
  if (alphaEl && hex8 && hex8.length >= 9) {
    const a = rgba2alpha(hex8);
    if (!Number.isNaN(a)) {
      alphaEl.value = a;
      alphaEl.disabled = false;
    }
  }
}

// combined color of one picker: "#rrggbb" + alpha from its "-alpha" slider
// ("ff" when the slider is absent or still disabled) -> "#rrggbbaa"
function osdColorValue(streamId, base) {
  const colorEl = $(`#osd${streamId}_${base}`);
  const alphaEl = $(`#osd${streamId}_${base}-alpha`);
  let a = 255;
  if (alphaEl && !alphaEl.disabled && alphaEl.value !== "") {
    const parsed = parseInt(alphaEl.value, 10);
    if (!Number.isNaN(parsed)) a = Math.min(255, Math.max(0, parsed));
  }
  const hex = a.toString(16).padStart(2, "0");
  return (colorEl ? colorEl.value : "#ffffff") + hex;
}

function previewEndpointValue(value, fallback) {
  return value === undefined || value === null || value === ""
    ? fallback
    : value;
}

function wrapIpv6Host(host) {
  return host && host.includes(":") && !host.startsWith("[")
    ? `[${host}]`
    : host;
}

function formatPreviewHostWithPort(host, port, defaultPort) {
  const numericPort = parseInt(port, 10);
  if (!port || Number.isNaN(numericPort) || numericPort === defaultPort) {
    return host;
  }
  return `${host}:${numericPort}`;
}

function buildRtspCredential(user, pass) {
  return `${encodeURIComponent(user)}:${encodeURIComponent(pass)}`;
}

function markPreviewEndpointCopied(link) {
  if (!link) return;
  link.classList.add("copied");
  if (link._copyTimer) {
    clearTimeout(link._copyTimer);
  }
  link._copyTimer = window.setTimeout(() => {
    link.classList.remove("copied");
    link._copyTimer = null;
  }, 1200);
}

async function copyPreviewEndpoint(ev) {
  ev.preventDefault();
  const link = ev.currentTarget;
  const url = link?.dataset?.copyUrl || link?.href || "";
  const clipboard = window.thinginoClipboard;
  if (!url || !clipboard || typeof clipboard.copy !== "function") {
    if (typeof window.showAlert === "function") {
      window.showAlert("warning", "Clipboard copy is not available.", 3000);
    }
    return;
  }
  try {
    await clipboard.copy(url);
    markPreviewEndpointCopied(link);
  } catch (err) {
    if (typeof window.showAlert === "function") {
      window.showAlert("danger", "Unable to copy the endpoint.", 3000);
    }
  }
}

function renderPreviewEndpoints() {
  const list = $("#preview-endpoint-list");
  if (!list) return;
  const host =
    window.network_address || window.location.hostname || "localhost";
  const rtspHost = formatPreviewHostWithPort(
    wrapIpv6Host(host),
    previewEndpointState.rtsp.port,
    554,
  );
  const rtspAuth = buildRtspCredential(
    previewEndpointState.rtsp.username,
    previewEndpointState.rtsp.password,
  );
  const entries = [
    {
      label: "RTSP Ch0",
      url: `rtsp://${rtspAuth}@${rtspHost}/${previewEndpointState.stream0.rtsp_endpoint}`,
    },
    {
      label: "RTSP Ch1",
      url: `rtsp://${rtspAuth}@${rtspHost}/${previewEndpointState.stream1.rtsp_endpoint}`,
    },
    {
      label: "MJPEG Ch0",
      url: timpsMediaUrl("live", 0, host),
    },
    {
      label: "MJPEG Ch1",
      url: timpsMediaUrl("live", 1, host),
    },
    {
      label: "Snapshot Ch0",
      url: timpsMediaUrl("still", 0, host),
    },
    {
      label: "Snapshot Ch1",
      url: timpsMediaUrl("still", 1, host),
    },
  ];

  list.innerHTML = "";
  entries.forEach((entry) => {
    const link = document.createElement("a");
    link.className = "preview-endpoint-link";
    link.href = entry.url;
    link.rel = "noopener";
    link.dataset.copyUrl = entry.url;
    link.title = `${entry.label}: ${entry.url}`;
    link.setAttribute("aria-label", `${entry.label} endpoint`);

    const shortLabel = document.createElement("span");
    shortLabel.className = "preview-endpoint-short";
    shortLabel.textContent = entry.label;

    const hint = document.createElement("span");
    hint.className = "preview-endpoint-hint";
    hint.innerHTML = '<i class="bi bi-clipboard"></i>';

    link.appendChild(shortLabel);
    link.appendChild(hint);
    link.addEventListener("click", copyPreviewEndpoint);

    list.appendChild(link);
  });
}

function updatePreviewEndpointState(msg) {
  if (msg.rtsp) {
    previewEndpointState.rtsp.username = previewEndpointValue(
      msg.rtsp.username,
      previewEndpointState.rtsp.username,
    );
    previewEndpointState.rtsp.password = previewEndpointValue(
      msg.rtsp.password,
      previewEndpointState.rtsp.password,
    );
    previewEndpointState.rtsp.port = previewEndpointValue(
      msg.rtsp.port,
      previewEndpointState.rtsp.port,
    );
  }
  if (msg.stream0) {
    previewEndpointState.stream0.rtsp_endpoint = previewEndpointValue(
      msg.stream0.rtsp_endpoint,
      previewEndpointState.stream0.rtsp_endpoint,
    );
  }
  if (msg.stream1) {
    previewEndpointState.stream1.rtsp_endpoint = previewEndpointValue(
      msg.stream1.rtsp_endpoint,
      previewEndpointState.stream1.rtsp_endpoint,
    );
  }
  renderPreviewEndpoints();
}

async function initPreviewEndpoints() {
  await fetchTimpsMediaInfo(); // token + port for the direct media URLs
  renderPreviewEndpoints();
}

initPreviewEndpoints();

function handleOsdData(osd, streamIndex) {
  if (!osd) return;

  if (osd.enabled !== undefined) {
    const el = $(`#osd${streamIndex}_enabled`);
    if (el) {
      el.checked = osd.enabled;
      el.disabled = false;
    }
  }
  if (osd.font_size !== undefined) {
    const el = $(`#osd${streamIndex}_fontsize`);
    if (el) {
      el.value = osd.font_size;
      el.disabled = false;
    }
  }
  if (osd.stroke_size !== undefined) {
    const el = $(`#osd${streamIndex}_strokesize`);
    if (el) {
      el.value = osd.stroke_size;
      el.disabled = false;
    }
  }

  // Logo element
  if (osd.logo) {
    if (osd.logo.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_logo_enabled`);
      if (el) {
        el.checked = osd.logo.enabled;
        el.disabled = false;
      }
    }
    if (osd.logo.position !== undefined) {
      const el = $(`#osd${streamIndex}_logo_position`);
      if (el) {
        el.value = osd.logo.position;
        el.disabled = false;
      }
    }
  }

  // Time element
  if (osd.time) {
    if (osd.time.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_time_enabled`);
      if (el) {
        el.checked = osd.time.enabled;
        el.disabled = false;
      }
    }
    if (osd.time.format !== undefined) {
      const el = $(`#osd${streamIndex}_time_format`);
      if (el) {
        el.value = osd.time.format;
        el.disabled = false;
      }
    }
    if (osd.time.position !== undefined) {
      const el = $(`#osd${streamIndex}_time_position`);
      if (el) {
        el.value = osd.time.position;
        el.disabled = false;
      }
    }
    if (osd.time.fill_color) {
      setOsdColorInputs(streamIndex, "time_fillcolor", osd.time.fill_color);
    }
    if (osd.time.stroke_color) {
      setOsdColorInputs(streamIndex, "time_strokecolor", osd.time.stroke_color);
    }
  }

  // Uptime element
  if (osd.uptime) {
    if (osd.uptime.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_enabled`);
      if (el) {
        el.checked = osd.uptime.enabled;
        el.disabled = false;
      }
    }
    if (osd.uptime.position !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_position`);
      if (el) {
        el.value = osd.uptime.position;
        el.disabled = false;
      }
    }
    if (osd.uptime.fill_color) {
      setOsdColorInputs(streamIndex, "uptime_fillcolor", osd.uptime.fill_color);
    }
    if (osd.uptime.stroke_color) {
      setOsdColorInputs(
        streamIndex,
        "uptime_strokecolor",
        osd.uptime.stroke_color,
      );
    }
  }

  // Usertext element
  if (osd.usertext) {
    if (osd.usertext.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_enabled`);
      if (el) {
        el.checked = osd.usertext.enabled;
        el.disabled = false;
      }
    }
    if (osd.usertext.format !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_format`);
      if (el) {
        el.value = osd.usertext.format;
        el.disabled = false;
      }
    }
    if (osd.usertext.position !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_position`);
      if (el) {
        el.value = osd.usertext.position;
        el.disabled = false;
      }
    }
    if (osd.usertext.fill_color) {
      setOsdColorInputs(
        streamIndex,
        "usertext_fillcolor",
        osd.usertext.fill_color,
      );
    }
    if (osd.usertext.stroke_color) {
      setOsdColorInputs(
        streamIndex,
        "usertext_strokecolor",
        osd.usertext.stroke_color,
      );
    }
  }
}

function handleMessage(msg) {
  if (msg.motion && msg.motion.enabled !== undefined) {
    $("#motion").checked = msg.motion.enabled;
  }
  if (msg.privacy && msg.privacy.enabled !== undefined) {
    $("#privacy").checked = msg.privacy.enabled;
  }

  // if (msg.rtsp) {
  //   const r = msg.rtsp;
  //   if (r.username && r.password && r.port && msg.stream0?.rtsp_endpoint)
  //     $('#playrtsp').innerHTML = `ffplay -hide_banner -rtsp_transport tcp rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
  // }

  // Handle image params
  if (msg.image) {
    const imageParams = [
      "hflip",
      "vflip",
      "wb_bgain",
      "wb_rgain",
      "ae_compensation",
      "core_wb_mode",
    ];
    imageParams.forEach((param) => {
      if (msg.image[param] !== undefined) {
        setValue(msg.image, "image", param);
      }
    });
  }

  // Handle stream0 params
  if (msg.stream0) {
    stream_params.forEach((param) => {
      if (msg.stream0[param] !== undefined) {
        setValue(msg.stream0, "stream0", param);
      }
    });
    handleOsdData(msg.stream0.osd, 0);
  }

  // Handle stream1 params
  if (msg.stream1) {
    stream_params.forEach((param) => {
      if (msg.stream1[param] !== undefined) {
        setValue(msg.stream1, "stream1", param);
      }
    });
    handleOsdData(msg.stream1.osd, 1);
  }

  // timps: encoder/stream/sensor settings are persisted but only take effect
  // after a streamer restart; the json-prudynt.cgi bridge flags this (same
  // hint audio.js shows; prudynt restarts its threads itself and never sets
  // the flag). "Restart streamer" in the menu calls /x/restart-prudynt.cgi.
  if (msg.restart_required && typeof window.showAlert === "function") {
    window.showAlert(
      "warning",
      "Setting saved. Restart the streamer (Restart streamer in the menu) for it to take effect.",
      8000,
    );
  }

  updatePreviewEndpointState(msg);
}

async function loadMotorParams() {
  try {
    const response = await fetch("/x/json-motor-params.cgi");
    const motorParams = await response.json();
    window.motorParams = motorParams;
    console.log("Motor parameters loaded:", motorParams);
  } catch (error) {
    console.error("Failed to load motor parameters:", error);
    window.motorParams = {
      steps_pan: 0,
      steps_tilt: 0,
      pos_0_x: 0,
      pos_0_y: 0,
    };
  }
}

// Map a timps GET /control snapshot to the prudynt-shaped message handleMessage
// expects (only the fields the preview page consumes: image quick controls,
// the motion/privacy control-bar flags, and the RTSP endpoint paths for the
// endpoint list). timps has no RTSP creds/port in /control, so those are left
// to the existing defaults.
function buildPreviewMsg(c) {
  const msg = { image: {}, stream0: {}, stream1: {} };
  if (c.image) {
    ["hflip", "vflip", "wb_bgain", "wb_rgain", "ae_compensation", "core_wb_mode"]
      .forEach((k) => { if (c.image[k] !== undefined) msg.image[k] = c.image[k]; });
  }
  if (c.motion && c.motion.enabled !== undefined)
    msg.motion = { enabled: c.motion.enabled };
  // privacy is per-region in timps; the control-bar flag is "on" if any mask is
  if (c.privacy) {
    let on = false;
    Object.keys(c.privacy).forEach((s) =>
      Object.keys(c.privacy[s] || {}).forEach((n) => {
        if (Number((c.privacy[s][n] || {}).enabled)) on = true;
      }),
    );
    msg.privacy = { enabled: on ? 1 : 0 };
  }
  if (c.video) {
    if (c.video[0]) msg.stream0.rtsp_endpoint = c.video[0].rtsp_path;
    if (c.video[1]) msg.stream1.rtsp_endpoint = c.video[1].rtsp_path;
  }
  return msg;
}

async function loadConfig() {
  // native image/OSD/encoder pages load their own state from timps GET /control
  // via a/streamer-image.js / a/streamer-osd.js / a/streamer-encoder.js
  if (nativeImagePage || nativeOsdPage || nativeEncoderPage) return;
  if (!window.timpsApi) return;
  showBusy("Loading camera configuration...");
  try {
    const c = await window.timpsApi.get();
    handleMessage(buildPreviewMsg(c));
  } catch (err) {
    console.error("Load config error", err);
  } finally {
    hideBusy();
  }
}

// NATIVE: apply a preview-page control change through timps /control. The old
// callers produced prudynt-shaped payloads ({image:{}}, {motion:{}},
// {streamN:{...}}); translate the ones the preview page still uses (image is
// the main one - WB/AE/flip quick controls). Encoder + OSD editors live on the
// native streamer-encoder.js / streamer-osd.js pages, so their shapes only
// arrive here as a best-effort fallback. No json-prudynt.cgi bridge.
async function sendToEndpoint(payload) {
  if (!window.timpsApi || !payload || typeof payload !== "object") return;
  const out = {};
  if (payload.image && typeof payload.image === "object") out.image = payload.image;
  if (payload.motion && typeof payload.motion === "object") out.motion = payload.motion;
  [0, 1].forEach((n) => {
    const s = payload["stream" + n];
    if (s && typeof s === "object") {
      const v = {};
      Object.keys(s).forEach((k) => { if (k !== "osd") v[k] = s[k]; });
      if (Object.keys(v).length) { out.video = out.video || {}; out.video[n] = v; }
    }
  });
  if (!Object.keys(out).length) return;
  try {
    await window.timpsApi.set(out);
  } catch (err) {
    console.error("Send error", err);
  }
}

async function loadInitialData() {
  await Promise.all([loadConfig(), loadMotorParams()]);
}

// Init on load
loadInitialData().then(async () => {
  // Load webui config for focus tracking settings
  let webuiConfig = {
    track_focus: false,
    focus_timeout: 0,
  };

  async function loadWebuiConfig() {
    try {
      const response = await fetch("/x/json-config-webui.cgi", {
        headers: { Accept: "application/json" },
      });
      if (response.ok) {
        const data = await response.json();
        webuiConfig.track_focus = data.track_focus === true;
        webuiConfig.focus_timeout = Math.max(
          0,
          parseInt(data.focus_timeout) || 0,
        );
      }
    } catch (err) {
      console.warn("Could not load webui config for focus tracking:", err);
    }
  }

  // Load webui config before continuing
  await loadWebuiConfig();

  // Expose config reload function globally for use in config-webui.js
  window.reloadPreviewFocusSettings = async () => {
    await loadWebuiConfig();
    // Update event listeners based on new settings
    if (webuiConfig.track_focus) {
      // Add listeners if not already added
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("focus", handleWindowFocus);
      window.removeEventListener("blur", handleWindowBlur);
      document.addEventListener("visibilitychange", handleVisibilityChange);
      window.addEventListener("focus", handleWindowFocus);
      window.addEventListener("blur", handleWindowBlur);
    } else {
      // Remove listeners if tracking is disabled
      document.removeEventListener("visibilitychange", handleVisibilityChange);
      window.removeEventListener("focus", handleWindowFocus);
      window.removeEventListener("blur", handleWindowBlur);
      // Clear any pending timeouts
      if (focusTimeoutId) {
        clearTimeout(focusTimeoutId);
        focusTimeoutId = null;
      }
      // Ensure window is marked as visible and start preview
      isWindowVisible = true;
      startPreview();
    }
  };

  // Get stream from data-stream attribute, default to ch0 if not specified;
  // "chN" maps to timps channel N (ch0 -> 0, ch1 -> 1)
  const preview = $("#preview");
  const streamChannel = preview?.dataset?.stream || "ch0";
  const streamChn = parseInt(streamChannel.replace(/^ch/, ""), 10) || 0;
  // live MJPEG straight from timps; the cache-bust param forces the browser
  // to reopen the multipart stream instead of showing a stale cached frame
  const liveStreamUrl = (chn = streamChn) =>
    `${timpsMediaUrl("live", chn)}&_=${Date.now()}`;

  // Preview
  const timeout = 15000;
  const restartBackoffInitialMs = 15000;
  const restartBackoffMaxMs = 60000;
  let lastLoadTime = Date.now();
  let isWindowVisible = true;
  let focusTimeoutId = null;
  let nextRestartAt = 0;
  let restartBackoffMs = restartBackoffInitialMs;
  let tokenRetried = false; // one re-fetch per failure (camera rebooted?)

  // the direct media URLs need the timps token/port first
  await fetchTimpsMediaInfo();

  // Function to start the preview stream
  function startPreview() {
    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
      focusTimeoutId = null;
    }
    if (isWindowVisible) {
      preview.src = liveStreamUrl();
      lastLoadTime = Date.now();
      nextRestartAt = 0;
    }
  }
  // let main.js's visibility handling restart the stream on any page
  window.restartStreamPreview = startPreview;

  // Function to stop the preview stream
  function stopPreview() {
    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
      focusTimeoutId = null;
    }
    preview.src = ImageNoStream;
    nextRestartAt = 0;
  }

  // Function to stop preview with delay
  function stopPreviewWithDelay() {
    if (!webuiConfig.track_focus) {
      return; // Don't stop if tracking is disabled
    }

    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
    }

    if (webuiConfig.focus_timeout > 0) {
      focusTimeoutId = setTimeout(() => {
        if (!isWindowVisible) {
          stopPreview();
        }
      }, webuiConfig.focus_timeout * 1000);
    } else {
      stopPreview();
    }
  }

  // Start the preview stream
  startPreview();

  // preview.src comes back absolutized by the browser, so compare by suffix
  const showsNoStream = () => (preview.src || "").endsWith(ImageNoStream);

  preview.addEventListener("load", () => {
    lastLoadTime = Date.now();
    restartBackoffMs = restartBackoffInitialMs;
    nextRestartAt = 0;
    if (!showsNoStream()) tokenRetried = false;
  });

  // Stream error (connection refused / 401): the per-boot token changes on
  // a camera reboot, so re-fetch it once and retry; if the stream still
  // fails, fall back to the nostream placeholder (the watchdog keeps
  // retrying with backoff).
  preview.addEventListener("error", () => {
    if (!isWindowVisible || showsNoStream() || !preview.src) return;
    if (tokenRetried) {
      preview.src = ImageNoStream;
      return;
    }
    tokenRetried = true;
    fetchTimpsMediaInfo(true).then(() => {
      if (isWindowVisible) preview.src = liveStreamUrl();
    });
  });

  // Stream watchdog - restart if no frames received
  setInterval(() => {
    const now = Date.now();
    if (
      isWindowVisible &&
      now - lastLoadTime > timeout &&
      now >= nextRestartAt
    ) {
      // Restart stream (fresh cache-bust + current token)
      preview.src = liveStreamUrl();
      lastLoadTime = now;
      nextRestartAt = now + restartBackoffMs;
      restartBackoffMs = Math.min(restartBackoffMs * 2, restartBackoffMaxMs);
    }
  }, 1000);

  // Handle window visibility changes
  function handleVisibilityChange() {
    if (document.hidden) {
      isWindowVisible = false;
      stopPreview();
    } else {
      isWindowVisible = true;
      startPreview();
    }
  }

  // Handle window focus/blur events
  function handleWindowFocus() {
    isWindowVisible = true;
    startPreview();
  }

  function handleWindowBlur() {
    isWindowVisible = false;
    stopPreviewWithDelay();
  }

  window.addEventListener("beforeunload", stopPreview);
  window.addEventListener("pagehide", stopPreview);

  // Add event listeners for visibility changes only if tracking is enabled
  document.addEventListener("visibilitychange", handleVisibilityChange);

  if (webuiConfig.track_focus) {
    window.addEventListener("focus", handleWindowFocus);
    window.addEventListener("blur", handleWindowBlur);
  }

  // Full-screen preview modal
  const previewModal = $("#mdPreview");
  const previewFullsize = $("#preview_fullsize");
  let savedPreviewSrc = "";

  if (previewModal && previewFullsize) {
    previewModal.addEventListener("show.bs.modal", () => {
      // Save current small preview source
      savedPreviewSrc = preview.src;
      // Stop the small preview
      preview.src = ImageNoStream;
      // Load main stream (ch0) in full-screen modal, straight from timps
      previewFullsize.src = liveStreamUrl(0);
    });

    previewModal.addEventListener("hidden.bs.modal", () => {
      // Stop the full-screen stream
      previewFullsize.src = ImageNoStream;
      // Restart the small preview (fresh cache-bust + current token)
      if (savedPreviewSrc && isWindowVisible) {
        startPreview();
      }
    });
  }
});

const imagingFields = [
  "brightness",
  "contrast",
  "sharpness",
  "saturation",
  "backlight",
  "wide_dynamic_range",
  "tone",
  "defog",
  "noise_reduction",
];

const imageConfigKeyMap = {
  brightness: "brightness",
  contrast: "contrast",
  sharpness: "sharpness",
  saturation: "saturation",
  backlight: "backlight_compensation",
  wide_dynamic_range: "drc_strength",
  tone: "highlight_depress",
  defog: "defog_strength",
  noise_reduction: "sinter_strength",
};

// Static per-field bounds, ported from the old json-imaging.cgi bridge (min 0,
// max 255 except backlight 10; default 128 except backlight/tone 0). timps
// GET /control reports the live value + caps.image (supported), but not the
// UI bounds, so they live here now.
const imageFieldBounds = {
  brightness: { min: 0, max: 255, default: 128 },
  contrast: { min: 0, max: 255, default: 128 },
  sharpness: { min: 0, max: 255, default: 128 },
  saturation: { min: 0, max: 255, default: 128 },
  backlight: { min: 0, max: 10, default: 0 },
  wide_dynamic_range: { min: 0, max: 255, default: 128 },
  tone: { min: 0, max: 255, default: 0 },
  defog: { min: 0, max: 255, default: 128 },
  noise_reduction: { min: 0, max: 255, default: 128 },
};

const previewSliderIds = [
  "brightness",
  "contrast",
  "sharpness",
  "saturation",
  "backlight",
  "wide_dynamic_range",
  "tone",
  "defog",
  "noise_reduction",
  "image_wb_bgain",
  "image_wb_rgain",
  "image_ae_compensation",
  "stream0_fps",
  "stream1_fps",
];

(function initPreviewSliders() {
  if (
    typeof window === "undefined" ||
    typeof window.initSliders !== "function"
  ) {
    return;
  }
  const run = () => window.initSliders(previewSliderIds);
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", () => run(), { once: true });
  } else {
    run();
  }
})();

// Load sensor information on sensor page
(function loadSensorInfo() {
  if (!$("#sensor-info")) {
    return; // Not on sensor page
  }

  const sensorLoading = $("#sensor-loading");
  const sensorDetails = $("#sensor-details");
  const sensorFilePath = $("#sensor-file-path");
  const sensorMd5 = $("#sensor-md5");
  const sensorSocFamily = $("#sensor-soc-family");
  const sensorModel = $("#sensor-model");

  async function fetchSensorInfo() {
    try {
      const response = await fetch("/x/json-sensor-info.cgi");
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const data = await response.json();

      if (data.error) {
        throw new Error(data.error.message || "Unknown error");
      }

      sensorFilePath.textContent = data.file_path || "Unknown";
      sensorMd5.textContent = data.md5 || "Unknown";
      if (sensorSocFamily)
        sensorSocFamily.textContent = data.soc_family || "Unknown";
      if (sensorModel) sensorModel.textContent = data.sensor_model || "Unknown";

      sensorLoading.classList.add("d-none");
      sensorDetails.classList.remove("d-none");
    } catch (err) {
      sensorLoading.textContent = `Error loading sensor info: ${err.message}`;
    }
  }

  fetchSensorInfo();
})();

// Disable all imaging controls initially. Prefer the field's own <p> wrapper
// so a single unsupported control never greys out a whole column.
imagingFields.forEach((field) => {
  const input = $(`#${field}`);
  if (input) {
    input.disabled = true;
    const wrapper = input.closest("p, .number-range, .col");
    if (wrapper) wrapper.classList.add("disabled");
  }
  // Also disable the modal slider if it exists
  const slider = $(`#${field}-slider`);
  if (slider) slider.disabled = true;
});

function updateImagingLabel(name, value) {
  const input = $(`#${name}`);
  if (input) {
    input.value = value === undefined || value === null ? "" : value;
  }
  // Also update the slider value display in modal
  const sliderValue = $(`#${name}-slider-value`);
  if (sliderValue) {
    const displayValue = value === undefined || value === null ? "—" : value;
    sliderValue.textContent = displayValue;
  }
  // Update the actual slider
  const slider = $(`#${name}-slider`);
  if (slider && value !== undefined && value !== null) {
    slider.value = value;
  }
}

function setSliderBounds(input, slider, min, max, value, defaultValue) {
  if (Number.isFinite(min)) {
    if (input) input.dataset.min = min;
    if (slider) slider.min = min;
  }
  if (Number.isFinite(max)) {
    if (input) input.dataset.max = max;
    if (slider) slider.max = max;
  }
  if (Number.isFinite(value)) {
    if (input) input.value = value;
    if (slider) slider.value = value;
  }
  if (Number.isFinite(defaultValue)) {
    if (input) input.dataset.defaultValue = defaultValue;
    if (slider) slider.dataset.defaultValue = defaultValue;
  } else {
    if (input) delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
  }
}

function applyFieldMetadata(field, data) {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);
  if (!input) return;
  const wrapper =
    input.closest("p, .number-range, .col") || input.parentElement;
  const isSupported = data && data.supported !== false;
  if (!isSupported) {
    input.disabled = true;
    if (slider) slider.disabled = true;
    if (wrapper) wrapper.classList.add("disabled");
    delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
    updateImagingLabel(field, "—");
    return;
  }
  input.disabled = false;
  if (slider) slider.disabled = false;
  if (wrapper) wrapper.classList.remove("disabled");
  setSliderBounds(
    input,
    slider,
    Number(data.min),
    Number(data.max),
    Number(data.value),
    Number(data.default),
  );
  updateImagingLabel(field, data.value);
}

// NATIVE: read the live image values from timps GET /control (no
// json-imaging.cgi bridge). Enable a field only when its timps key is in
// caps.image; bounds come from the static imageFieldBounds table.
async function fetchImagingState() {
  if (!window.timpsApi) return;
  showBusy("Loading imaging settings...");
  try {
    const json = await window.timpsApi.get();
    const image = json.image || {};
    const caps = (json.caps && json.caps.image) || [];
    imagingFields.forEach((field) => {
      const key = imageConfigKeyMap[field];
      const b = imageFieldBounds[field] || { min: 0, max: 255, default: 128 };
      const value = image[key];
      applyFieldMetadata(field, {
        supported: caps.indexOf(key) >= 0,
        min: b.min,
        max: b.max,
        default: b.default,
        value: value === undefined || value === null ? b.default : value,
      });
    });
  } catch (err) {
    console.warn("Unable to load imaging state", err);
  } finally {
    hideBusy();
  }
}

// NATIVE: apply a changed field straight to timps /control (debounced; the
// single noise-reduction knob drives both ISP noise reducers). timps applies
// live AND persists immediately.
async function sendImagingUpdate(field, value, element) {
  const key = imageConfigKeyMap[field];
  if (!key || !window.timpsApi) return;
  const b = imageFieldBounds[field] || { min: 0, max: 255, default: 128 };
  let v = parseInt(value, 10);
  if (Number.isNaN(v)) return;
  v = Math.max(b.min, Math.min(b.max, v));
  const image = { [key]: v };
  if (key === "sinter_strength") image.temper_strength = v;
  element?.setAttribute("data-busy", "1");
  element?.classList.add("opacity-75");
  try {
    await window.timpsApi.setDebounced({ image }, 150);
    applyFieldMetadata(field, {
      supported: true,
      min: b.min,
      max: b.max,
      default: b.default,
      value: v,
    });
  } catch (err) {
    console.error("Failed to update imaging value", err);
  } finally {
    element?.removeAttribute("data-busy");
    element?.classList.remove("opacity-75");
  }
}

// Setup event handlers for imaging fields (number inputs and modal sliders).
// Skipped on the native image page: a/streamer-image.js wires these controls
// to timps /control directly (this handler would POST to json-imaging.cgi).
if (!nativeImagePage)
imagingFields.forEach((field) => {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);

  // Handle text input changes
  if (input) {
    input.addEventListener("change", (ev) => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on input to reset to default
    input.addEventListener("dblclick", (ev) => {
      const min = Number(ev.target.dataset.min ?? 0);
      const max = Number(ev.target.dataset.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue))
        ? Number(defaultValue)
        : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }

  // Handle modal slider input (live update)
  if (slider) {
    slider.addEventListener("input", (ev) => {
      updateImagingLabel(field, ev.target.value);
    });

    // Handle slider change (on release)
    slider.addEventListener("change", (ev) => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on slider to reset to default
    slider.addEventListener("dblclick", (ev) => {
      const min = Number(ev.target.min ?? 0);
      const max = Number(ev.target.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue))
        ? Number(defaultValue)
        : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }
});

// Streamer controls
function coerceStreamValue(param, el) {
  if (el.type === "checkbox") {
    return el.checked;
  }

  const raw = typeof el.value === "string" ? el.value : "";
  const trimmed = raw.trim();
  if (trimmed === "") {
    return "";
  }

  // Treat any purely numeric string as a number so prudynt gets the correct type.
  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
    return trimmed.includes(".")
      ? Number.parseFloat(trimmed)
      : Number.parseInt(trimmed, 10);
  }

  return trimmed;
}

function saveStreamValue(streamId, param) {
  const el = $(`#stream${streamId}_${param}`);
  if (!el) return;
  const value = coerceStreamValue(param, el);
  const payload = {
    [`stream${streamId}`]: { [param]: value },
    action: { restart_thread: ThreadRtsp | ThreadVideo },
  };
  sendToEndpoint(payload);
}

// Setup stream0 and stream1 controls. Skipped on the native encoder pages
// (streamer-main/substream): a/streamer-encoder.js wires these controls to
// timps /control directly, so this must not also wire them (double submit +
// bridge). On other pages there are no stream fields, so this is inert.
if (!nativeEncoderPage)
[0, 1].forEach((streamId) => {
  stream_params.forEach((param) => {
    const el = $(`#stream${streamId}_${param}`);
    if (el) {
      el.addEventListener("change", () => saveStreamValue(streamId, param));
      el.disabled = true;
    }

    // Also handle modal slider if it exists
    const slider = $(`#stream${streamId}_${param}-slider`);
    if (slider) {
      slider.addEventListener("input", (ev) => {
        // Update the text input while dragging
        if (el) el.value = ev.target.value;
        const sliderValue = $(`#stream${streamId}_${param}-slider-value`);
        if (sliderValue) sliderValue.textContent = ev.target.value;
      });
      slider.addEventListener("change", () => saveStreamValue(streamId, param));
      slider.disabled = true;
    }
  });
});

// OSD controls
function sendOsdUpdate(streamId, osdPayload) {
  // OSD changes require Video + OSD thread restart to take effect immediately
  const payload = {
    [`stream${streamId}`]: { osd: osdPayload },
    action: { restart_thread: ThreadVideo | ThreadOSD },
  };
  sendToEndpoint(payload);
}

function setFont(streamId) {
  const fontSizeInput = $(`#osd${streamId}_fontsize`);
  const strokeSizeInput = $(`#osd${streamId}_strokesize`);
  if (!fontSizeInput || !strokeSizeInput) return;

  const payload = {};

  const fontSize = Number(fontSizeInput.value);
  if (!Number.isNaN(fontSize)) {
    payload.font_size = fontSize;
  }

  const strokeSize = Number(strokeSizeInput.value);
  if (!Number.isNaN(strokeSize)) {
    payload.stroke_size = strokeSize;
  }

  if (Object.keys(payload).length === 0) return;
  console.log(ts(), "setFont for stream", streamId, ":", payload);
  // Font changes require Video + OSD thread restart for immediate effect
  const fullPayload = {
    [`stream${streamId}`]: { osd: payload },
    action: { restart_thread: ThreadVideo | ThreadOSD },
  };
  sendToEndpoint(fullPayload);
}

// Setup OSD controls for both stream0 and stream1. Skipped on the native
// OSD pages: a/streamer-osd.js wires these controls to timps /control
// directly (these handlers would POST to the json-prudynt.cgi bridge).
if (!nativeOsdPage)
[0, 1].forEach((streamId) => {
  // Configuration for OSD controls
  const osdControls = [
    {
      id: "enabled",
      handler: (e) => sendOsdUpdate(streamId, { enabled: e.target.checked }),
    },
    { id: "fontsize", handler: () => setFont(streamId) },
    { id: "strokesize", handler: () => setFont(streamId) },
    {
      id: "logo_enabled",
      handler: (e) =>
        sendOsdUpdate(streamId, { logo: { enabled: e.target.checked } }),
    },
    {
      id: "logo_position",
      handler: (e) =>
        sendOsdUpdate(streamId, { logo: { position: e.target.value } }),
    },
    {
      id: "time_enabled",
      handler: (e) =>
        sendOsdUpdate(streamId, { time: { enabled: e.target.checked } }),
    },
    {
      id: "time_format",
      handler: (e) =>
        sendOsdUpdate(streamId, { time: { format: e.target.value } }),
    },
    {
      id: "time_position",
      handler: (e) =>
        sendOsdUpdate(streamId, { time: { position: e.target.value } }),
    },
    {
      id: "time_fillcolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          time: { fill_color: osdColorValue(streamId, "time_fillcolor") },
        }),
    },
    {
      id: "time_fillcolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          time: { fill_color: osdColorValue(streamId, "time_fillcolor") },
        }),
    },
    {
      id: "time_strokecolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          time: { stroke_color: osdColorValue(streamId, "time_strokecolor") },
        }),
    },
    {
      id: "time_strokecolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          time: { stroke_color: osdColorValue(streamId, "time_strokecolor") },
        }),
    },
    {
      id: "uptime_enabled",
      handler: (e) =>
        sendOsdUpdate(streamId, { uptime: { enabled: e.target.checked } }),
    },
    {
      id: "uptime_position",
      handler: (e) =>
        sendOsdUpdate(streamId, { uptime: { position: e.target.value } }),
    },
    {
      id: "uptime_fillcolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          uptime: { fill_color: osdColorValue(streamId, "uptime_fillcolor") },
        }),
    },
    {
      id: "uptime_fillcolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          uptime: { fill_color: osdColorValue(streamId, "uptime_fillcolor") },
        }),
    },
    {
      id: "uptime_strokecolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          uptime: {
            stroke_color: osdColorValue(streamId, "uptime_strokecolor"),
          },
        }),
    },
    {
      id: "uptime_strokecolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          uptime: {
            stroke_color: osdColorValue(streamId, "uptime_strokecolor"),
          },
        }),
    },
    {
      id: "usertext_enabled",
      handler: (e) =>
        sendOsdUpdate(streamId, { usertext: { enabled: e.target.checked } }),
    },
    {
      id: "usertext_format",
      handler: (e) =>
        sendOsdUpdate(streamId, { usertext: { format: e.target.value } }),
    },
    {
      id: "usertext_position",
      handler: (e) =>
        sendOsdUpdate(streamId, { usertext: { position: e.target.value } }),
    },
    {
      id: "usertext_fillcolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          usertext: {
            fill_color: osdColorValue(streamId, "usertext_fillcolor"),
          },
        }),
    },
    {
      id: "usertext_fillcolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          usertext: {
            fill_color: osdColorValue(streamId, "usertext_fillcolor"),
          },
        }),
    },
    {
      id: "usertext_strokecolor",
      handler: () =>
        sendOsdUpdate(streamId, {
          usertext: {
            stroke_color: osdColorValue(streamId, "usertext_strokecolor"),
          },
        }),
    },
    {
      id: "usertext_strokecolor-alpha",
      handler: () =>
        sendOsdUpdate(streamId, {
          usertext: {
            stroke_color: osdColorValue(streamId, "usertext_strokecolor"),
          },
        }),
    },
  ];

  // Fields start disabled and are only re-enabled when the streamer's echo
  // contains them. The timps json-prudynt.cgi bridge echoes each stream's
  // OWN overlay set (timps keeps them per-stream) including
  // stroke_size/stroke_color (mapped to the timps text outline), so all
  // controls un-grey. With prudynt every field is echoed as before.
  osdControls.forEach(({ id, handler }) => {
    const el = $(`#osd${streamId}_${id}`);
    if (el) {
      el.addEventListener("change", handler);
      el.disabled = true;
    }
  });
});

// Image controls (WB and AE)
function saveImageValue(param) {
  const el = $("#image_" + param);
  if (!el) return;

  let value;
  if (el.type === "checkbox") {
    value = el.checked;
  } else if (el.type === "select-one") {
    value = parseInt(el.value);
  } else {
    value = parseInt(el.value);
  }

  const payload = { image: { [param]: value } };
  console.log(ts(), "Sending image param:", param, "=", value);
  sendToEndpoint(payload);
}

const imageParams = [
  "hflip",
  "vflip",
  "wb_bgain",
  "wb_rgain",
  "ae_compensation",
  "core_wb_mode",
];
imageParams.forEach((param) => {
  const el = $("#image_" + param);
  if (el) {
    // native image page: a/streamer-image.js owns these controls (they go
    // straight to timps /control, not through the json-prudynt.cgi bridge)
    if (nativeImagePage) return;
    el.addEventListener("change", () => {
      console.log("Image param changed:", param);
      saveImageValue(param);
    });
    // Disabled until the streamer's echo confirms the key: the timps
    // json-prudynt.cgi bridge only echoes image.* keys listed in the
    // caps.image capability array of GET /control, so controls the SoC
    // cannot drive never get re-enabled by setValue().
    el.disabled = true;
    const wrapper = el.closest(
      ".range, .number-range, .number, .select, .boolean, .file",
    );
    if (wrapper) wrapper.classList.add("disabled");
  }
});

// Export configuration button
const exportConfigBtn = $("#export-config");
if (exportConfigBtn) {
  exportConfigBtn.addEventListener("click", async () => {
    exportConfigBtn.disabled = true;
    try {
      // NATIVE: download the live timps /control snapshot as JSON (no
      // json-prudynt-config.cgi bridge).
      const json = window.timpsApi ? await window.timpsApi.get() : {};
      const blob = new Blob([JSON.stringify(json, null, 2)], {
        type: "application/json",
      });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = "timps-control.json";
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    } catch (err) {
      console.error("Export failed", err);
    } finally {
      exportConfigBtn.disabled = false;
    }
  });
}

// Save configuration button. timps persists every /control change to
// /etc/timps.conf immediately, so there is nothing to save explicitly - the
// button just confirms (no json-prudynt.cgi bridge).
const saveConfigBtn = $("#save-config");
if (saveConfigBtn) {
  saveConfigBtn.addEventListener("click", () => {
    if (typeof window.showAlert === "function") {
      window.showAlert(
        "success",
        "Nothing to do: settings are applied live and already saved to the streamer configuration.",
        4000,
      );
    } else {
      alert("Settings are applied live and already saved to the streamer configuration.");
    }
  });
}

// native image/OSD pages: the page scripts load their state from timps
// GET /control instead of the json-imaging.cgi bridge (the OSD pages have
// no imaging fields at all - skip the pointless bridge call there too)
if (!nativeImagePage && !nativeOsdPage) fetchImagingState();

// Add reload button handler
const reloadBtn = $("#preview-reload");
if (reloadBtn) {
  reloadBtn.addEventListener("click", () => {
    Promise.all([loadConfig(), loadMotorParams()]).then(() => {
      console.log("Configuration and motor parameters reloaded");
    });
  });
}
