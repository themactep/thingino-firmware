// roi-crop.js - "ROI" and "Crop / zoom" tabs of streamer-overlays.html:
// encoder ROI regions (roi<S>.<N>.*) and the ISP FrontCrop (image.fcrop_*).
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-overlays" || !window.timpsUi) return;

  var MB = 16, FMIN = 64;
  var api = window.timpsApi;
  var S = window.timpsUi.stream();
  var W = 1920, H = 1080;          // current stream picture
  var maxRoi = 4, regions = [], shown = {}, sel = -1, dragging = false, roiTier = "", roiState = "ok";
  var qpDelta = [-25, 25], qpAbs = [0, 51], qpEff = null;
  var sw = 0, sh = 0, crop = { en: 0, x: 0, y: 0, w: 0, h: 0 }, cropTier = "";

  var $ = function (id) { return document.getElementById(id); };
  var stage = $("frame"), img = $("preview"), list = $("roi-list"), addBtn = $("roi-add");

  function toast(t, m) { window.timpsUi.toast(t, m); }

  var TIER = {
    experimental: "Experimental on this camera: the streamer accepts it, but no effect has been verified on this SoC - it may do nothing.",
    unsupported: "Not available on this camera (SoC or libimp). Values cannot be changed here.",
    sim: "Simulator: values are stored, nothing is applied.",
  };
  function note(el, tier, extra) {
    var t = (TIER[tier] || "") + (extra ? (TIER[tier] ? " " : "") + extra : "");
    el.textContent = t;
    el.classList.toggle("d-none", !t);
    el.classList.toggle("alert-danger", tier === "unsupported");
    el.classList.toggle("alert-warning", tier !== "unsupported");
  }

  /* ---------------- ROI ---------------- */

  function snap(r) {
    var x1 = Math.min(W, Math.ceil((r.x + Math.max(r.w, 1)) / MB) * MB);
    var y1 = Math.min(H, Math.ceil((r.y + Math.max(r.h, 1)) / MB) * MB);
    r.x = Math.max(0, Math.min(W - MB, Math.floor(r.x / MB) * MB));
    r.y = Math.max(0, Math.min(H - MB, Math.floor(r.y / MB) * MB));
    r.w = Math.max(MB, x1 - r.x);
    r.h = Math.max(MB, y1 - r.y);
  }
  function qpRange(r) { return r.qp_mode ? qpDelta : qpAbs; }
  function pair(a, d) { return Array.isArray(a) && a.length === 2 && isFinite(a[0]) && isFinite(a[1]) && a[0] < a[1] ? [+a[0], +a[1]] : d; }

  function sendRoi(n) {
    var r = regions[n], b = {}; b[S] = {};
    b[S][n] = { enabled: r.enabled ? 1 : 0, x: r.x, y: r.y, w: r.w, h: r.h, qp: r.qp, qp_mode: r.qp_mode };
    api.set({ roi: b }).then(function (res) {
      var t = api.takeCorrections(res);
      if (t) toast("info", api.correctionsText(t));
    }, function (e) { toast("danger", "ROI update failed: " + (e.message || e)); });
  }

  function scale() {
    var dw = img.clientWidth || stage.clientWidth || 1;
    var dh = img.clientHeight || dw * H / W;
    return { sx: dw / W, sy: dh / H };
  }
  function place(box, r, s) {
    box.style.left = r.x * s.sx + "px"; box.style.top = r.y * s.sy + "px";
    box.style.width = r.w * s.sx + "px"; box.style.height = r.h * s.sy + "px";
  }

  function renderBoxes() {
    Array.prototype.slice.call(stage.querySelectorAll(".rc-box:not(.rc-crop)")).forEach(function (b) { b.remove(); });
    var s = scale();
    regions.forEach(function (r, n) {
      if (!shown[n] || r.w <= 0 || r.h <= 0) return;
      var box = document.createElement("div");
      box.className = "rc-box" + (n === sel ? " sel" : "") + (r.enabled ? "" : " off");
      box.innerHTML = '<span class="pm-tag">ROI ' + (n + 1) + " · " + qpText(r) + '</span><div class="pm-handle"></div>';
      place(box, r, s);
      stage.appendChild(box);
      box.addEventListener("pointerdown", function (ev) {
        drag(ev, n, ev.target.classList.contains("pm-handle") ? "size" : "move", box);
      });
    });
  }

  function drag(ev, n, mode, box) {
    if (roiTier === "unsupported") return;
    ev.preventDefault(); ev.stopPropagation();
    dragging = true; select(n);
    var s = scale(), r = regions[n], o = { px: ev.clientX, py: ev.clientY, x: r.x, y: r.y, w: r.w, h: r.h };
    function move(e) {
      var dx = (e.clientX - o.px) / s.sx, dy = (e.clientY - o.py) / s.sy;
      if (mode === "move") { r.x = o.x + dx; r.y = o.y + dy; r.w = o.w; r.h = o.h; }
      else { r.x = o.x; r.y = o.y; r.w = o.w + dx; r.h = o.h + dy; }
      if (mode === "move") { r.x = Math.max(0, Math.min(W - r.w, r.x)); r.y = Math.max(0, Math.min(H - r.h, r.y)); }
      snap(r); place(box, r, s); syncRow(n);
    }
    function up() {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      dragging = false; sendRoi(n); renderList();
    }
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
  }

  function qpText(r) { return (r.qp_mode ? "QP " + (r.qp > 0 ? "+" : "") : "QP =") + r.qp; }
  function pos(r) { return r.x + "," + r.y + " · " + r.w + "×" + r.h; }
  function syncRow(n) {
    var r = regions[n], row = list.querySelector('[data-n="' + n + '"]');
    if (!row) return;
    row.querySelector(".tv-pos").textContent = pos(r);
    ["x", "y", "w", "h"].forEach(function (k) { var e = $("roi-" + k + "-" + n); if (e) e.value = r[k]; });
  }
  function select(n) { if (sel !== n) { sel = n; renderList(); renderBoxes(); } }

  function field(id, label, v, extra) {
    return '<div><label for="' + id + '">' + label + '</label><input type="number" class="form-control" id="' +
      id + '" value="' + v + '"' + (extra || "") + "></div>";
  }

  function renderList() {
    list.innerHTML = "";
    var count = 0, off = roiTier === "unsupported";
    regions.forEach(function (r, n) {
      if (!shown[n]) return;
      count++;
      var w = document.createElement("div");
      w.className = "tv-item mb-2" + (n === sel ? " open" : "");
      w.setAttribute("data-n", String(n));
      w.innerHTML = '<div class="tv-ih"><div class="form-check form-switch m-0"><input class="form-check-input" type="checkbox" role="switch" aria-label="Region on"' +
        (r.enabled ? " checked" : "") + (off ? " disabled" : "") + '></div><span></span><span class="tv-tx">Region ' + (n + 1) + " · " + qpText(r) +
        '</span><span class="tv-pos">' + pos(r) + "</span>" +
        (r.enabled ? '<span class="badge text-bg-success">On</span>' : '<span class="badge text-bg-secondary">Off</span>') + "</div>";
      if (n === sel) {
        var q = qpRange(r), ib = document.createElement("div");
        ib.className = "tv-ib";
        ib.innerHTML = '<div class="tv-fields">' +
          field("roi-x-" + n, "From left", r.x, ' min="0" step="16"') + field("roi-y-" + n, "From top", r.y, ' min="0" step="16"') +
          field("roi-w-" + n, "Width", r.w, ' min="16" step="16"') + field("roi-h-" + n, "Height", r.h, ' min="16" step="16"') +
          '<div><label for="roi-m-' + n + '">QP mode</label><select class="form-select" id="roi-m-' + n + '">' +
          '<option value="1"' + (r.qp_mode ? " selected" : "") + ">delta</option>" +
          '<option value="0"' + (r.qp_mode ? "" : " selected") + ">absolute</option></select></div>" +
          field("roi-q-" + n, "QP " + q[0] + ".." + q[1] + (r.qp_mode && qpEff && (qpEff[0] !== q[0] || qpEff[1] !== q[1]) ?
            ", effect " + qpEff[0] + ".." + qpEff[1] : "") + " (lower = sharper)", r.qp, ' min="' + q[0] + '" max="' + q[1] + '"') + "</div>" +
          '<div class="d-flex flex-wrap align-items-center gap-2 mt-2"><span class="tv-cfg me-auto">roi' + S + "." + n +
          '</span><button type="button" class="btn btn-sm btn-outline-danger" id="roi-del-' + n + '"><i class="bi bi-trash me-1"></i>Remove</button></div>';
        Array.prototype.forEach.call(ib.querySelectorAll("input,select,button"), function (e) { e.disabled = off; });
        w.appendChild(ib);
      }
      w.querySelector(".tv-ih").addEventListener("click", function (e) {
        if (!e.target.closest(".form-check")) select(sel === n ? -1 : n);
      });
      w.querySelector(".form-check-input").addEventListener("change", function () {
        r.enabled = this.checked ? 1 : 0; sendRoi(n); renderList(); renderBoxes();
      });
      list.appendChild(w);
      if (n === sel) wireRow(n);
    });
    $("roi-empty").classList.toggle("d-none", count > 0);
    addBtn.disabled = off || count >= maxRoi;
  }

  function wireRow(n) {
    var r = regions[n];
    ["x", "y", "w", "h"].forEach(function (k) {
      $("roi-" + k + "-" + n).addEventListener("change", function () {
        var v = parseInt(this.value, 10); if (isNaN(v)) return;
        r[k] = v; snap(r); sendRoi(n); renderList(); renderBoxes();
      });
    });
    $("roi-m-" + n).addEventListener("change", function () {
      r.qp_mode = +this.value; var q = qpRange(r);
      r.qp = Math.max(q[0], Math.min(q[1], r.qp_mode ? -5 : 30));
      sendRoi(n); renderList(); renderBoxes();
    });
    $("roi-q-" + n).addEventListener("change", function () {
      var v = parseInt(this.value, 10), q = qpRange(r); if (isNaN(v)) return;
      r.qp = Math.max(q[0], Math.min(q[1], v)); sendRoi(n); renderList(); renderBoxes();
    });
    $("roi-del-" + n).addEventListener("click", function () {
      r.enabled = 0; delete shown[n]; sel = -1; sendRoi(n); renderList(); renderBoxes();
    });
  }

  addBtn.addEventListener("click", function () {
    var n = -1;
    for (var i = 0; i < regions.length; i++) if (!shown[i]) { n = i; break; }
    if (n < 0) return;
    var r = regions[n];
    r.enabled = 1; r.qp_mode = 1; r.qp = -5;
    r.w = Math.round(W / 4); r.h = Math.round(H / 4); r.x = Math.round((W - r.w) / 2); r.y = Math.round((H - r.h) / 2);
    snap(r); shown[n] = true; sel = n;
    sendRoi(n); renderList(); renderBoxes();
  });

  /* ---------------- crop / zoom ---------------- */

  // pure geometry, host-tested by timps scripts/test_webui_crop.js
  // fmin: the smallest window, a number or caps.fcrop.min_win [w, h]
  function cropFit(c, sw, sh, fmin) {
    var e = function (v) { return Math.round(v / 2) * 2; };
    var mw = Math.min(sw, fmin[0] || fmin), mh = Math.min(sh, fmin[1] || fmin);
    var w = Math.max(mw, Math.min(sw, e(c.w))), h = Math.max(mh, Math.min(sh, e(c.h)));
    return { x: Math.max(0, Math.min(sw - w, e(c.x))), y: Math.max(0, Math.min(sh - h, e(c.y))), w: w, h: h };
  }
  // "size" keeps the sensor aspect like the zoom slider; top-left stays put
  function cropDrag(o, mode, dx, dy, sw, sh, fmin) {
    if (mode === "move") return cropFit({ x: o.x + dx, y: o.y + dy, w: o.w, h: o.h }, sw, sh, fmin);
    var a = sh / sw, w = o.w + (dx + dy / a) / 2, mw = fmin[0] || fmin, mh = fmin[1] || fmin;
    w = Math.max(mw, mh / a, Math.min(w, sw - o.x, (sh - o.y) / a));
    return cropFit({ x: o.x, y: o.y, w: w, h: w * a }, sw, sh, fmin);
  }
  function cropFromZoom(z, px, py, sw, sh, fmin) {
    var w = Math.round(sw / z / 2) * 2, h = Math.round(sh / z / 2) * 2;
    return cropFit({ x: (sw - w) * px, y: (sh - h) * py, w: w, h: h }, sw, sh, fmin);
  }
  function zoomFromCrop(c, sw, sh, zmax) {
    var w = c.w > 0 ? c.w : sw, h = c.h > 0 ? c.h : sh;
    return { z: Math.min(zmax, sw / w), px: sw > w ? Math.round(c.x / (sw - w) * 100) : 50,
      py: sh > h ? Math.round(c.y / (sh - h) * 100) : 50 };
  }
  // window in % of a full-sensor surface (the map, or the preview while no crop is applied)
  function cropPct(c, sw, sh) {
    return { left: c.x / sw * 100, top: c.y / sh * 100, width: c.w / sw * 100, height: c.h / sh * 100 };
  }
  // > 1: the stream upscales the window
  function cropScale(c, vw, vh) { return Math.max(vw / c.w, vh / c.h); }
  // zoom_max is rounded down to 0.01, so it only tightens min_win when clearly lower
  function cropEffMin(sw, sh, fmin, zcap) {
    if (!(zcap > 0) || zcap * 1.01 >= Math.min(sw / fmin[0], sh / fmin[1])) return fmin;
    return [Math.max(fmin[0], Math.ceil(sw / zcap / 2) * 2), Math.max(fmin[1], Math.ceil(sh / zcap / 2) * 2)];
  }
  // end of the zoom slider: the smallest window
  function cropZoomMax(sw, sh, em) { return Math.max(1, Math.min(sw / em[0], sh / em[1])); }
  // above this zoom the window is smaller than a zoomed stream [w, h], which then upscales it
  function cropNative(sw, sh, sizes, zmax) {
    var z = zmax;
    sizes.forEach(function (s) { z = Math.min(z, sw / s[0], sh / s[1]); });
    return Math.max(1, z);
  }

  // cropOn: the preview (stream S) shows the window; with a full-sensor frame (shot) the editor is that
  // frame (#crop-ed) with the live result as an inset, liveBig swaps the two; without one the cut-out
  var cropLive = 1, cropOn = false, cropSeq = 0, liveBig = false, shot = false, sentAt = 0, savedAt = 0;
  var capRun = null, capTried = false, tokInfo = null;
  var fmin = [FMIN, FMIN], emin = fmin, zoomCap = 8, zmax = 1, upPct = -1, waitPoll = null;
  var vids = [], fcInfo = {}, zs = $("crop-zoom");
  var ed = document.createElement("canvas"), msg = document.createElement("div");
  ed.id = "crop-ed"; ed.className = "rc-crop";
  msg.className = "rc-msg rc-crop";
  msg.innerHTML = '<span></span><button type="button" class="btn btn-sm btn-outline-light py-0" id="crop-capture">Capture full view</button>';
  stage.insertBefore(ed, img); stage.appendChild(msg);

  function zoomedSizes() {
    var a = [];
    vids.forEach(function (v, i) { if (v && v.en && showsCrop(i)) a.push([v.w, v.h]); });
    return a;
  }
  function showsCrop(i) {
    var a = fcInfo.state === "on" && Array.isArray(fcInfo.zoomed) ? fcInfo.zoomed : fcInfo.zoomable;
    return Array.isArray(a) ? !!a[i] : true;
  }
  function takeFc(fc) { fcInfo = fc; cropOn = shownOn(fc); }
  function setCrop(c) { crop.x = c.x; crop.y = c.y; crop.w = c.w; crop.h = c.h; }
  function cropValid() { return crop.w >= FMIN && crop.h >= FMIN; }
  function shownOn(fc) {
    if (fc.state !== "on") return false;
    return Array.isArray(fc.zoomed) ? !!fc.zoomed[S] : true;
  }

  function cropFromSliders() {
    setCrop(cropFromZoom(+zs.value, +$("crop-px").value / 100, +$("crop-py").value / 100, sw, sh, emin));
  }
  function slidersFromCrop() {
    var v = zoomFromCrop(crop, sw, sh, zmax);
    zs.value = String(v.z); $("crop-px").value = String(v.px); $("crop-py").value = String(v.py);
  }

  var box = document.createElement("div");
  box.className = "rc-box rc-crop sel";
  box.innerHTML = '<span class="pm-tag">Crop</span><div class="pm-handle"></div>';
  stage.appendChild(box);
  box.addEventListener("pointerdown", function (ev) {
    cropDragStart(ev, ev.target.classList.contains("pm-handle") ? "size" : "move");
  });

  function inCrop() { return document.body.getAttribute("data-pane") === "crop"; }
  function pip() { return cropOn && !!sw; }
  function edMode() { return pip() && shot; }
  // the large picture and the sensor window it shows
  function surf() { return edMode() && !liveBig ? ed : img; }

  // the inset and the button must not open the preview modal (timps-preview.js)
  stage.addEventListener("click", function (ev) {
    if (!inCrop()) return;
    if (ev.target.classList.contains("rc-inset")) { ev.stopPropagation(); liveBig = !liveBig; renderCrop(); }
    else if (ev.target.id === "crop-capture") { ev.stopPropagation(); capture(); }
  }, true);

  function cropDragStart(ev, mode) {
    if (cropTier === "unsupported" || !sw || capRun) return;
    ev.preventDefault(); ev.stopPropagation();
    if (!cropValid()) cropFromSliders();
    dragging = true;
    var bw = surf().clientWidth, bh = surf().clientHeight;
    var o = { px: ev.clientX, py: ev.clientY, x: crop.x, y: crop.y, w: crop.w, h: crop.h }, moved = false;
    function move(e) {
      moved = true;
      setCrop(cropDrag(o, mode, (e.clientX - o.px) * sw / (bw || 1), (e.clientY - o.py) * sh / (bh || 1), sw, sh, emin));
      slidersFromCrop(); sendCrop(false);
    }
    function up() {
      window.removeEventListener("pointermove", move);
      window.removeEventListener("pointerup", up);
      window.removeEventListener("pointercancel", up);
      dragging = false;
      if (moved && !cropLive) sendCrop(true);
    }
    window.addEventListener("pointermove", move);
    window.addEventListener("pointerup", up);
    window.addEventListener("pointercancel", up);
  }

  function renderCrop(state) {
    $("crop-en").checked = !!crop.en;
    ["x", "y", "w", "h"].forEach(function (k) { $("crop-" + k).value = crop[k]; });
    $("crop-sensor").textContent = sw && sh ? sw + "×" + sh : "unknown";
    if (sw && sh) ed.style.aspectRatio = sw + " / " + sh;
    var pp = edMode(), big = surf(), cv = sw && cropValid();
    var right = cv && crop.x + crop.w / 2 > sw / 2, low = cv && crop.y + crop.h / 2 > sh / 2;
    document.body.classList.toggle("rc-pip", pp);
    [img, ed].forEach(function (e) {
      var ins = pp && e !== big;
      e.classList.toggle("rc-inset", ins); e.classList.toggle("at-l", ins && right); e.classList.toggle("at-t", ins && low);
    });
    var dis = cropTier === "unsupported" || !sw, show = cv && (!pip() || big === ed);
    msg.style.display = capRun || (pip() && !shot) ? "" : "none";
    msg.firstChild.textContent = capRun ? "Taking a full-sensor picture..." : "Showing the cut-out. Switch crop off to see the whole sensor.";
    msg.lastChild.hidden = !!capRun || !cropLive || dis;
    msg.classList.toggle("busy", !!capRun);
    dis = dis || !!capRun;
    var bw = big.clientWidth, bh = big.clientHeight, ox = big.offsetLeft, oy = big.offsetTop;
    box.style.display = show ? "" : "none";
    box.classList.toggle("off", dis);
    if (show) {
      var p = cropPct(crop, sw, sh);
      box.style.left = ox + p.left * bw / 100 + "px"; box.style.top = oy + p.top * bh / 100 + "px";
      box.style.width = p.width * bw / 100 + "px"; box.style.height = p.height * bh / 100 + "px";
    }
    renderZoom();
    renderScale();
    if (state !== undefined)
      $("crop-state").textContent = "State: " + state + (state === "failed" ? " (the SoC refused this window)" :
        state === "waiting" ? " (applies when a stream that can show this window is running)" :
        state === "rejected" ? " (smaller than " + fmin[0] + "×" + fmin[1] + ", outside the sensor, or no stream can show it)" : "");
    Array.prototype.forEach.call(document.querySelectorAll('[data-page-pane="crop"] input'), function (e) { e.disabled = dis; });
  }

  // value + Crop / Crop + zoom; the track turns amber above the native threshold
  function renderZoom() {
    var out = $("crop-zoom-v"), sizes = zoomedSizes(), cv = sw && cropValid(), ups = [];
    var zn = cropNative(sw, sh, sizes, zmax), f = zmax > 1 ? Math.min(1, (zn - 1) / (zmax - 1)) : 1;
    zs.style.setProperty("--nat", String(f));
    zs.style.setProperty("--tk", f < 0.999 ? "#fff" : "transparent");
    if (cv) vids.forEach(function (v, i) {
      if (!v || !v.en || !showsCrop(i)) return;
      var k = cropScale(crop, v.w, v.h);
      if (k > 1.005) ups.push("upscaled " + (Math.round(k * 100) / 100) + "× on stream " + i);
    });
    out.textContent = (cv ? zoomFromCrop(crop, sw, sh, zmax).z : +zs.value).toFixed(2) + "× " +
      (ups.length ? "Crop + zoom, " + ups.join(", ") : "Crop");
    out.classList.toggle("text-warning", ups.length > 0);
    $("crop-zoom-h").textContent = !sw || zmax <= 1.005 || !sizes.length ? "" : zmax - zn < 0.005 ?
      (upPct === 0 ? "Crop only (this camera does not upscale)" : "Crop only (no upscaling at these stream sizes)") :
      "1–" + zn.toFixed(2) + "×: crop at full resolution. Above the mark, up to " + zmax.toFixed(2) + "×: crop + zoom (upscaled, softer).";
  }

  function renderScale() {
    var el = $("crop-scale"), soft = false;
    el.innerHTML = "";
    if (!sw || !cropValid()) return;
    vids.forEach(function (v, i) {
      if (!v || !v.en) return;
      var d = document.createElement("div"), t = "Stream " + i + " " + v.w + "×" + v.h + ": ";
      if (!showsCrop(i)) t += "not zoomed (shows the full frame)";
      else {
        var f = cropScale(crop, v.w, v.h);
        t += "window " + crop.w + "×" + crop.h + " → " + (f > 1.005 ? "upscaled " + (Math.round(f * 100) / 100) + "×" : "native");
        if (f > 1.005) { soft = true; d.className = "text-warning"; }
      }
      d.textContent = t;
      el.appendChild(d);
    });
    if (!el.firstChild) return;
    if (!crop.en) el.insertAdjacentHTML("afterbegin", "<div>With crop enabled:</div>");
    if (soft) el.insertAdjacentHTML("beforeend", '<div class="text-warning">Upscaled pictures get soft. A lower stream resolution lets you crop tighter onto an object without upscaling.</div>');
  }


  // T23 (caps.fcrop.live 0) applies the window only at start: one POST on release, no live drag stream
  function sendCrop(final) {
    renderCrop();
    if (!cropLive && !final) return;
    sentAt = Date.now();
    // every merged setDebounced() call resolves; only the newest re-reads the state
    var n = ++cropSeq, body = { image: { fcrop_enable: crop.en ? 1 : 0, fcrop_x: crop.x, fcrop_y: crop.y, fcrop_w: crop.w, fcrop_h: crop.h } };
    (cropLive ? api.setDebounced(body, 400) : api.set(body))
      .then(function () { return n === cropSeq && cropLive ? api.get() : null; })
      .then(function (j) {
        if (n !== cropSeq) return;
        if (!j) { renderCrop("saved, applies after restart"); return; }
        var fc = (j.caps && j.caps.fcrop) || {};
        takeFc(fc); renderCrop(fc.state || ""); watchWaiting(fc.state);
      }, function (e) { if (n === cropSeq) toast("danger", "Crop update failed: " + (e.message || e)); });
  }

  // "waiting" turns "on" when a stream starts, without a config event: re-read a few times
  function watchWaiting(state) {
    clearTimeout(waitPoll); waitPoll = null;
    if (state !== "waiting") return;
    var left = 10;
    (function poll() {
      waitPoll = setTimeout(function () {
        if (dragging || document.hidden) { if (--left > 0) poll(); return; }
        api.get().then(function (j) {
          var fc = (j.caps && j.caps.fcrop) || {};
          if (fc.state !== "waiting") { takeFc(fc); renderCrop(fc.state || ""); waitPoll = null; }
          else if (--left > 0) poll();
        }, function () { if (--left > 0) poll(); });
      }, 3000);
    })();
  }

  /* full-sensor frame: grabbed while crop is off, kept per camera + sensor in localStorage */
  function frameKey() { return "timps-crop-full:" + location.host + ":" + sw + "x" + sh; }
  function fit(c) { var w = Math.min(640, sw), h = Math.round(w * sh / sw); if (c.width !== w || c.height !== h) { c.width = w; c.height = h; } return c; }
  function paint(src) { fit(ed).getContext("2d").drawImage(src, 0, 0, ed.width, ed.height); shot = true; }
  // the preview <img> is cross-origin (timps port) and taints a canvas: then a CORS still is stored instead
  function store(src) {
    try {
      var c = fit(document.createElement("canvas"));
      c.getContext("2d").drawImage(src, 0, 0, c.width, c.height);
      localStorage.setItem(frameKey(), c.toDataURL("image/jpeg", 0.7));
      return true;
    } catch (e) { return false; }
  }
  function hasCache() { try { return !!localStorage.getItem(frameKey()); } catch (e) { return false; } }
  function loadCache() {
    if (shot || !sw) return;
    try {
      var d = localStorage.getItem(frameKey()), i = new Image();
      if (!d) return;
      i.onload = function () { if (!shot) { paint(i); renderCrop(); } };
      i.src = d;
    } catch (e) {}
  }
  function snap() {
    if (typeof timpsMediaUrl !== "function") return Promise.reject(new Error("no media url"));
    return fetch(timpsMediaUrl("still", S) + "&_=" + Date.now(), { cache: "no-store" }).then(function (r) {
      if (!r.ok) throw new Error("HTTP " + r.status);
      return r.blob();
    }).then(function (b) {
      return new Promise(function (res, rej) {
        var i = new Image(), u = URL.createObjectURL(b);
        i.onload = function () { URL.revokeObjectURL(u); res(i); };
        i.onerror = function () { URL.revokeObjectURL(u); rej(new Error("bad still")); };
        i.src = u;
      });
    });
  }
  function fresh() { return !cropOn && !capRun && Date.now() - sentAt >= 3000; }
  function persist() {
    savedAt = Date.now();
    if (!store(img)) snap().then(function (i) { if (fresh()) store(i); }, function () {});
  }
  // skipped right after a POST: the stream may already be cropped
  function grab() {
    if (!fresh() || !sw || document.hidden || !inCrop() || !img.naturalWidth || /nostream\.svg$/.test(img.src)) return;
    try { paint(img); } catch (e) { return; }
    if (Date.now() - savedAt > 10000) persist();
  }
  setInterval(grab, 1500);

  function wait(ms) { return new Promise(function (r) { setTimeout(r, ms); }); }
  function cropBody(c, en) { return { image: { fcrop_enable: en, fcrop_x: c.x, fcrop_y: c.y, fcrop_w: c.w, fcrop_h: c.h } }; }
  function autoCapture() {
    if (!capTried && inCrop() && pip() && !shot && !hasCache() && cropLive && cropTier !== "unsupported") { capTried = true; capture(); }
  }
  // live cameras only: crop off until two fresh frames arrived, draw one, then always the identical window back on
  function capture() {
    if (capRun || !cropLive || !pip() || cropTier === "unsupported" || !cropValid()) return;
    var win = { x: crop.x, y: crop.y, w: crop.w, h: crop.h }, run = capRun = { stop: false, on: cropBody(win, 1) };
    var loads = 0, t0 = 0, tm = null, onl = function () { loads++; };
    var guard = function () { if (run.stop) throw new Error("stopped"); };
    cropSeq++; clearTimeout(waitPoll); waitPoll = null; renderCrop();
    fetch("/x/timps-token.cgi", { cache: "no-store" }).then(function (r) { return r.json(); }).then(function (j) { tokInfo = j; }, function () {});
    var steps = api.set(cropBody(win, 0)).then(function () {
      guard(); t0 = Date.now(); img.addEventListener("load", onl);
      return wait(1200);
    }).then(function () {
      guard();
      return snap().then(function () { guard(); return snap(); }).catch(function (e) {
        if (run.stop) throw e;
        return new Promise(function (res, rej) {
          (function chk() {
            if (run.stop) return rej(new Error("stopped"));
            if (loads >= 2 || Date.now() - t0 > 3500) return res(img);
            setTimeout(chk, 100);
          })();
        });
      });
    }).then(function (src) { guard(); paint(src); store(src); });
    steps.catch(function () {});
    Promise.race([steps, new Promise(function (_, rej) { tm = setTimeout(function () { rej(new Error("timeout")); }, 6000); })])
      .catch(function () { run.stop = true; })
      .then(function () { clearTimeout(tm); img.removeEventListener("load", onl); return restore(run, 2); });
  }
  function restore(run, tries) {
    return api.set(run.on).then(function () { return api.get(); }).then(function (j) {
      capRun = null;
      var fc = (j.caps && j.caps.fcrop) || {};
      takeFc(fc); renderCrop(fc.state || ""); watchWaiting(fc.state);
    }, function (e) {
      if (tries > 1) return wait(500).then(function () { return restore(run, tries - 1); });
      capRun = null; renderCrop();
      toast("danger", "Switching the crop back on failed: " + (e.message || e));
    });
  }
  window.addEventListener("pagehide", function () {
    if (!capRun || !tokInfo) return;
    var h = location.hostname, t = tokInfo, hd = { "Content-Type": "application/json" };
    if (h.indexOf(":") >= 0 && h.charAt(0) !== "[") h = "[" + h + "]";
    var sc = t.scheme === "https" || (t.scheme === "both" && location.protocol === "https:") || (!t.scheme && t.tls) ? "https" : "http";
    if (t.token) hd["X-Timps-Token"] = t.token;
    try { fetch(sc + "://" + h + ":" + (t.port || 8880) + "/control", { method: "POST", keepalive: true, headers: hd, body: JSON.stringify(capRun.on) }); } catch (e) {}
  });

  $("crop-en").addEventListener("change", function () {
    crop.en = this.checked ? 1 : 0;
    if (crop.en && !cropValid()) cropFromSliders();
    sendCrop(true);
  });
  ["crop-zoom", "crop-px", "crop-py"].forEach(function (id) {
    $(id).addEventListener("input", function () { cropFromSliders(); crop.en = 1; sendCrop(false); });
    $(id).addEventListener("change", function () { if (!cropLive) sendCrop(true); });
  });
  ["x", "y", "w", "h"].forEach(function (k) {
    $("crop-" + k).addEventListener("change", function () {
      var v = parseInt(this.value, 10); if (isNaN(v) || !sw) return;
      var c = { x: crop.x, y: crop.y, w: crop.w || sw, h: crop.h || sh }; c[k] = v;
      setCrop(cropFit(c, sw, sh, emin)); slidersFromCrop(); sendCrop(true);
    });
  });

  /* ---------------- load / sync ---------------- */

  function load() {
    if (!api) return;
    api.get().then(function (j) {
      var c = j.caps || {}, rc = c.roi || {}, fc = c.fcrop || {};
      roiTier = rc.tier || "unsupported";
      roiState = (rc.streams && rc.streams[S]) || "ok";
      if (rc.regions > 0) maxRoi = Math.min(rc.regions, 8);
      qpDelta = pair(rc.qp_delta, [-25, 25]); qpAbs = pair(rc.qp_abs, [0, 51]); qpEff = pair(rc.qp_delta_eff, null);
      $("roi-max").textContent = String(maxRoi);
      var v = (j.video && (j.video[S] || j.video[String(S)])) || {};
      if (v.width > 0 && v.height > 0) { W = v.width; H = v.height; }
      var st = roiState === "h265" ? "This stream is H.265: ROI regions are ignored." :
        roiState === "rotated" ? "This stream is rotated: ROI regions are ignored." : "";
      note($("roi-note"), roiTier === "effective" ? "" : roiTier, st);
      var src = (j.roi && (j.roi[S] || j.roi[String(S)])) || {};
      regions = []; shown = {};
      for (var n = 0; n < maxRoi; n++) {
        var r = src[n] || src[String(n)] || {};
        regions.push({ enabled: +r.enabled || 0, x: +r.x || 0, y: +r.y || 0, w: +r.w || 0, h: +r.h || 0,
          qp: r.qp === undefined ? -5 : +r.qp, qp_mode: r.qp_mode === undefined ? 1 : +r.qp_mode });
        if (regions[n].enabled || (regions[n].w > 0 && regions[n].h > 0)) shown[n] = true;
      }
      if (!shown[sel]) sel = -1;
      renderList(); renderBoxes();

      cropTier = fc.tier || "unsupported";
      sw = (fc.sensor && fc.sensor[0]) || 0; sh = (fc.sensor && fc.sensor[1]) || 0;
      var mn = fc.min_win;
      fmin = Array.isArray(mn) && mn[0] > 0 && mn[1] > 0 ? [Math.max(FMIN, +mn[0]), Math.max(FMIN, +mn[1])] : [FMIN, FMIN];
      zoomCap = +fc.zoom_max > 0 ? +fc.zoom_max : 8;
      upPct = fc.upscale_pct === undefined ? -1 : +fc.upscale_pct;
      emin = sw && sh ? cropEffMin(sw, sh, fmin, zoomCap) : fmin;
      zmax = sw && sh ? cropZoomMax(sw, sh, emin) : 1;
      zs.max = String(zmax);
      var im = j.image || {};
      crop = { en: +im.fcrop_enable || 0, x: +im.fcrop_x || 0, y: +im.fcrop_y || 0, w: +im.fcrop_w || 0, h: +im.fcrop_h || 0 };
      cropLive = fc.live === undefined ? 1 : +fc.live; takeFc(fc);
      vids = [];
      for (var i = 0; i < 4; i++) {
        var vi = j.video && (j.video[i] || j.video[String(i)]);
        if (vi && vi.width > 0 && vi.height > 0) vids[i] = { en: vi.enabled === undefined ? 1 : +vi.enabled, w: +vi.width, h: +vi.height };
      }
      $("crop-tier").textContent = cropTier;
      $("crop-live").textContent = cropLive ? "live" : "restart";
      $("crop-live").className = "tv-badge " + (cropLive ? "live" : "rst");
      var zl = [], zn = Array.isArray(fc.zoomable) ? fc.zoomable : null;
      if (zn) zn.forEach(function (z, i) { if (z) zl.push(i ? "substream" : "main stream"); });
      var zt = !zn || zl.length === zn.length ? "" : !zl.length ? "No stream can show a crop window here." :
        "Only the " + zl.join(" and ") + " shows the crop; the others keep the full picture.";
      if (sw && zmax <= 1.005) zt = (zt ? zt + " " : "") + "Zoom is not possible with the current stream sizes.";
      note($("crop-note"), cropTier === "effective" ? "" : cropTier,
        [cropTier !== "unsupported" && !cropLive ? "Applies after restarting timps." : "", zt].filter(Boolean).join(" "));
      slidersFromCrop();
      if (!cropValid() && sw) cropFromSliders();
      renderCrop(fc.state); watchWaiting(fc.state);
      loadCache(); autoCapture();
    }).catch(function () {
      note($("roi-note"), "unsupported", "The streamer is not reachable.");
      note($("crop-note"), "unsupported", "The streamer is not reachable.");
    });
  }

  var reload = null;
  if (api) api.events("config", function (t, d) {
    if (!d || dragging || capRun || !(d.resync || /^(roi\d|image\.fcrop_)/.test(d.key || ""))) return;
    var ae = document.activeElement;
    if (ae && ae.id && /^(roi|crop)-/.test(ae.id)) return;
    clearTimeout(reload); reload = setTimeout(load, 500);
  });
  document.addEventListener("timps-stream", function (e) { if (capRun) capRun.stop = true; S = e.detail; sel = -1; load(); });
  function relayout() { if (!dragging) { renderBoxes(); renderCrop(); } }
  img.addEventListener("load", relayout);
  window.addEventListener("resize", relayout);
  // the inset resizes #preview: let every tab re-place its boxes
  new MutationObserver(function () {
    if (capRun && !inCrop()) capRun.stop = true;
    grab(); autoCapture(); window.dispatchEvent(new Event("resize"));
  })
    .observe(document.body, { attributes: true, attributeFilter: ["data-pane"] });
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
