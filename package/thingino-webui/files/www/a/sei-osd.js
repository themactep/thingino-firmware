/**
 * SEI OSD Overlay Renderer
 *
 * Polls /api/v1/osd-sei and renders OSD elements as positioned HTML
 * overlays on top of the MJPEG preview <img>.
 * Works with the simplified SEI format: { t, text, x, y }
 */
(function () {
  "use strict";

  const POLL_INTERVAL_MS = 1000;
  const OVERLAY_ID = "sei-osd-overlay";
  const PREVIEW_IMG_ID = "preview";
  const FONT_SIZE = 14; // px base size, scaled with image

  let timer = null;

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

  async function poll() {
    try {
      const resp = await fetch("/api/v1/osd-sei");
      if (!resp.ok) return;
      const data = await resp.json();
      if (!data || !data.elements || !data.elements.length) return;

      let overlay = document.getElementById(OVERLAY_ID);
      const img = document.getElementById(PREVIEW_IMG_ID);
      if (!img) return;

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

      overlay.innerHTML = buildOverlayHTML(data.elements);
      reposition();
    } catch (_) {}
  }

  function start() {
    if (timer) return;
    poll();
    timer = setInterval(poll, POLL_INTERVAL_MS);
    window.addEventListener("resize", reposition);
  }

  function stop() {
    if (timer) {
      clearInterval(timer);
      timer = null;
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
