// streamer-encoder.js - video encoder page, both streams behind tabs.
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-video") return;

  var idx = 0;      // stream shown in the form
  var last = null;  // last GET /control
  var stats = null; // last "stats" event
  var videoLive = null;
  var curMode = "";

  // form field suffix (id "v-<suffix>") -> timps video.* key + value type
  var FIELD_MAP = {
    width: { key: "width", type: "int" },
    height: { key: "height", type: "int" },
    format: { key: "codec", type: "codec" },
    fps: { key: "fps", type: "int" },
    gop: { key: "gop", type: "int" },
    bitrate: { key: "bitrate", type: "int" },
    profile: { key: "profile", type: "int" },
    buffers: { key: "buffers", type: "int" },
    rtsp_endpoint: { key: "rtsp_path", type: "str" },
    enabled: { key: "enabled", type: "bool" },
    qp: { key: "qp", type: "int" },
    min_qp: { key: "min_qp", type: "int" },
    max_qp: { key: "max_qp", type: "int" },
    quality_lvl: { key: "quality_lvl", type: "int" },
    change_pos: { key: "change_pos", type: "int" },
    i_bias_lvl: { key: "i_bias_lvl", type: "int" },
    fluc_lvl: { key: "fluc_lvl", type: "int" },
  };
  var KEY_TO_SUFFIX = {};
  Object.keys(FIELD_MAP).forEach(function (s) { KEY_TO_SUFFIX[FIELD_MAP[s].key] = s; });

  var RC_FIELDS = {
    qp: { modes: ["FIXQP"], name: "Fixed QP" },
    min_qp: {},
    quality_lvl: { modes: ["VBR", "SMART"], classicOnly: true, name: "Quality level" },
    change_pos: { modes: ["VBR", "SMART"], classicOnly: true, name: "Change position" },
    i_bias_lvl: { name: "I-frame bias" },   // classic yes, T31/C100 via QpIPDelta, T40/T41 no
    fluc_lvl: { codecs: ["H265"], classicOnly: true, name: "Fluctuation level" },
  };
  var CLASSIC_FAMS = ["t10", "t20", "t21", "t23", "t30"];
  var NO_IBIAS_FAMS = ["t40", "t41"];
  var SOC_MODE = {
    t10: ["CBR", "VBR", "FIXQP", "SMART"], t20: ["CBR", "VBR", "FIXQP", "SMART"],
    t21: ["CBR", "VBR", "FIXQP", "SMART"], t23: ["CBR", "VBR", "FIXQP", "SMART"],
    t30: ["CBR", "VBR", "FIXQP", "SMART"],
    t31: ["CBR", "VBR", "FIXQP", "CAPPED_VBR", "CAPPED_QUALITY"],
    t40: ["CBR", "VBR", "FIXQP", "CAPPED_VBR", "CAPPED_QUALITY"],
    t41: ["CBR", "VBR", "FIXQP", "CAPPED_VBR", "CAPPED_QUALITY"],
    c100: ["CBR", "VBR", "FIXQP", "CAPPED_VBR", "CAPPED_QUALITY"],
  };
  var SOC_FMT = {
    t10: ["H264"], t20: ["H264"], t21: ["H264"], t23: ["H264"],
    t30: ["H264", "H265"], t31: ["H264", "H265"], t40: ["H264", "H265"],
    t41: ["H264", "H265"], c100: ["H264", "H265"],
  };
  var DEF_MODE = ["CBR", "VBR", "FIXQP", "CAPPED_VBR", "CAPPED_QUALITY"];
  var DEF_FMT = ["H264", "H265"];
  var PROFILE = ["Baseline", "Main", "High"];

  function $id(id) { return document.getElementById(id); }
  function ui() { return window.timpsUi; }
  function toast(t, m, ms) { ui().toast(t, m, ms); }

  function socFamily() {
    var soc = window.thinginoUIConfig && window.thinginoUIConfig.device &&
      window.thinginoUIConfig.device.soc;
    var m = soc && String(soc).toLowerCase().match(/^(t\d+|c\d+)/);
    return m ? m[1] : null;
  }

  function isLive(key) {
    if (key === "rtsp_path") return true;
    return !!videoLive && videoLive.indexOf(key) >= 0;
  }

  function streamSummary(v) {
    if (!v || !v.width) return "";
    return v.width + "×" + v.height + " · " + String(v.codec || "").toUpperCase() +
      " · " + v.fps + " fps";
  }

  // ---- save -------------------------------------------------------------

  function verdict(r, key) {
    var full = "video" + idx + "." + key;
    var deferred = r && Array.isArray(r.deferred_keys)
      ? r.deferred_keys.indexOf(full) >= 0 : !isLive(key);
    if (deferred) { if (!r || r.changed !== 0) ui().markPending([full]); return; }
    if (!r || !r.changed) return;
    toast("success", key === "rtsp_path"
      ? "Applied; new RTSP connections use the new path."
      : "Applied to the running encoder; takes effect at the next keyframe.", 3000);
  }

  function applyCorrections(r) {
    var corr = r && r.corrections;
    if (corr) Object.keys(corr).forEach(function (k) {
      var m = /^video(\d)\.(.+)$/.exec(k);
      if (m && +m[1] === idx && KEY_TO_SUFFIX[m[2]]) {
        var one = {}; one[m[2]] = corr[k];
        populate(KEY_TO_SUFFIX[m[2]], one);
      }
    });
    var t = window.timpsApi.takeCorrections(r);
    if (t) toast("info", window.timpsApi.correctionsText(t));
  }

  function post(key, value, busyEl) {
    var inner = {}; inner[key] = value;
    var video = {}; video[idx] = inner;
    var s = idx;
    if (busyEl) busyEl.classList.add("opacity-75");
    return window.timpsApi.set({ video: video }).then(function (r) {
      if (s !== idx) return;
      applyCorrections(r);
      verdict(r, key);
      if (last && last.video && last.video[s]) last.video[s][key] = value;
      renderMeta();
      if (key === "rc_mode" || key === "codec") rcGate();
      refreshRcHolds();
    }, function (err) {
      toast("danger", "Failed to save setting: " + (err.message || err));
    }).then(function () { if (busyEl) busyEl.classList.remove("opacity-75"); });
  }

  function readValue(suffix) {
    var el = $id("v-" + suffix), map = FIELD_MAP[suffix];
    if (!el) return undefined;
    if (map.type === "bool") return el.checked ? 1 : 0;
    if (map.type === "codec") return el.value ? el.value.toLowerCase() : undefined;
    if (map.type === "str") return el.value;
    var n = parseInt(el.value, 10);
    return isNaN(n) ? undefined : n;
  }

  // ---- fill -------------------------------------------------------------

  function populate(suffix, video) {
    var el = $id("v-" + suffix), map = FIELD_MAP[suffix];
    if (!el) return;
    var v = video[map.key];
    if (v === undefined || v === null) return;
    if (map.type === "bool") el.checked = !!Number(v);
    else if (map.type === "codec") el.value = String(v).toUpperCase();
    else el.value = v;
  }

  function fillSelect(sel, values) {
    sel.innerHTML = "";
    values.forEach(function (v) {
      var o = document.createElement("option");
      o.value = v; o.textContent = v === "H264" ? "H.264" : v === "H265" ? "H.265" : v;
      sel.appendChild(o);
    });
  }

  function renderModes() {
    var box = $id("v-modes"), fam = socFamily();
    box.innerHTML = "";
    ((fam && SOC_MODE[fam]) || DEF_MODE).forEach(function (m) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "btn btn-outline-secondary" + (m === curMode ? " active" : "");
      b.textContent = m.replace(/_/g, " ");
      b.addEventListener("click", function () {
        if (m === curMode) return;
        curMode = m; renderModes(); rcGate();
        post("rc_mode", m.toLowerCase(), box);
      });
      box.appendChild(b);
    });
  }

  function renderBadges() {
    Array.prototype.forEach.call(document.querySelectorAll("[data-badge]"), function (el) {
      el.innerHTML = ui().badge(isLive(el.getAttribute("data-badge")));
    });
  }

  function chip(label, value) {
    return '<span class="badge rounded-pill text-bg-dark border fw-normal">' +
      '<b class="fw-semibold">' + value + "</b> " + label + "</span>";
  }

  function renderChips() {
    var box = $id("v-chips");
    if (!stats) { box.innerHTML = ""; return; }
    var s = null;
    (stats.video || []).forEach(function (v) { if (v.chn === idx) s = v; });
    var h = "";
    if (s) {
      h += chip("", s.kbps >= 1000 ? (s.kbps / 1000).toFixed(2) + " Mbit/s" : Math.round(s.kbps) + " kbit/s");
      h += chip("fps", Number(s.fps).toFixed(1));
      h += chip(s.subs === 1 ? "subscriber" : "subscribers", s.subs);
      if (s.drop_frames) h += chip("dropped", s.drop_frames);
    }
    if (stats.clients !== undefined) h += chip("clients total", stats.clients);
    box.innerHTML = h;
  }

  function renderMeta() {
    if (!last || !last.video) return;
    [0, 1].forEach(function (i) { ui().setTabSummary(i, streamSummary(last.video[i])); });
    var v = last.video[idx] || {};
    $id("v-url").value = "rtsp://" + window.location.hostname + (v.rtsp_path || "");
    var fps = parseInt(v.fps, 10), gop = parseInt(v.gop, 10);
    $id("v-gop-s").textContent = fps > 0 && gop > 0
      ? "frames = " + (gop / fps).toFixed(gop % fps ? 1 : 0) + " s at " + fps + " fps" : "";
    renderCompare();
    renderChips();
  }

  function renderCompare() {
    var tb = document.querySelector("#v-cmp tbody");
    if (!tb || !last || !last.video) return;
    var rows = [
      ["Resolution", function (v) { return v.width + "×" + v.height; }],
      ["Frame rate", function (v) { return v.fps + " fps"; }],
      ["Codec / profile", function (v) { return String(v.codec).toUpperCase() + " " + (PROFILE[v.profile] || v.profile); }],
      ["Mode", function (v) { return String(v.rc_mode).toUpperCase(); }],
      ["Bitrate", function (v) { return v.bitrate + " kbit/s"; }],
      ["QP range", function (v) { return v.min_qp + "–" + v.max_qp; }],
      ["Keyframe", function (v) { return v.gop + " frames"; }],
      ["RTSP path", function (v) { return v.rtsp_path; }],
      ["Enabled", function (v) { return Number(v.enabled) ? "yes" : "no"; }],
    ];
    var a = last.video[0] || {}, b = last.video[1] || {};
    tb.innerHTML = "";
    rows.forEach(function (r) {
      var tr = document.createElement("tr"), va = r[1](a), vb = r[1](b);
      if (va !== vb) tr.className = "diff";
      [r[0], va, vb].forEach(function (t, i) {
        var td = document.createElement("td"); td.textContent = t;
        if (i) td.className = "font-monospace";
        tr.appendChild(td);
      });
      tb.appendChild(tr);
    });
  }

  // hide rc fields that do nothing for this SoC/mode/codec, and say which
  function rcGate() {
    var fam = socFamily();
    var classic = fam ? CLASSIC_FAMS.indexOf(fam) >= 0 : null;
    var codec = $id("v-format").value;
    var hidden = [];
    Object.keys(RC_FIELDS).forEach(function (suffix) {
      var info = RC_FIELDS[suffix];
      var wrap = document.querySelector('[data-rc="' + suffix + '"]');
      if (!wrap) return;
      var off = null;
      if (classic === false && info.classicOnly) off = "not on this SoC";
      else if (classic === false && suffix === "i_bias_lvl" && NO_IBIAS_FAMS.indexOf(fam) >= 0)
        off = "not on this SoC";
      else if (info.modes && curMode && info.modes.indexOf(curMode) < 0)
        off = info.modes.join("/") + " only";
      else if (info.codecs && codec && info.codecs.indexOf(codec) < 0)
        off = info.codecs.join("/") + " only";
      wrap.classList.toggle("d-none", !!off);
      if (off) hidden.push(info.name + " (" + off + ")");
    });
    $id("v-hidden").textContent = hidden.length ? "Hidden: " + hidden.join(", ") + "." : "";
  }

  var RC_HOLD_ORDER = ["rc_mode", "bitrate", "max_bitrate", "qp", "min_qp",
    "max_qp", "quality_lvl", "change_pos", "i_bias_lvl", "fluc_lvl",
    "static_time", "frm_qp_step", "gop_qp_step", "ip_delta", "pb_delta", "max_psnr"];
  function refreshRcHolds() {
    var el = $id("v-holds"), s = idx;
    window.timpsApi.get().then(function (json) {
      if (s !== idx) return;
      var rc = json.encoder && json.encoder[s] && json.encoder[s].rc;
      if (!rc) { el.textContent = "Encoder readback: not available (channel not running)."; return; }
      var parts = [];
      RC_HOLD_ORDER.forEach(function (k) {
        if (rc[k] !== undefined) parts.push(k.replace(/_/g, " ") + " " + rc[k]);
      });
      el.textContent = "Encoder holds: " + parts.join(", ");
    }, function () { el.textContent = "Encoder readback: streamer not reachable."; });
  }

  function fill() {
    if (!last) return;
    var video = (last.video && last.video[idx]) || {};
    Object.keys(FIELD_MAP).forEach(function (s) { populate(s, video); });
    curMode = String(video.rc_mode || "").toUpperCase();
    var au = $id("v-audio_enabled");
    if (last.audio && last.audio.enabled !== undefined) au.checked = !!Number(last.audio.enabled);
    renderModes(); renderMeta(); rcGate(); refreshRcHolds();
  }

  function setDisabled(off) {
    Array.prototype.forEach.call(document.querySelectorAll("main input, main select, #v-modes button"),
      function (el) { if (el.id !== "v-url" && el.id !== "v-compare") el.disabled = off; });
  }

  function offlineNotice(show) {
    var n = $id("timps-offline-notice");
    if (!show) { if (n) n.remove(); return; }
    if (n) return;
    n = document.createElement("div");
    n.id = "timps-offline-notice";
    n.className = "alert alert-warning";
    n.innerHTML = '<i class="bi bi-exclamation-triangle me-1"></i>The streamer is not reachable, ' +
      "encoder controls are disabled. Check that the timps service is running, then reload this page.";
    var tabs = document.querySelector(".tv-tabs");
    tabs.parentNode.insertBefore(n, tabs);
  }

  function load() {
    if (!window.timpsApi) { offlineNotice(true); setDisabled(true); return; }
    window.timpsApi.get().then(function (json) {
      last = json;
      videoLive = (json.caps && json.caps.video_live) || [];
      renderBadges();
      setDisabled(false);
      fill();
      offlineNotice(false);
    }, function () { offlineNotice(true); setDisabled(true); });
  }

  function onEvent(type, data) {
    if (!data) return;
    if (type === "stats") { stats = data; renderChips(); return; }
    if (data.resync) { load(); return; }
    if (data.key === "audio.enabled") {
      var au = $id("v-audio_enabled");
      if (document.activeElement !== au) au.checked = !!Number(data.value);
      return;
    }
    var m = /^video(\d)\.(.+)$/.exec(data.key || "");
    if (!m || !last || !last.video) return;
    if (last.video[m[1]]) last.video[m[1]][m[2]] = data.value;
    renderMeta();
    if (+m[1] !== idx) return;
    if (m[2] === "rc_mode") { curMode = String(data.value).toUpperCase(); renderModes(); rcGate(); return; }
    var suffix = KEY_TO_SUFFIX[m[2]];
    if (!suffix || document.activeElement === $id("v-" + suffix)) return;
    var one = {}; one[m[2]] = data.value;
    populate(suffix, one);
    if (suffix === "format") rcGate();
  }

  function wire() {
    var fam = socFamily();
    fillSelect($id("v-format"), (fam && SOC_FMT[fam]) || DEF_FMT);
    Object.keys(FIELD_MAP).forEach(function (suffix) {
      var el = $id("v-" + suffix);
      if (!el) return;
      el.addEventListener("change", function () {
        var v = readValue(suffix);
        if (v !== undefined) post(FIELD_MAP[suffix].key, v, el);
        if (suffix === "format") rcGate();
      });
    });
    $id("v-audio_enabled").addEventListener("change", function () {
      var el = this;
      window.timpsApi.set({ audio: { enabled: el.checked ? 1 : 0 } }).then(function (r) {
        var deferred = !r || !Array.isArray(r.deferred_keys) || r.deferred_keys.indexOf("audio.enabled") >= 0;
        if (deferred && r && r.changed !== 0) ui().markPending(["audio.enabled"]);
      }, function (err) { toast("danger", "Failed to save setting: " + (err.message || err)); });
    });
    $id("v-compare").addEventListener("change", function () { $id("v-cmp").hidden = !this.checked; });
    $id("v-copy").addEventListener("click", function () {
      var el = $id("v-url");
      var done = function () { toast("success", "RTSP URL copied.", 2000); };
      if (navigator.clipboard && window.isSecureContext)
        navigator.clipboard.writeText(el.value).then(done, function () { el.select(); });
      else { el.select(); try { document.execCommand("copy"); done(); } catch (e) {} }
    });
  }

  function init() {
    if (!window.timpsUi) return;
    idx = ui().initTabs(function (i) { idx = i; fill(); });
    ui().onRestarted(load);
    wire();
    load();
    if (window.timpsApi) window.timpsApi.events("config,stats", onEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
