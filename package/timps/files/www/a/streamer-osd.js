// streamer-osd.js - overlay page, both streams behind tabs.
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-overlays") return;

  var MAX_OSD = 8; // MS_MAX_OSD
  var NAME = { 0: "main stream", 1: "substream" };
  var POS_NAME = { tl: "top left", tc: "top", tr: "top right", ml: "left", mc: "centre",
    mr: "right", bl: "bottom left", bc: "bottom", br: "bottom right" };
  var ANCHORS = ["tl", "tc", "tr", "ml", "mc", "mr", "bl", "bc", "br"];

  var S = 0;
  var capsOsd = [];
  var items = { 0: {}, 1: {} };       // GET osd0/osd1 per slot
  var bootEnabled = { 0: {}, 1: {} }; // slots that had a region at startup
  var dims = { 0: { w: 1920, h: 1080 }, 1: { w: 640, h: 360 } };
  var shown = {};                     // slots listed for S
  var openItem = -1;
  var linked = false;
  var dragging = false;
  var reloadLater = false;            // config changed while the user was typing

  function $id(id) { return document.getElementById(id); }
  function ui() { return window.timpsUi; }
  function toast(t, m, ms) { ui().toast(t, m, ms); }
  function num(v, d) { var n = parseInt(v, 10); return isNaN(n) ? d : n; }

  // ---- conversions -----------------------------------------------------

  // timps "0xAARRGGBB" <-> {color:"#rrggbb", alpha}
  function fromColor(v) {
    var n = parseInt(String(v), 16);
    if (isNaN(n)) return { color: "#ffffff", alpha: 255 };
    return { color: "#" + (n & 0xffffff).toString(16).padStart(6, "0"), alpha: (n >>> 24) & 0xff };
  }
  function toColor(hex, alpha) {
    var rgb = /^#?([0-9a-f]{6})/i.exec(hex || "");
    if (!rgb) return null;
    var a = Math.min(255, Math.max(0, isNaN(alpha) ? 255 : alpha));
    return "0x" + a.toString(16).padStart(2, "0").toUpperCase() + rgb[1].toUpperCase();
  }

  // timps x/y: 0 = centred, >0 from left/top, <0 from right/bottom
  function anchorOf(it) {
    var x = num(it.x, 0), y = num(it.y, 0);
    return (y === 0 ? "m" : y > 0 ? "t" : "b") + (x === 0 ? "c" : x > 0 ? "l" : "r");
  }
  function toXY(a, ox, oy) {
    var h = a[1], v = a[0];
    ox = Math.max(1, Math.round(ox)); oy = Math.max(1, Math.round(oy));
    return { x: h === "c" ? 0 : h === "r" ? -ox : ox, y: v === "m" ? 0 : v === "b" ? -oy : oy };
  }

  function leafOk(leaf) {
    if (leaf === "enabled" || leaf === "x" || leaf === "y") return true;
    return capsOsd.indexOf(leaf) >= 0;
  }

  // ---- post ------------------------------------------------------------

  function scaled(leaves, from, to) {
    var out = {}, ky = dims[to].h / dims[from].h, kx = dims[to].w / dims[from].w;
    Object.keys(leaves).forEach(function (k) {
      var v = leaves[k];
      if (k === "font_size") v = Math.min(128, Math.max(8, Math.round(v * ky)));
      else if (k === "outline") v = Math.round(v * ky);
      else if (k === "x") v = v === 0 ? 0 : (v > 0 ? 1 : -1) * Math.max(1, Math.round(Math.abs(v) * kx));
      else if (k === "y") v = v === 0 ? 0 : (v > 0 ? 1 : -1) * Math.max(1, Math.round(Math.abs(v) * ky));
      out[k] = v;
    });
    return out;
  }

  function applyCorrections(r) {
    var corr = r && r.corrections;
    if (corr) Object.keys(corr).forEach(function (k) {
      var p = k.split(".");
      if (p.length === 3 && /^osd[01]$/.test(p[0]) && items[+p[0][3]][p[1]])
        items[+p[0][3]][p[1]][p[2]] = corr[k];
    });
    var t = window.timpsApi.takeCorrections(r);
    if (t) toast("info", window.timpsApi.correctionsText(t));
  }

  // write leaves to slot i on S (and, linked, scaled onto the other stream)
  function push(i, leaves, opts) {
    opts = opts || {};
    var body = {}, targets = linked ? [S, 1 - S] : [S];
    targets.forEach(function (s) {
      var l = s === S ? leaves : scaled(leaves, S, s);
      body["osd" + s] = {}; body["osd" + s][String(i)] = l;
      Object.keys(l).forEach(function (k) { (items[s][i] = items[s][i] || {})[k] = l[k]; });
    });
    if (leaves.enabled) {
      var need = targets.filter(function (s) { return !bootEnabled[s][i]; })
        .map(function (s) { return "osd" + s + "." + i + ".enabled"; });
      if (need.length) ui().markPending(need);
    }
    var p = opts.debounce ? window.timpsApi.setDebounced(body, 300) : window.timpsApi.set(body);
    return p.then(function (r) {
      applyCorrections(r);
      if (r && r.rejected > 0)
        toast("warning", "Applied, but the streamer refused " + r.rejected + " value(s).");
      if (!opts.quiet) render();
    }, function (err) { toast("danger", "Failed to apply setting: " + (err.message || err)); });
  }

  // ---- preview boxes ---------------------------------------------------

  var measureCtx = null;
  function expand(t) {
    var d = new Date(), p = function (n) { return String(n).padStart(2, "0"); };
    var map = { Y: d.getFullYear(), m: p(d.getMonth() + 1), d: p(d.getDate()), H: p(d.getHours()),
      M: p(d.getMinutes()), S: p(d.getSeconds()), y: p(d.getFullYear() % 100), e: d.getDate(),
      F: d.getFullYear() + "-" + p(d.getMonth() + 1) + "-" + p(d.getDate()),
      T: p(d.getHours()) + ":" + p(d.getMinutes()) + ":" + p(d.getSeconds()),
      a: "Mon", b: "Jan", Z: "CET", z: "+0100", "%": "%" };
    var uc = window.thinginoUIConfig || {};
    var host = (uc.footer && uc.footer.host) || (uc.device && uc.device.hostname) || window.location.hostname;
    var ph = { hostname: host, ip: window.location.hostname, uptime: "0:00:00",
      fps: "25.0", bitrate: "1234", mac: "00:00:00:00:00:00", net: "1.2 M", cpu: "12%", mem: "40%", clients: "1" };
    return String(t || "").replace(/%([A-Za-z%])/g, function (m, c) { return map[c] !== undefined ? map[c] : m; })
      .replace(/\{([a-z0-9_]+)\}/gi, function (m, k) { return ph[k.replace(/\d+$/, "")] || "xxxx"; });
  }

  // the TTF timps rendered with (osd.font_path at streamer start), fetched from the camera
  var osdFont = "sans-serif", fontPath = "";
  function useFont(path) {
    var m = /^\/usr\/share\/fonts\/([A-Za-z0-9._-]+)$/.exec(path || "");
    if (!m || path === fontPath || !window.FontFace) return;
    fontPath = path;
    var fam = "timpsOsd" + Date.now();
    new FontFace(fam, "url(/x/timps-upload.cgi?kind=font&raw=" + m[1] + ")").load().then(function (f) {
      document.fonts.add(f);
      osdFont = fam;
      renderBoxes();
    }, function () { osdFont = "sans-serif"; });
  }

  // same geometry as msttf_render(): em = font_size, pad on every side, even width
  function boxSize(it) {
    if (it.type === "logo") return { w: 100, h: 30, pad: 0 };
    var fs = Math.min(512, Math.max(8, num(it.font_size, 16)));
    var ol = Math.min(Math.max(0, num(it.outline, 0)), Math.floor(fs / 4) + 1);
    if (/^0x00/i.test(it.outline_color || "")) ol = 0;
    var pad = Math.floor(fs / 4) + 1 + ol;
    if (!measureCtx) measureCtx = document.createElement("canvas").getContext("2d");
    measureCtx.font = fs + "px " + osdFont;
    if ("fontKerning" in measureCtx) measureCtx.fontKerning = "none";
    var w = Math.floor(measureCtx.measureText(expand(it.text) || " ").width + 2 * pad);
    return { w: (w + 1) & ~1, h: fs + 2 * pad, pad: pad };
  }

  // region placed like resolve_pos(), the frame drawn around the text (region minus pad)
  function placeBox(el, it) {
    var W = dims[S].w, H = dims[S].h, a = anchorOf(it), sz = boxSize(it);
    var ox = Math.abs(num(it.x, 0)), oy = Math.abs(num(it.y, 0));
    var left = a[1] === "l" ? ox : a[1] === "r" ? W - ox - sz.w : Math.floor((W - sz.w) / 2);
    var top = a[0] === "t" ? oy : a[0] === "b" ? H - oy - sz.h : Math.floor((H - sz.h) / 2);
    left = Math.max(0, Math.min(left, W - sz.w));
    top = Math.max(0, Math.min(top, H - sz.h));
    el.style.left = ((left + sz.pad) / W * 100) + "%";
    el.style.top = ((top + sz.pad) / H * 100) + "%";
    el.style.width = ((sz.w - 2 * sz.pad) / W * 100) + "%";
    el.style.height = ((sz.h - 2 * sz.pad) / H * 100) + "%";
  }

  function renderBoxes() {
    var host = $id("osd-boxes");
    host.style.cssText = "position:absolute;inset:0";
    host.innerHTML = "";
    Object.keys(shown).forEach(function (k) {
      var i = +k, it = items[S][i];
      if (!it || !Number(it.enabled)) return;
      var b = document.createElement("div");
      b.className = "tv-box" + (i === openItem ? " sel" : "");
      b.title = it.type === "logo" ? "logo" : it.text;
      placeBox(b, it);
      b.addEventListener("pointerdown", function (e) { startDrag(e, b, i); });
      host.appendChild(b);
    });
  }

  function lockHint(axis) {
    toast("info", axis === "x"
      ? "Centred horizontally. Pick a left or right anchor to move it sideways."
      : "Centred vertically. Pick a top or bottom anchor to move it up or down.", 3500);
  }

  function startDrag(e, el, i) {
    e.preventDefault();
    if (openItem !== i) { openItem = i; render(); $id("frame").focus({ preventScroll: true }); return; }
    var it = items[S][i], a = anchorOf(it), frame = $id("frame");
    var k = dims[S].w / frame.clientWidth;
    var x0 = e.clientX, y0 = e.clientY, sx = num(it.x, 0), sy = num(it.y, 0);
    dragging = true;
    el.setPointerCapture(e.pointerId);
    function move(ev) {
      var dx = (ev.clientX - x0) * k, dy = (ev.clientY - y0) * k;
      var nx = a[1] === "c" ? 0 : a[1] === "l" ? Math.max(1, sx + dx) : -Math.max(1, -sx - dx);
      var ny = a[0] === "m" ? 0 : a[0] === "t" ? Math.max(1, sy + dy) : -Math.max(1, -sy - dy);
      it.x = Math.round(nx); it.y = Math.round(ny);
      placeBox(el, it); syncEditor(i);
    }
    function up(ev) {
      el.removeEventListener("pointermove", move);
      el.removeEventListener("pointerup", up);
      dragging = false;
      if (a[1] === "c" && Math.abs(ev.clientX - x0) > 8) lockHint("x");
      else if (a[0] === "m" && Math.abs(ev.clientY - y0) > 8) lockHint("y");
      if (it.x !== sx || it.y !== sy) push(i, { x: it.x, y: it.y });
    }
    el.addEventListener("pointermove", move);
    el.addEventListener("pointerup", up);
  }

  function nudge(e) {
    if (openItem < 0 || document.body.getAttribute("data-pane") === "privacy") return;
    var d = { ArrowLeft: [-1, 0], ArrowRight: [1, 0], ArrowUp: [0, -1], ArrowDown: [0, 1] }[e.key];
    if (!d) return;
    e.preventDefault();
    var it = items[S][openItem], a = anchorOf(it), step = e.shiftKey ? 10 : 1;
    var x = num(it.x, 0), y = num(it.y, 0);
    if (d[0]) {
      if (a[1] === "c") { lockHint("x"); return; }
      x = a[1] === "l" ? Math.max(1, x + d[0] * step) : -Math.max(1, -x - d[0] * step);
    }
    if (d[1]) {
      if (a[0] === "m") { lockHint("y"); return; }
      y = a[0] === "t" ? Math.max(1, y + d[1] * step) : -Math.max(1, -y - d[1] * step);
    }
    it.x = x; it.y = y;
    renderBoxes(); syncEditor(openItem);
    push(openItem, { x: x, y: y }, { debounce: true, quiet: true });
  }

  // ---- list + editor ---------------------------------------------------

  function status(i) {
    var it = items[S][i] || {};
    if (!Number(it.enabled)) return '<span class="badge text-bg-secondary">Off</span>';
    return bootEnabled[S][i] ? '<span class="badge text-bg-success">Live</span>'
      : '<span class="badge text-bg-warning">Needs restart</span>';
  }

  function posText(it) {
    var a = anchorOf(it), ox = Math.abs(num(it.x, 0)), oy = Math.abs(num(it.y, 0));
    var off = a === "mc" ? "" : " " + (a[1] === "c" ? oy : a[0] === "m" ? ox : ox + "/" + oy);
    return POS_NAME[a] + off + (it.type === "logo" ? "" : " · " + num(it.font_size, 0) + " px");
  }

  function xLabel(a) { return a[1] === "l" ? "From left" : a[1] === "r" ? "From right" : "Centred"; }
  function yLabel(a) { return a[0] === "t" ? "From top" : a[0] === "b" ? "From bottom" : "Centred"; }
  function cfgText(i, it) { return "osd" + S + "." + i + ".x = " + num(it.x, 0) + ", y = " + num(it.y, 0); }

  function syncEditor(i) {
    var ed = document.querySelector('.tv-item[data-item="' + i + '"]');
    if (!ed) return;
    var it = items[S][i];
    var ox = ed.querySelector(".e-ox"), oy = ed.querySelector(".e-oy");
    if (ox) ox.value = Math.abs(num(it.x, 0)) || "";
    if (oy) oy.value = Math.abs(num(it.y, 0)) || "";
    var c = ed.querySelector(".tv-cfg"); if (c) c.textContent = cfgText(i, it);
    var p = ed.querySelector(".tv-pos"); if (p) p.textContent = posText(it);
  }

  function field(label, inner, leaf, extra) {
    var ok = leafOk(leaf);
    return '<div class="' + (extra || "") + (ok ? "" : " opacity-50") + '"' + (ok ? "" : ' title="Not supported by the running streamer"') +
      '><label>' + label + "</label>" + (ok ? inner : inner.replace(/<(input|select)/g, "<$1 disabled")) + "</div>";
  }

  function editorHtml(i, it) {
    var a = anchorOf(it), text = it.type !== "logo";
    var fc = fromColor(it.color), sc = fromColor(it.outline_color);
    var grid = ANCHORS.map(function (x) {
      return '<button type="button" data-a="' + x + '" aria-label="' + POS_NAME[x] + '"' +
        (x === a ? ' class="active"' : "") + "></button>";
    }).join("");
    var h = '<div class="tv-fields">';
    if (text) h += field('Text <span class="tv-badge live">live</span>',
      '<input type="text" class="form-control e-text" placeholder="%F %T or {hostname}">', "text", "grid-column-full");
    h += '<div><label>Anchor</label><div class="tv-anchor">' + grid + "</div></div>";
    h += field(xLabel(a), '<input type="number" min="1" class="form-control e-ox"' + (a[1] === "c" ? " disabled" : "") + ">", "x");
    h += field(yLabel(a), '<input type="number" min="1" class="form-control e-oy"' + (a[0] === "m" ? " disabled" : "") + ">", "y");
    if (text) {
      h += field("Size, px", '<input type="number" min="8" max="128" class="form-control e-size">', "font_size");
      h += field("Outline, px", '<input type="number" min="0" max="64" class="form-control e-outline">', "outline");
      h += field("Colour", '<div class="d-flex gap-2 align-items-center"><input type="color" class="form-control form-control-color e-fill">' +
        '<input type="range" min="0" max="255" class="form-range e-fill-a" title="Opacity"></div>', "color");
      h += field("Outline colour", '<div class="d-flex gap-2 align-items-center"><input type="color" class="form-control form-control-color e-stroke">' +
        '<input type="range" min="0" max="255" class="form-range e-stroke-a" title="Opacity"></div>', "outline_color");
    }
    h += field('Transparency <span class="e-trans-v text-body-secondary"></span>',
      '<input type="range" min="0" max="255" class="form-range e-trans">', "transparency");
    h += "</div>";
    h += '<div class="d-flex flex-wrap align-items-center gap-2 mt-2"><span class="tv-cfg me-auto">' + cfgText(i, it) +
      '</span><button type="button" class="btn btn-sm btn-outline-danger e-remove"><i class="bi bi-trash me-1"></i>Remove</button></div>';
    if (it.type === "logo")
      h += '<p class="form-text mb-0">The logo image is set in the streamer configuration file.</p>';
    return h;
  }

  function wireEditor(box, i) {
    var it = items[S][i], a = anchorOf(it);
    function q(c) { return box.querySelector(c); }
    function set(c, v) { var el = q(c); if (el) el.value = v; }
    set(".e-text", it.text || "");
    set(".e-ox", Math.abs(num(it.x, 0)) || "");
    set(".e-oy", Math.abs(num(it.y, 0)) || "");
    set(".e-size", num(it.font_size, 16));
    set(".e-outline", num(it.outline, 0));
    var fc = fromColor(it.color), sc = fromColor(it.outline_color);
    set(".e-fill", fc.color); set(".e-fill-a", fc.alpha);
    set(".e-stroke", sc.color); set(".e-stroke-a", sc.alpha);
    var tr = it.transparency === undefined ? 255 : num(it.transparency, 255);
    set(".e-trans", tr);
    if (q(".e-trans-v")) q(".e-trans-v").textContent = "(" + tr + ")";

    Array.prototype.forEach.call(box.querySelectorAll(".tv-anchor button"), function (b) {
      b.addEventListener("click", function () {
        var na = b.getAttribute("data-a");
        if (na === a) return;
        var xy = toXY(na, Math.abs(num(it.x, 0)) || 10, Math.abs(num(it.y, 0)) || 10);
        push(i, xy);
      });
    });
    function onChange(c, fn) { var el = q(c); if (el) el.addEventListener("change", fn); }
    onChange(".e-text", function () { push(i, { text: q(".e-text").value }); });
    onChange(".e-ox", function () { push(i, toXY(a, num(q(".e-ox").value, 1), Math.abs(num(it.y, 0)))); });
    onChange(".e-oy", function () { push(i, toXY(a, Math.abs(num(it.x, 0)), num(q(".e-oy").value, 1))); });
    onChange(".e-size", function () { push(i, { font_size: Math.min(128, Math.max(8, num(q(".e-size").value, 16))) }); });
    onChange(".e-outline", function () { push(i, { outline: Math.min(64, Math.max(0, num(q(".e-outline").value, 0))) }); });
    [".e-fill", ".e-fill-a"].forEach(function (c) {
      onChange(c, function () { var v = toColor(q(".e-fill").value, num(q(".e-fill-a").value, 255)); if (v) push(i, { color: v }); });
    });
    [".e-stroke", ".e-stroke-a"].forEach(function (c) {
      onChange(c, function () { var v = toColor(q(".e-stroke").value, num(q(".e-stroke-a").value, 255)); if (v) push(i, { outline_color: v }); });
    });
    var trans = q(".e-trans");
    if (trans) {
      trans.addEventListener("input", function () { q(".e-trans-v").textContent = "(" + trans.value + ")"; });
      trans.addEventListener("change", function () { push(i, { transparency: num(trans.value, 255) }); });
    }
    q(".e-remove").addEventListener("click", function () {
      delete shown[i];
      if (openItem === i) openItem = -1;
      push(i, { enabled: 0 });
    });
  }

  function render() {
    var host = $id("osd-items");
    host.innerHTML = "";
    var keys = Object.keys(shown).map(Number).sort(function (a, b) { return a - b; });
    keys.forEach(function (i) {
      var it = items[S][i] || {};
      var w = document.createElement("div");
      w.className = "tv-item" + (i === openItem ? " open" : "");
      w.setAttribute("data-item", String(i));
      w.innerHTML = '<div class="tv-ih"><div class="form-check form-switch m-0"><input class="form-check-input e-en" type="checkbox" role="switch" aria-label="Show overlay"' +
        (Number(it.enabled) ? " checked" : "") + "></div>" +
        '<span class="badge text-bg-dark border fw-normal">' + (it.type === "logo" ? "logo" : "text") + "</span>" +
        '<span class="tv-tx"></span><span class="tv-pos">' + posText(it) + "</span>" + status(i) + "</div>";
      w.querySelector(".tv-tx").textContent = it.type === "logo" ? "Logo" : (it.text || "(empty)");
      if (i === openItem) {
        var ib = document.createElement("div");
        ib.className = "tv-ib";
        ib.innerHTML = editorHtml(i, it);
        w.appendChild(ib);
        wireEditor(ib, i);
      }
      w.querySelector(".tv-ih").addEventListener("click", function (e) {
        if (e.target.closest(".form-check")) return;
        openItem = openItem === i ? -1 : i;
        render();
        if (openItem >= 0) $id("frame").focus({ preventScroll: true });
      });
      w.querySelector(".e-en").addEventListener("change", function () { push(i, { enabled: this.checked ? 1 : 0 }); });
      host.appendChild(w);
    });
    $id("osd-items-empty").classList.toggle("d-none", keys.length > 0);
    $id("osd-add-item").disabled = keys.length >= MAX_OSD;
    $id("osd-slot-count").textContent = keys.length + " of " + MAX_OSD + " overlays";
    renderBoxes();
  }

  function renderLink() {
    $id("osd-link").checked = linked;
    $id("osd-link-txt").innerHTML = linked
      ? "Editing <b>both streams</b>. Sizes and offsets scale to each resolution."
      : "Editing the <b>" + NAME[S] + "</b> only. Switch on to edit both streams together.";
  }

  // ---- load ------------------------------------------------------------

  function inUse(it) {
    return it && (Number(it.enabled) || (it.text && String(it.text).length) || it.type === "logo");
  }

  function selectStream(s) {
    S = s;
    shown = {};
    for (var i = 0; i < MAX_OSD; i++) if (inUse(items[S][i])) shown[i] = true;
    if (!shown[openItem]) openItem = -1;
    renderLink();
    render();
  }

  function offlineNotice(show) {
    var n = $id("timps-offline-notice");
    if (!show) { if (n) n.remove(); return; }
    if (n) return;
    n = document.createElement("div");
    n.id = "timps-offline-notice";
    n.className = "alert alert-warning";
    n.innerHTML = '<i class="bi bi-exclamation-triangle me-1"></i>The streamer is not reachable, ' +
      "overlay controls are disabled. Check that the timps service is running, then reload this page.";
    var tabs = document.querySelector(".tv-tabs");
    tabs.parentNode.insertBefore(n, tabs);
  }

  function load(first) {
    if (!window.timpsApi) { offlineNotice(true); return; }
    window.timpsApi.get().then(function (json) {
      capsOsd = (json.caps && json.caps.osd) || [];
      [0, 1].forEach(function (s) {
        var set = json["osd" + s] || {};
        var v = json.video && json.video[s];
        if (v && v.width) dims[s] = { w: +v.width, h: +v.height };
        ui().setTabSummary(s, v && v.width ? v.width + "×" + v.height : "");
        for (var i = 0; i < MAX_OSD; i++) {
          items[s][i] = set[String(i)] || {};
          if (first) bootEnabled[s][i] = !!Number(items[s][i].enabled);
        }
      });
      if (json.osd && json.osd.enabled !== undefined) $id("osd-master").checked = !!Number(json.osd.enabled);
      if (first && json.osd) useFont(json.osd.font_path);
      offlineNotice(false);
      var keep = shown;
      selectStream(S);
      Object.keys(keep).forEach(function (k) { shown[k] = true; });
      render();
    }, function () { offlineNotice(true); });
  }

  function typing() {
    var ae = document.activeElement;
    return !!ae && /^(INPUT|SELECT|TEXTAREA)$/.test(ae.tagName) && ae.type !== "checkbox";
  }

  function onEvent(type, data) {
    if (!data || dragging) return;
    if (!data.resync) {
      var key = data.key || "";
      if (key !== "osd.enabled" && !/^osd[01]\./.test(key)) return;
    }
    if (typing()) { reloadLater = true; return; }
    load(false);
  }

  var FONT_DIR = "/usr/share/fonts/";
  function setFont(path) {
    return window.timpsApi.set({ osd: { font_path: path } }).then(function (r) {
      ui().markPending((r && r.deferred_keys) || ["osd.font_path"]);
    }, function (e) { ui().toast("danger", "Font: " + (e.message || e)); });
  }
  // select box: every font in FONT_DIR, current = osd.font_path; an upload lands in default.ttf
  function fontList(j, uploaded) {
    var sel = $id("osd-font-sel");
    if (!sel || !j.fonts) return;
    window.timpsApi.get().then(function (c) {
      var cur = (c.osd && c.osd.font_path) || FONT_DIR + "default.ttf";
      var paths = j.fonts.map(function (f) { return FONT_DIR + f; });
      if (paths.indexOf(cur) < 0) paths.unshift(cur);
      sel.innerHTML = "";
      paths.forEach(function (p) {
        var o = document.createElement("option");
        o.value = p;
        o.textContent = p.indexOf(FONT_DIR) === 0 ? p.slice(FONT_DIR.length) : p;
        sel.appendChild(o);
      });
      sel.value = cur;
      sel.disabled = false;
      if (uploaded && cur !== FONT_DIR + "default.ttf") {
        sel.value = FONT_DIR + "default.ttf";
        setFont(sel.value);
      }
    });
  }

  function init() {
    if (!window.timpsUi) return;
    try { linked = localStorage.getItem("timps-osd-link") === "1"; } catch (e) {}
    S = ui().initTabs(function (s) { selectStream(s); });
    ui().uploadCard($id("osd-font"), "font", "OSD font", fontList);
    // any streamer restart (restart bar or outside): new font/boot state
    document.addEventListener("timps-back", function () { load(true); });
    renderLink();

    $id("osd-font-sel").addEventListener("change", function () { setFont(this.value); });
    $id("osd-link").addEventListener("change", function () {
      linked = this.checked;
      try { localStorage.setItem("timps-osd-link", linked ? "1" : "0"); } catch (e) {}
      renderLink();
    });
    $id("osd-master").addEventListener("change", function () {
      var on = this.checked ? 1 : 0;
      window.timpsApi.set({ osd: { enabled: on } }).then(function (r) {
        if (r && r.changed !== 0) ui().markPending(["osd.enabled"]);
      }, function (err) { toast("danger", "Failed to apply setting: " + (err.message || err)); });
    });
    $id("osd-add-item").addEventListener("click", function () {
      for (var i = 0; i < MAX_OSD; i++) {
        if (shown[i]) continue;
        shown[i] = true;
        openItem = i;
        var it = items[S][i];
        if (!it || it.type !== "logo") items[S][i] = Object.assign({ type: "text", text: "", x: 10, y: 10 }, it || {});
        render();
        return;
      }
    });
    $id("frame").addEventListener("keydown", nudge);
    document.addEventListener("focusout", function () {
      setTimeout(function () {
        if (reloadLater && !typing() && !dragging) { reloadLater = false; load(false); }
      }, 0);
    });
    window.addEventListener("resize", renderBoxes);
    load(true);
    if (window.timpsApi) window.timpsApi.events("config", onEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
