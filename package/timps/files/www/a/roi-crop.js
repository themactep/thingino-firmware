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
  function qpRange(r) { return r.qp_mode ? [-26, 25] : [0, 51]; }

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
    Array.prototype.slice.call(stage.querySelectorAll(".rc-box")).forEach(function (b) { b.remove(); });
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
          field("roi-q-" + n, "QP " + q[0] + ".." + q[1] + " (lower = sharper)", r.qp, ' min="' + q[0] + '" max="' + q[1] + '"') + "</div>" +
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

  function maxZoom() { return Math.max(1, Math.min(8, Math.floor(Math.min(sw, sh) / FMIN * 10) / 10)); }
  function even(v) { return Math.max(0, Math.round(v / 2) * 2); }

  function cropFromSliders() {
    var z = +$("crop-zoom").value, px = +$("crop-px").value / 100, py = +$("crop-py").value / 100;
    crop.w = even(sw / z); crop.h = even(sh / z);
    crop.x = even((sw - crop.w) * px); crop.y = even((sh - crop.h) * py);
  }
  function slidersFromCrop() {
    var w = crop.w > 0 ? crop.w : sw, h = crop.h > 0 ? crop.h : sh;
    $("crop-zoom").value = String(Math.min(maxZoom(), sw / w));
    $("crop-px").value = String(sw > w ? Math.round(crop.x / (sw - w) * 100) : 50);
    $("crop-py").value = String(sh > h ? Math.round(crop.y / (sh - h) * 100) : 50);
  }

  function renderCrop(state) {
    $("crop-en").checked = !!crop.en;
    ["x", "y", "w", "h"].forEach(function (k) { $("crop-" + k).value = crop[k]; });
    $("crop-zoom-v").textContent = (+$("crop-zoom").value).toFixed(1) + "×";
    $("crop-sensor").textContent = sw && sh ? sw + "×" + sh : "unknown";
    var m = $("crop-map");
    if (sw && sh) m.style.aspectRatio = sw + " / " + sh;
    var b = m.firstElementChild, on = crop.en && crop.w > 0 && sw;
    b.style.display = on ? "" : "none";
    if (on) {
      b.style.left = crop.x / sw * 100 + "%"; b.style.top = crop.y / sh * 100 + "%";
      b.style.width = crop.w / sw * 100 + "%"; b.style.height = crop.h / sh * 100 + "%";
    }
    if (state !== undefined)
      $("crop-state").textContent = "State: " + state + (state === "failed" ? " (the SoC refused this window)" :
        state === "rejected" ? " (below 64×64 or outside the sensor)" : "");
    var dis = cropTier === "unsupported" || !sw;
    Array.prototype.forEach.call(document.querySelectorAll('[data-page-pane="crop"] input'), function (e) { e.disabled = dis; });
  }

  function sendCrop() {
    renderCrop();
    api.setDebounced({ image: { fcrop_enable: crop.en ? 1 : 0, fcrop_x: crop.x, fcrop_y: crop.y, fcrop_w: crop.w, fcrop_h: crop.h } }, 400)
      .then(function () { return api.get(); })
      .then(function (j) { renderCrop(j.caps && j.caps.fcrop ? j.caps.fcrop.state : ""); },
        function (e) { toast("danger", "Crop update failed: " + (e.message || e)); });
  }

  $("crop-en").addEventListener("change", function () {
    crop.en = this.checked ? 1 : 0;
    if (crop.en && !(crop.w >= FMIN && crop.h >= FMIN)) cropFromSliders();
    sendCrop();
  });
  ["crop-zoom", "crop-px", "crop-py"].forEach(function (id) {
    $(id).addEventListener("input", function () { cropFromSliders(); crop.en = 1; sendCrop(); });
  });
  ["x", "y", "w", "h"].forEach(function (k) {
    $("crop-" + k).addEventListener("change", function () {
      var v = parseInt(this.value, 10); if (isNaN(v)) return;
      crop[k] = even(v); slidersFromCrop(); sendCrop();
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
      $("crop-zoom").max = String(maxZoom());
      var im = j.image || {};
      crop = { en: +im.fcrop_enable || 0, x: +im.fcrop_x || 0, y: +im.fcrop_y || 0, w: +im.fcrop_w || 0, h: +im.fcrop_h || 0 };
      $("crop-tier").textContent = cropTier;
      note($("crop-note"), cropTier === "effective" ? "" : cropTier,
        cropTier === "unsupported" ? "" : !fc.live ? "Applies after a streamer restart." : "");
      slidersFromCrop();
      renderCrop(fc.state);
    }).catch(function () {
      note($("roi-note"), "unsupported", "The streamer is not reachable.");
      note($("crop-note"), "unsupported", "The streamer is not reachable.");
    });
  }

  var reload = null;
  if (api) api.events("config", function (t, d) {
    if (!d || dragging || !(d.resync || /^(roi\d|image\.fcrop_)/.test(d.key || ""))) return;
    var ae = document.activeElement;
    if (ae && ae.id && /^(roi|crop)-/.test(ae.id)) return;
    clearTimeout(reload); reload = setTimeout(load, 500);
  });
  document.addEventListener("timps-stream", function (e) { S = e.detail; sel = -1; load(); });
  img.addEventListener("load", function () { if (!dragging) renderBoxes(); });
  window.addEventListener("resize", renderBoxes);
  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
