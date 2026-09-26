// privacy.js - privacy-mask editor, "Privacy masks" tab of streamer-overlays.html.
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-overlays" || !window.timpsUi) return;

  var MIN = 8;                 // smallest mask edge, stream px
  var maxRegions = 4;
  var streamIdx = window.timpsUi.stream();
  var streamW = 1920, streamH = 1080;
  var linkEl = document.getElementById("osd-link"); // page-wide "both streams" switch
  var otherW = 0, otherH = 0;  // other stream's resolution (for scaling)
  var regions = [];            // [{enabled,x,y,w,h,color}] in STREAM coords
  var selected = -1;
  var dragging = false;        // true while a box move/resize drag is live

  var stage = document.getElementById("frame");   // boxes sit over the live preview
  var img = document.getElementById("preview");
  var list = document.getElementById("pm-list");
  var addBtn = document.getElementById("pm-add");

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

  function clampRegionTo(r, W, H) {
    r.w = Math.max(MIN, Math.min(W, Math.round(r.w)));
    r.h = Math.max(MIN, Math.min(H, Math.round(r.h)));
    r.x = Math.max(0, Math.min(W - r.w, Math.round(r.x)));
    r.y = Math.max(0, Math.min(H - r.h, Math.round(r.y)));
  }
  function clampRegion(r) { clampRegionTo(r, streamW, streamH); }

  function send(n) {
    var r = regions[n];
    var payload = {}; payload[streamIdx] = {};
    payload[streamIdx][n] = {
      enabled: r.enabled ? 1 : 0,
      x: r.x, y: r.y, w: r.w, h: r.h, color: r.color,
    };
    // "apply to both": mirror the mask onto the other stream, scaled to its
    // resolution (streams differ, e.g. 1920x1080 main vs 640x360 sub).
    if (linkEl && linkEl.checked && otherW > 0 && otherH > 0) {
      var o = 1 - streamIdx;               // only two video streams
      var fx = otherW / streamW, fy = otherH / streamH;
      // scale, then clamp against the OTHER stream's bounds + MIN so the mirror
      // can't round past its width/height or shrink below the minimum edge.
      var mr = { x: r.x * fx, y: r.y * fy, w: r.w * fx, h: r.h * fy };
      clampRegionTo(mr, otherW, otherH);
      payload[o] = {};
      payload[o][n] = {
        enabled: r.enabled ? 1 : 0,
        x: mr.x, y: mr.y, w: mr.w, h: mr.h,
        color: r.color,
      };
    }
    window.timpsApi.set({ privacy: payload }).then(function (r) {
      var corr = r && r.corrections;
      if (corr) {
        var redraw = false;
        Object.keys(corr).forEach(function (k) {
          var parts = k.split(".");           // ["privacy0", "3", "x"]
          if (parts.length !== 3 || parts[0] !== "privacy" + streamIdx) return;
          var reg = regions[parseInt(parts[1], 10)];
          var f = parts[2];
          if (!reg) return;
          if (f === "enabled") reg.enabled = !!Number(corr[k]);
          else if (f === "color") reg.color = corr[k];
          else if (f === "x" || f === "y" || f === "w" || f === "h")
            reg[f] = Number(corr[k]);
          redraw = true;
        });
        if (redraw) renderBoxes();
        var t = window.timpsApi.takeCorrections(r);
        if (t) toast("info", window.timpsApi.correctionsText(t));
      }
    }, function (err) {
      console.error("privacy set failed:", err);
      toast("danger", "Failed to update mask: " + (err.message || err));
    });
  }

  /* ---- rendering ---- */

  function renderBoxes() {
    // drop existing mask boxes
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

  var shown = {};              // mask slots listed for this stream
  function inUse(r) { return r.enabled || (r.w > 0 && r.h > 0); }

  function renderList() {
    list.innerHTML = "";
    var count = 0;
    regions.forEach(function (r, n) {
      if (!shown[n]) return;
      count++;
      var c = colorFromTimps(r.color), open = n === selected;
      var w = document.createElement("div");
      w.className = "tv-item mb-2" + (open ? " open" : "");
      w.setAttribute("data-n", String(n));
      w.innerHTML =
        '<div class="tv-ih"><div class="form-check form-switch m-0">' +
        '<input class="form-check-input" type="checkbox" role="switch" id="pm-en-' + n + '" aria-label="Show mask"' +
        (r.enabled ? " checked" : "") + "></div>" +
        '<span class="pm-swatch" style="background:' + c.rgb + ";opacity:" + Math.max(0.15, c.alpha / 255) + '"></span>' +
        '<span class="tv-tx">Mask ' + (n + 1) + "</span>" +
        '<span class="tv-pos">' + posText(r) + "</span>" +
        (r.enabled ? '<span class="badge text-bg-success">On</span>' : '<span class="badge text-bg-secondary">Off</span>') +
        "</div>";
      if (open) {
        var ib = document.createElement("div");
        ib.className = "tv-ib";
        ib.innerHTML = '<div class="tv-fields">' +
          coord("pm-x-" + n, "From left", r.x) + coord("pm-y-" + n, "From top", r.y) +
          coord("pm-w-" + n, "Width", r.w) + coord("pm-h-" + n, "Height", r.h) +
          '<div><label>Colour</label><div class="d-flex gap-2 align-items-center">' +
          '<input type="color" class="form-control form-control-color" id="pm-col-' + n + '" value="' + c.rgb + '">' +
          '<input type="range" min="0" max="255" class="form-range" id="pm-al-' + n + '" value="' + c.alpha + '" title="Opacity"></div></div>' +
          "</div>" +
          '<div class="d-flex flex-wrap align-items-center gap-2 mt-2"><span class="tv-cfg me-auto">' + cfgText(n, r) + "</span>" +
          '<button type="button" class="btn btn-sm btn-outline-danger" id="pm-del-' + n + '"><i class="bi bi-trash me-1"></i>Remove</button></div>';
        w.appendChild(ib);
      }
      w.querySelector(".tv-ih").addEventListener("click", function (e) {
        if (e.target.closest(".form-check")) return;
        select(selected === n ? -1 : n);
        if (selected >= 0) stage.focus({ preventScroll: true });
      });
      list.appendChild(w);
      wireListRow(n);
    });
    var empty = document.getElementById("pm-empty");
    if (empty) empty.classList.toggle("d-none", count > 0);
    if (addBtn) addBtn.disabled = count >= maxRegions;
  }

  function posText(r) { return r.x + "," + r.y + " · " + r.w + "×" + r.h; }
  function cfgText(n, r) { return "privacy" + streamIdx + "." + n + ": x=" + r.x + ", y=" + r.y + ", w=" + r.w + ", h=" + r.h; }

  function coord(id, label, val) {
    return '<div><label for="' + id + '">' + label + '</label><input type="number" min="0" class="form-control" id="' +
      id + '" value="' + val + '"></div>';
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
    dragging = true;
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
      dragging = false;
      send(n);
      stage.focus({ preventScroll: true });
    }
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  function syncCoordInputs(n) {
    var r = regions[n];
    var row = list.querySelector('.tv-item[data-n="' + n + '"]');
    if (row) {
      var p = row.querySelector(".tv-pos"), c = row.querySelector(".tv-cfg");
      if (p) p.textContent = posText(r);
      if (c) c.textContent = cfgText(n, r);
    }
    setVal("pm-x-" + n, r.x); setVal("pm-y-" + n, r.y);
    setVal("pm-w-" + n, r.w); setVal("pm-h-" + n, r.h);
  }
  function setVal(id, v) { var el = document.getElementById(id); if (el) el.value = v; }

  // arrows move the selected mask, Ctrl/Cmd+arrows resize it (Alt+Left is "back"); Shift = 10 px
  var nudgeTimer = null;
  function nudge(e) {
    if (document.body.getAttribute("data-pane") !== "privacy" || selected < 0) return;
    var d = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    var r = regions[selected];
    if (!d || !r || !r.enabled) return;
    e.preventDefault();
    var step = e.shiftKey ? 10 : 1, n = selected;
    if (e.ctrlKey || e.metaKey) { r.w += d[0] * step; r.h += d[1] * step; }
    else { r.x += d[0] * step; r.y += d[1] * step; }
    clampRegion(r);
    var box = stage.querySelector('.pm-box[data-n="' + n + '"]');
    if (box) positionBox(box, r, scale());
    syncCoordInputs(n);
    clearTimeout(nudgeTimer);
    nudgeTimer = setTimeout(function () { send(n); }, 300);
  }
  stage.addEventListener("keydown", nudge);

  function select(n) {
    if (selected === n) return;
    selected = n;
    Array.prototype.slice.call(stage.querySelectorAll(".pm-box")).forEach(function (b) {
      b.classList.toggle("sel", b.dataset.n === String(n));
    });
    renderList();
  }

  function wireListRow(n) {
    var r = regions[n];
    var en = document.getElementById("pm-en-" + n);
    if (en) en.addEventListener("change", function () {
      r.enabled = en.checked ? 1 : 0;
      if (r.enabled && (r.w < MIN || r.h < MIN)) defaultRect(r);
      send(n); render();
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
      r.enabled = 0; delete shown[n]; if (selected === n) selected = -1;
      send(n); render();
    });
    ["x", "y", "w", "h"].forEach(function (k) {
      var el = document.getElementById("pm-" + k + "-" + n);
      if (!el) return;
      el.addEventListener("change", function () {
        var v = parseInt(el.value, 10); if (isNaN(v)) return;
        r[k] = v; clampRegion(r); send(n); render();
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
    var n = -1;
    regions.forEach(function (r, i) { if (n < 0 && !shown[i]) n = i; });
    if (n < 0) n = regions.findIndex(function (r) { return !r.enabled; });
    if (n < 0) { toast("warning", "All " + maxRegions + " masks are in use on this stream."); return; }
    var r = regions[n];
    r.enabled = 1;
    if (!r.color) r.color = "0xFF000000";
    defaultRect(r);
    shown[n] = true;
    send(n); render(); select(n);
  }

  /* ---- load ---- */

  // Captured before any markUnavailable(msg) can overwrite it with textContent,
  // so markAvailable() can put the original markup (icon included) back.
  var unavailEl = document.getElementById("privacy-unavailable");
  var unavailHtml = unavailEl ? unavailEl.innerHTML : "";

  function markUnavailable(msg) {
    if (unavailEl) {
      unavailEl.classList.remove("d-none");
      if (msg) unavailEl.textContent = msg;
    }
    if (addBtn) addBtn.disabled = true;
  }

  // Exact inverse of markUnavailable(), run on every successful load() -
  // fixes a real transient-unavailability bug during a streamer restart.
  // See WEBUI-NOTES.md.
  function markAvailable() {
    if (unavailEl) {
      unavailEl.classList.add("d-none");
      unavailEl.innerHTML = unavailHtml;
    }
    if (addBtn) addBtn.disabled = false;
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

      // other stream's resolution, for the "apply to both" scaling
      var ovi = 1 - streamIdx;
      var ov = (json.video && (json.video[ovi] || json.video[String(ovi)])) || {};
      otherW = ov.width > 0 ? ov.width : 0;
      otherH = ov.height > 0 ? ov.height : 0;

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
      var keep = selected;
      shown = {};
      regions.forEach(function (r, i) { if (inUse(r)) shown[i] = true; });
      selected = shown[keep] ? keep : -1;
      markAvailable();
      render();
    }).catch(function (err) {
      console.warn("timps unreachable:", err);
      markUnavailable("The streamer is not reachable; reload once it is running.");
    });
  }

  /* ---- live sync: another open tab/client editing a mask on this stream --- */

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; }
    var m = /^privacy(\d+)\.(\d+)\.(\w+)$/.exec(data.key || "");
    if (!m) return;
    var s = Number(m[1]), n = Number(m[2]), leaf = m[3];
    if (s !== streamIdx || n < 0 || n >= regions.length || dragging) return;
    var ae = document.activeElement;
    // don't fight the user mid-drag/mid-edit of this same mask's list row
    if (ae && ae.id && ae.id.indexOf("pm-") === 0) return;
    var r = regions[n];
    if (leaf === "enabled") r.enabled = (data.value === "1" || data.value === "true") ? 1 : 0;
    else if (leaf === "x" || leaf === "y" || leaf === "w" || leaf === "h")
      r[leaf] = parseInt(data.value, 10) || 0;
    else if (leaf === "color") r.color = data.value;
    else return;
    render();
  }

  document.addEventListener("timps-stream", function (e) {
    streamIdx = e.detail;
    selected = -1;
    load();
  });
  if (addBtn) addBtn.addEventListener("click", addMask);
  img.addEventListener("load", function () { if (!dragging) renderBoxes(); });
  window.addEventListener("resize", renderBoxes);
  if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
