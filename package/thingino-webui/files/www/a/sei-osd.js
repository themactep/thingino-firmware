/**
 * SEI OSD Overlay Renderer
 *
 * Polls /api/v1/osd-sei and renders OSD elements as positioned HTML
 * overlays on top of the MJPEG preview <img>.
 */
(function () {
  "use strict";

  const POLL_INTERVAL_MS = 1000;
  const OVERLAY_ID = "sei-osd-overlay";
  const PREVIEW_IMG_ID = "preview";

  let timer = null;

  /** Resolve negative / centered positions relative to container size */
  function resolvePos(rawPos, elemSize, containerSize) {
    if (rawPos < 0) return Math.max(containerSize - elemSize + rawPos, 0);
    if (rawPos === 0) return Math.max((containerSize - elemSize) / 2, 0);
    return rawPos;
  }

  /** Parse "#RRGGBBAA" color to CSS rgba() */
  function parseColor(hex) {
    if (!hex || hex.length < 7) return "rgba(255,255,255,0.8)";
    const r = parseInt(hex.slice(1, 3), 16);
    const g = parseInt(hex.slice(3, 5), 16);
    const b = parseInt(hex.slice(5, 7), 16);
    const a = hex.length >= 9 ? parseInt(hex.slice(7, 9), 16) / 255 : 1;
    return `rgba(${r},${g},${b},${a})`;
  }

  function buildOverlayHTML(elements) {
    let html = "";
    for (const el of elements) {
      html += `<div data-sei-type="${el.t}" style="
          position:absolute;
          left:${el.x}px; top:${el.y}px;
          width:${el.w}px; height:${el.h}px;
          color:${parseColor(el.color)};
          font-family:monospace;
          font-size:${el.h * 0.72}px;
          line-height:${el.h}px;
          white-space:nowrap;
          pointer-events:none;
          text-shadow:
            -1px -1px 0 ${parseColor(el.stroke)},
             1px -1px 0 ${parseColor(el.stroke)},
            -1px  1px 0 ${parseColor(el.stroke)},
             1px  1px 0 ${parseColor(el.stroke)};
        ">${escapeHTML(el.text)}</div>`;
    }
    return html;
  }

  function escapeHTML(str) {
    const div = document.createElement("div");
    div.textContent = str;
    return div.innerHTML;
  }

  /** Position overlay elements relative to the preview image */
  function reposition() {
    const img = document.getElementById(PREVIEW_IMG_ID);
    const overlay = document.getElementById(OVERLAY_ID);
    if (!img || !overlay) return;

    const rect = img.getBoundingClientRect();
    const imgW = img.naturalWidth || rect.width;
    const imgH = img.naturalHeight || rect.height;
    const scaleX = rect.width / (imgW || 1);
    const scaleY = rect.height / (imgH || 1);

    overlay.style.left = rect.left + "px";
    overlay.style.top = rect.top + "px";
    overlay.style.width = rect.width + "px";
    overlay.style.height = rect.height + "px";

    const children = overlay.children;
    for (let i = 0; i < children.length; i++) {
      const el = children[i];
      const rawX = parseFloat(el.dataset.rawX) || 0;
      const rawY = parseFloat(el.dataset.rawY) || 0;
      const rawW = parseFloat(el.dataset.rawW) || 0;
      const rawH = parseFloat(el.dataset.rawH) || 0;

      const x = resolvePos(rawX, rawW * scaleX, rect.width);
      const y = resolvePos(rawY, rawH * scaleY, rect.height);

      el.style.left = x + "px";
      el.style.top = y + "px";
      el.style.width = rawW * scaleX + "px";
      el.style.height = rawH * scaleY + "px";
      el.style.fontSize = rawH * scaleY * 0.72 + "px";
      el.style.lineHeight = rawH * scaleY + "px";
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

      // Create overlay container if needed
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

      // Store raw positions on elements for repositioning
      overlay.innerHTML = buildOverlayHTML(data.elements);
      const children = overlay.children;
      for (let i = 0; i < children.length; i++) {
        children[i].dataset.rawX = data.elements[i].x;
        children[i].dataset.rawY = data.elements[i].y;
        children[i].dataset.rawW = data.elements[i].w;
        children[i].dataset.rawH = data.elements[i].h;
      }

      reposition();
    } catch (_) {
      // Silently ignore network/parse errors
    }
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

  // Start when DOM is ready
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", start);
  } else {
    start();
  }
})();
