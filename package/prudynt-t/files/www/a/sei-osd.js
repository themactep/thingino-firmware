(function () {
  "use strict";

  var API_KEY_PROMISE = fetch("/x/api-key.cgi", { cache: "no-store" })
    .then(function (r) {
      return r.json();
    })
    .then(function (d) {
      return d.exists && d.api_key ? d.api_key : "";
    })
    .catch(function () {
      return "";
    });
  var API_BASE = "http://" + location.hostname + ":8080/api/v1/config";

  async function apiFetch(url, options) {
    var key = await API_KEY_PROMISE;
    options = options || {};
    options.headers = options.headers || {};
    if (key) options.headers["X-API-Key"] = key;
    return fetch(url, options);
  }
  const SSE_URL = "/x/json-osd-sei.cgi";
  const OVERLAY_ID = "sei-osd-overlay";
  const PREVIEW_IMG_ID = "preview";
  const FONT_SIZE = 14;

  let source = null;
  let started = false;
  let lastData = null;

  function visualSettings() {
    try {
      return JSON.parse(localStorage.getItem("sei-osd-settings") || "{}");
    } catch (_) {
      return {};
    }
  }

  function resolvePos(rawPos, containerSize, scale) {
    var px = rawPos * scale;
    if (rawPos < 0) return Math.max(containerSize + px, 0);
    if (rawPos === 0) return Math.max(containerSize / 2, 0);
    return px;
  }

  function escapeHTML(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  function buildOverlayHTML(elements) {
    const vis = visualSettings();
    const fs = parseInt(vis.fs, 10) || FONT_SIZE;
    const fc = vis.fc || "#ffffff";
    const sc = vis.sc || "#000000";
    const stw = parseInt(vis.stw, 10) || 1;
    const shadow = ["-1", "1"]
      .map((sx) =>
        ["-1", "1"]
          .map((sy) => `${sx * stw}px ${sy * stw}px 0 ${sc}`)
          .join(","),
      )
      .join(",");
    let html = "";
    for (const el of elements) {
      const cls =
        el.t === "gain" ? "sei-gain" : el.t === "timestamp" ? "sei-time" : "";
      html += `<div class="sei-el ${cls}" data-sei-x="${el.x}" data-sei-y="${el.y}"
        style="position:absolute;white-space:nowrap;pointer-events:none;
        color:${fc};font-family:monospace;font-size:${fs}px;
        text-shadow:${shadow};
        ">${escapeHTML(el.text)}</div>`;
    }
    return html;
  }

  function reposition() {
    const img = document.getElementById(PREVIEW_IMG_ID);
    const overlay = document.getElementById(OVERLAY_ID);
    if (!img || !overlay) return;

    const rect = img.getBoundingClientRect();
    const sw = (lastData && lastData.sw) || img.naturalWidth || rect.width || 1;
    const sh = (lastData && lastData.sh) || img.naturalHeight || rect.height || 1;
    const scale = Math.min(rect.width / sw, rect.height / sh);
    const vis = visualSettings();
    const baseFs =
      parseInt(overlay.dataset.fs, 10) || parseInt(vis.fs, 10) || FONT_SIZE;
    const fontSize = Math.round(baseFs * scale);

    overlay.style.left = "0";
    overlay.style.top = "0";
    overlay.style.width = rect.width + "px";
    overlay.style.height = rect.height + "px";

    for (const el of overlay.querySelectorAll(".sei-el")) {
      const rawX = parseFloat(el.dataset.seiX) || 0;
      const rawY = parseFloat(el.dataset.seiY) || 0;
      el.style.left = resolvePos(rawX, rect.width, scale) + "px";
      el.style.top = resolvePos(rawY, rect.height, scale) + "px";
      el.style.fontSize = fontSize + "px";
    }
  }

  function ensureOverlay() {
    let overlay = document.getElementById(OVERLAY_ID);
    const img = document.getElementById(PREVIEW_IMG_ID);
    if (!img) return null;

    if (!overlay) {
      const wrapper = document.createElement("div");
      wrapper.style.cssText = "position:relative;display:inline-block;";
      img.parentNode.insertBefore(wrapper, img);
      wrapper.appendChild(img);

      overlay = document.createElement("div");
      overlay.id = OVERLAY_ID;
      overlay.style.cssText =
        "position:absolute;left:0;top:0;pointer-events:none;overflow:hidden;z-index:10;";
      wrapper.appendChild(overlay);
    }
    return overlay;
  }

  function handleEvent(event) {
    try {
      const data = JSON.parse(event.data);
      lastData = data;
      if (!data || !data.elements || !data.elements.length) {
        hideOverlay();
        return;
      }

      const overlay = ensureOverlay();
      if (!overlay) return;

      overlay.style.display = "";
      overlay.innerHTML = buildOverlayHTML(data.elements);
      reposition();
    } catch (_) {}
  }

  function hideOverlay() {
    const overlay = document.getElementById(OVERLAY_ID);
    if (overlay) overlay.style.display = "none";
  }

  function sseStart() {
    if (source) return;

    source = new EventSource(SSE_URL);
    source.onmessage = handleEvent;
    source.onerror = function () {
      source.close();
      source = null;
      setTimeout(sseStart, 5000);
    };

    window.addEventListener("resize", reposition);
    started = true;
  }

  function sseStop() {
    if (source) {
      source.close();
      source = null;
    }
    window.removeEventListener("resize", reposition);
    const overlay = document.getElementById(OVERLAY_ID);
    if (overlay) overlay.remove();
    started = false;
  }

  async function checkAndStart() {
    try {
      var r = await apiFetch(API_BASE, {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ osd: { sei: { enabled: null } } }),
      });
      var data = await r.json();
      if (data && data.sei && data.sei.enabled === true) {
        sseStart();
      } else {
        sseStop();
      }
    } catch (e) {
      sseStop();
    }
  }

  window.SeiOSD = {
    start: sseStart,
    stop: sseStop,
    restart: function () {
      sseStop();
      checkAndStart();
    },
    repaint: function () {
      const overlay = document.getElementById(OVERLAY_ID);
      if (
        !overlay ||
        !lastData ||
        !lastData.elements ||
        !lastData.elements.length
      )
        return;
      overlay.innerHTML = buildOverlayHTML(lastData.elements);
      reposition();
    },
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", checkAndStart);
  } else {
    checkAndStart();
  }
})();
