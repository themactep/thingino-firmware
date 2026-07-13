/* privacy.js - NATIVE privacy-mask VISUAL editor. Talks directly to the timps
 * streamer over window.timpsApi (GET/POST /control, per-boot token) - no bridge.
 *
 * Privacy masks are solid cover rectangles per video stream (timps "privacy"
 * section: privacy<S>.<N>.{enabled,x,y,w,h,color}, caps.privacy = {available,
 * max_regions}). This page shows a live snapshot of the selected stream and
 * lets you drag/resize the mask rectangles directly on it; every change is
 * applied LIVE via timpsApi.set({privacy:{<s>:{<n>:{...}}}}). A side list gives
 * per-mask enable / colour / alpha / exact coordinates / delete.
 *
 * Coordinates are the stream's own pixels; the editor scales them to the
 * displayed snapshot. Dependency-free, pointer events (mouse + touch).
 */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-privacy") return;

  var MIN = 8;                 // smallest mask edge, stream px
  var maxRegions = 4;
  var streamIdx = 0;
  var streamW = 1920, streamH = 1080;
  var regions = [];            // [{enabled,x,y,w,h,color}] in STREAM coords
  var selected = -1;

  var stage = document.getElementById("pm-stage");
  var img = document.getElementById("pm-img");
  var noimg = document.getElementById("pm-noimg");
  var list = document.getElementById("pm-list");
  var streamSel = document.getElementById("pm-stream");
  var addBtn = document.getElementById("pm-add");
  var reloadBtn = document.getElementById("pm-reload");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[privacy]", type + ":", msg);
  }

  // timps color 0xAARRGGBB <-> {rgb:"#RRGGBB", alpha:0..255}
  function colorToTimps(rgb, alpha) {
    var m = /^#([0-9a-fA-F]{6})$/.exec(String(rgb || ""));
    var body = m ? m[1].toUpperCase() : "000000";
    var a = Math.max(0, Math.min(255, parseInt(alpha, 10)));
    if (isNaN(a)) a = 255;
    return "0x" + a.toString(16).padStart(2, "0").toUpperCase() + body;
  }
  function colorFromTimps(v) {
    var m = /^0x([0-9a-fA-F]{2})([0-9a-fA-F]{6})$/.exec(String(v || ""));
    if (!m) return { rgb: "#000000", alpha: 255 };
    return { rgb: "#" + m[2].toUpperCase(), alpha: parseInt(m[1], 16) };
  }

  function scale() {
    var dw = img.clientWidth || stage.clientWidth || 1;
    var dh = img.clientHeight || (dw * streamH / streamW);
    return { sx: dw / streamW, sy: dh / streamH, dw: dw, dh: dh };
  }

  function clampRegion(r) {
    r.w = Math.max(MIN, Math.min(streamW, Math.round(r.w)));
    r.h = Math.max(MIN, Math.min(streamH, Math.round(r.h)));
    r.x = Math.max(0, Math.min(streamW - r.w, Math.round(r.x)));
    r.y = Math.max(0, Math.min(streamH - r.h, Math.round(r.y)));
  }

  function send(n) {
    var r = regions[n];
    var payload = {}; payload[streamIdx] = {};
    payload[streamIdx][n] = {
      enabled: r.enabled ? 1 : 0,
      x: r.x, y: r.y, w: r.w, h: r.h, color: r.color,
    };
    window.timpsApi.set({ privacy: payload }).catch(function (err) {
      console.error("privacy set failed:", err);
      toast("danger", "Failed to update mask: " + (err.message || err));
    });
  }

  /* ---- rendering ---- */

  function renderBoxes() {
    // drop existing boxes (keep img + noimg)
    Array.prototype.slice.call(stage.querySelectorAll(".pm-box")).forEach(function (b) { b.remove(); });
    var s = scale();
    regions.forEach(function (r, n) {
      if (!r.enabled || r.w <= 0 || r.h <= 0) return;
      var box = document.createElement("div");
      box.className = "pm-box" + (n === selected ? " sel" : "");
      box.dataset.n = String(n);
      positionBox(box, r, s);
      box.innerHTML =
        '<span class="pm-tag">Mask ' + (n + 1) + "</span>" +
        '<div class="pm-handle"></div>';
      stage.appendChild(box);
      wireBox(box, n);
    });
  }

  function positionBox(box, r, s) {
    box.style.left = r.x * s.sx + "px";
    box.style.top = r.y * s.sy + "px";
    box.style.width = r.w * s.sx + "px";
    box.style.height = r.h * s.sy + "px";
  }

  function renderList() {
    list.innerHTML = "";
    regions.forEach(function (r, n) {
      var c = colorFromTimps(r.color);
      var card = document.createElement("div");
      card.className = "card mb-2" + (n === selected ? " border-warning" : "");
      card.innerHTML =
        '<div class="card-body p-2">' +
        '<div class="d-flex align-items-center gap-2 mb-1">' +
        '<div class="form-check form-switch mb-0">' +
        '<input class="form-check-input" type="checkbox" id="pm-en-' + n + '"' + (r.enabled ? " checked" : "") + ">" +
        '<label class="form-check-label small" for="pm-en-' + n + '">Mask ' + (n + 1) + "</label></div>" +
        '<input type="color" class="form-control form-control-color form-control-sm" id="pm-col-' + n + '" value="' + c.rgb + '" title="Fill color">' +
        '<input type="number" class="form-control form-control-sm" style="max-width:5rem" id="pm-al-' + n + '" min="0" max="255" value="' + c.alpha + '" title="Alpha">' +
        '<button type="button" class="btn btn-outline-danger btn-sm ms-auto" id="pm-del-' + n + '" title="Disable mask"><i class="bi bi-trash"></i></button>' +
        "</div>" +
        '<div class="row g-1">' +
        coord("pm-x-" + n, "X", r.x) + coord("pm-y-" + n, "Y", r.y) +
        coord("pm-w-" + n, "W", r.w) + coord("pm-h-" + n, "H", r.h) +
        "</div></div>";
      list.appendChild(card);
      wireListRow(n);
    });
  }

  function coord(id, label, val) {
    return '<div class="col-3"><label class="form-label small mb-0" for="' + id + '">' + label +
      '</label><input type="number" min="0" class="form-control form-control-sm" id="' + id + '" value="' + val + '"></div>';
  }

  function render() {
    renderBoxes();
    renderList();
  }

  /* ---- interaction: drag to move, corner handle to resize ---- */

  function wireBox(box, n) {
    box.addEventListener("pointerdown", function (ev) {
      if (ev.target.classList.contains("pm-handle")) return; // handled below
      startDrag(ev, n, "move");
    });
    var handle = box.querySelector(".pm-handle");
    handle.addEventListener("pointerdown", function (ev) {
      ev.stopPropagation();
      startDrag(ev, n, "resize");
    });
  }

  function startDrag(ev, n, mode) {
    ev.preventDefault();
    select(n);
    var s = scale();
    var r = regions[n];
    var start = { px: ev.clientX, py: ev.clientY, x: r.x, y: r.y, w: r.w, h: r.h };
    var box = stage.querySelector('.pm-box[data-n="' + n + '"]');
    try { ev.target.setPointerCapture(ev.pointerId); } catch (e) { /* ok */ }

    function move(e) {
      var ddx = (e.clientX - start.px) / s.sx;
      var ddy = (e.clientY - start.py) / s.sy;
      if (mode === "move") { r.x = start.x + ddx; r.y = start.y + ddy; }
      else { r.w = start.w + ddx; r.h = start.h + ddy; }
      clampRegion(r);
      if (box) positionBox(box, r, s);
      syncCoordInputs(n);
    }
    function up(e) {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      try { ev.target.releasePointerCapture(e.pointerId); } catch (er) { /* ok */ }
      send(n);
    }
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  function syncCoordInputs(n) {
    var r = regions[n];
    setVal("pm-x-" + n, r.x); setVal("pm-y-" + n, r.y);
    setVal("pm-w-" + n, r.w); setVal("pm-h-" + n, r.h);
  }
  function setVal(id, v) { var el = document.getElementById(id); if (el) el.value = v; }

  function select(n) {
    selected = n;
    Array.prototype.slice.call(stage.querySelectorAll(".pm-box")).forEach(function (b) {
      b.classList.toggle("sel", b.dataset.n === String(n));
    });
    Array.prototype.slice.call(list.querySelectorAll(".card")).forEach(function (c, i) {
      c.classList.toggle("border-warning", i === n);
    });
  }

  function wireListRow(n) {
    var r = regions[n];
    var en = document.getElementById("pm-en-" + n);
    if (en) en.addEventListener("change", function () {
      r.enabled = en.checked ? 1 : 0;
      if (r.enabled && (r.w < MIN || r.h < MIN)) defaultRect(r);
      send(n); render(); select(n);
    });
    var colEl = document.getElementById("pm-col-" + n);
    var alEl = document.getElementById("pm-al-" + n);
    function colorChanged() {
      r.color = colorToTimps(colEl && colEl.value, alEl && alEl.value);
      send(n); renderBoxes();
    }
    if (colEl) colEl.addEventListener("change", colorChanged);
    if (alEl) alEl.addEventListener("change", colorChanged);
    var del = document.getElementById("pm-del-" + n);
    if (del) del.addEventListener("click", function () {
      r.enabled = 0; send(n); render();
    });
    ["x", "y", "w", "h"].forEach(function (k) {
      var el = document.getElementById("pm-" + k + "-" + n);
      if (!el) return;
      el.addEventListener("change", function () {
        var v = parseInt(el.value, 10); if (isNaN(v)) return;
        r[k] = v; clampRegion(r); send(n); render(); select(n);
      });
    });
  }

  function defaultRect(r) {
    r.w = Math.round(streamW * 0.25);
    r.h = Math.round(streamH * 0.25);
    r.x = Math.round((streamW - r.w) / 2);
    r.y = Math.round((streamH - r.h) / 2);
  }

  function addMask() {
    var n = regions.findIndex(function (r) { return !r.enabled; });
    if (n < 0) { toast("warning", "All " + maxRegions + " masks are in use on this stream."); return; }
    var r = regions[n];
    r.enabled = 1;
    if (!r.color) r.color = "0xFF000000";
    defaultRect(r);
    send(n); render(); select(n);
  }

  /* ---- snapshot ---- */

  function setSnapshot() {
    window.timpsApi.token().then(function (tok) {
      var url = window.timpsApi.base() + "/snapshot.jpg?chn=" + streamIdx +
        (tok ? "&token=" + encodeURIComponent(tok) : "") + "&_=" + Date.now();
      img.onload = function () { if (noimg) noimg.classList.add("d-none"); renderBoxes(); };
      img.onerror = function () { if (noimg) noimg.classList.remove("d-none"); };
      img.src = url;
    });
  }

  /* ---- load ---- */

  function markUnavailable(msg) {
    var el = document.getElementById("privacy-unavailable");
    if (el) { el.classList.remove("d-none"); if (msg) el.textContent = msg; }
    if (addBtn) addBtn.disabled = true;
    if (streamSel) streamSel.disabled = true;
  }

  function load() {
    if (!window.timpsApi) { markUnavailable("timps-api.js not loaded."); return; }
    window.timpsApi.get().then(function (json) {
      var caps = (json.caps && json.caps.privacy) || null;
      if (caps && caps.available === 0) { markUnavailable(); return; }
      if (caps && caps.max_regions > 0) maxRegions = Math.min(caps.max_regions, 8);
      var maxSpan = document.getElementById("privacy-max");
      if (maxSpan) maxSpan.textContent = String(maxRegions);

      var v = (json.video && (json.video[streamIdx] || json.video[String(streamIdx)])) || {};
      if (v.width > 0 && v.height > 0) { streamW = v.width; streamH = v.height; }
      stage.style.aspectRatio = streamW + " / " + streamH;

      var priv = (json.privacy && (json.privacy[streamIdx] || json.privacy[String(streamIdx)])) || {};
      regions = [];
      for (var n = 0; n < maxRegions; n++) {
        var r = priv[n] || priv[String(n)] || {};
        regions.push({
          enabled: Number(r.enabled) || 0,
          x: Number(r.x) || 0, y: Number(r.y) || 0,
          w: Number(r.w) || 0, h: Number(r.h) || 0,
          color: r.color || "0xFF000000",
        });
      }
      selected = regions.findIndex(function (r) { return r.enabled; });
      var off = document.getElementById("privacy-unavailable");
      if (off) off.classList.add("d-none");
      setSnapshot();
      render();
    }).catch(function (err) {
      console.warn("timps unreachable:", err);
      markUnavailable("The streamer is not reachable; reload once it is running.");
    });
  }

  if (streamSel) streamSel.addEventListener("change", function () {
    streamIdx = parseInt(streamSel.value, 10) || 0;
    load();
  });
  if (addBtn) addBtn.addEventListener("click", addMask);
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  window.addEventListener("resize", renderBoxes);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
