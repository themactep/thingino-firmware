/**
 * SEI OSD Overlay Renderer
 *
 * Subscribes to /x/json-osd-sei.cgi SSE stream and renders OSD elements
 * as positioned HTML overlays on top of the MJPEG preview <img>.
 */
(function () {
  "use strict";

  const SSE_URL = "/x/json-osd-sei.cgi";
  const OVERLAY_ID = "sei-osd-overlay";
  const PREVIEW_IMG_ID = "preview";
  const FONT_SIZE = 14;

  let source = null;

  function resolvePos(rawPos, containerSize) {
    if (rawPos < 0) return Math.max(containerSize + rawPos, 0);
    if (rawPos === 0) return Math.max(containerSize / 2, 0);
    return rawPos;
  }

  function escapeHTML(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  function buildOverlayHTML(elements) {
    let html = "";
    for (const el of elements) {
      const cls =
        el.t === "gain" ? "sei-gain" : el.t === "timestamp" ? "sei-time" : "";
      html += `<div class="sei-el ${cls}" data-sei-x="${el.x}" data-sei-y="${el.y}"
        style="position:absolute;white-space:nowrap;pointer-events:none;
        color:#fff;font-family:monospace;
        text-shadow:-1px -1px 0 #000,1px -1px 0 #000,-1px 1px 0 #000,1px 1px 0 #000;
        ">${escapeHTML(el.text)}</div>`;
    }
    return html;
  }

  function reposition() {
    const img = document.getElementById(PREVIEW_IMG_ID);
    const overlay = document.getElementById(OVERLAY_ID);
    if (!img || !overlay) return;

    const rect = img.getBoundingClientRect();
    const scaleX = rect.width / (img.naturalWidth || rect.width || 1);
    const scaleY = rect.height / (img.naturalHeight || rect.height || 1);
    const fontSize = Math.round(FONT_SIZE * Math.min(scaleX, scaleY));

    overlay.style.left = rect.left + "px";
    overlay.style.top = rect.top + "px";
    overlay.style.width = rect.width + "px";
    overlay.style.height = rect.height + "px";

    for (const el of overlay.querySelectorAll(".sei-el")) {
      const rawX = parseFloat(el.dataset.seiX) || 0;
      const rawY = parseFloat(el.dataset.seiY) || 0;
      el.style.left = resolvePos(rawX, rect.width) + "px";
      el.style.top = resolvePos(rawY, rect.height) + "px";
      el.style.fontSize = fontSize + "px";
    }
  }

  function ensureOverlay() {
    let overlay = document.getElementById(OVERLAY_ID);
    const img = document.getElementById(PREVIEW_IMG_ID);
    if (!img) return overlay;

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
      if (!data || !data.elements || !data.elements.length) return;

      const overlay = ensureOverlay();
      if (!overlay) return;

      overlay.innerHTML = buildOverlayHTML(data.elements);
      reposition();
    } catch (_) {}
  }

  function start() {
    if (source) return;

    source = new EventSource(SSE_URL);
    source.onmessage = handleEvent;
    source.onerror = function () {
      source.close();
      source = null;
      setTimeout(start, 5000);
    };

    window.addEventListener("resize", reposition);
  }

  function stop() {
    if (source) {
      source.close();
      source = null;
    }
    window.removeEventListener("resize", reposition);
    const overlay = document.getElementById(OVERLAY_ID);
    if (overlay) overlay.remove();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
