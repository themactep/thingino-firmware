/* streamer-encoder.js - NATIVE RTSP main/substream encoder page. Talks directly
 * to the timps streamer over window.timpsApi (GET/POST /control on timps's own
 * port, per-boot token) - no /x/json-prudynt.cgi bridge (a/streamer-config.js
 * is no longer loaded here). One file drives both pages; the stream index is
 * derived from the body id (page-streamer-main -> 0, page-streamer-substream
 * -> 1).
 *
 * Load:  timpsApi.get() -> populate from json.video[idx] (+ the global
 *        json.audio.enabled for the "Audio in stream" switch).
 * Save:  every change goes to timpsApi.set({video:{idx:{key:val}}}) (audio
 *        switch -> {audio:{enabled}}). timps persists immediately, but ALL
 *        video/sensor keys are restart-required (caps.restart lists "video"),
 *        so each change shows the "restart the streamer" hint.
 * Offline: if timps is unreachable the controls stay disabled + a notice.
 *
 * Kept lean on purpose (embedded target): no libraries, no polling, changes
 * fire on 'change' only, text fields are debounced through timpsApi.
 */
(function () {
  "use strict";

  var body = document.body;
  if (!body) return;
  var idx =
    body.id === "page-streamer-main" ? 0 :
    body.id === "page-streamer-substream" ? 1 : -1;
  if (idx < 0) return;

  var P = "stream" + idx + "_"; // page field id prefix

  // page field id (without prefix) -> timps video.* key + value type.
  // "int": parseInt, "str": raw string, "bool": checkbox 0/1.
  var FIELD_MAP = {
    width: { key: "width", type: "int" },
    height: { key: "height", type: "int" },
    format: { key: "codec", type: "codec" },
    fps: { key: "fps", type: "int" },
    gop: { key: "gop", type: "int" },
    max_gop: { key: "max_gop", type: "int" },
    mode: { key: "rc_mode", type: "rc" },
    bitrate: { key: "bitrate", type: "int" },
    profile: { key: "profile", type: "int" },
    buffers: { key: "buffers", type: "int" },
    rtsp_endpoint: { key: "rtsp_path", type: "str" },
    enabled: { key: "enabled", type: "bool" },
  };

  // page codec/mode spelling <-> timps canonical (lowercase) spelling
  function codecToTimps(v) { return String(v).toLowerCase(); }        // H264 -> h264
  function codecFromTimps(v) { return String(v).toUpperCase(); }      // h264 -> H264
  function rcToTimps(v) { return String(v).toLowerCase(); }           // CAPPED_VBR -> capped_vbr
  function rcFromTimps(v) { return String(v).toUpperCase(); }         // capped_vbr -> CAPPED_VBR

  // per-SoC encoder capability (same matrix streamer-config.js used)
  var SOC_MODE = {
    t10: ["CBR", "VBR", "FIXQP", "SMART"],
    t20: ["CBR", "VBR", "FIXQP", "SMART"],
    t21: ["CBR", "VBR", "FIXQP", "SMART"],
    t23: ["CBR", "VBR", "FIXQP", "SMART"],
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

  function socFamily(soc) {
    if (!soc) return null;
    var m = String(soc).toLowerCase().match(/^(t\d+|c\d+)/);
    return m ? m[1] : null;
  }

  function $id(id) { return document.getElementById(id); }

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, message, ms);
    else console.log("[streamer-encoder]", type + ":", message);
  }

  function restartHint() {
    toast(
      "warning",
      "Setting saved. Encoder changes take effect after a streamer restart (Restart streamer in the menu).",
      8000,
    );
  }

  function setEnabled(id, on) {
    var el = $id(id);
    if (!el) return;
    el.disabled = !on;
    var wrap = el.closest("p, .col, .form-switch, .select") || el.parentElement;
    if (wrap) wrap.classList.toggle("disabled", !on);
  }

  function fillSelect(select, values, current) {
    if (!select) return;
    select.innerHTML = "";
    values.forEach(function (v) {
      var o = document.createElement("option");
      o.value = v;
      o.textContent = v.replace(/_/g, " ");
      select.appendChild(o);
    });
    if (current && values.indexOf(current) >= 0) select.value = current;
  }

  function populateSelectors() {
    var soc =
      (window.thinginoUIConfig &&
        window.thinginoUIConfig.device &&
        window.thinginoUIConfig.device.soc) || null;
    var fam = socFamily(soc);
    fillSelect($id(P + "mode"), (fam && SOC_MODE[fam]) || DEF_MODE);
    fillSelect($id(P + "format"), (fam && SOC_FMT[fam]) || DEF_FMT);
  }

  // read one field's timps value; returns undefined when it should be skipped
  function readValue(suffix, map) {
    var el = $id(P + suffix);
    if (!el) return undefined;
    if (map.type === "bool") return el.checked ? 1 : 0;
    if (map.type === "codec") return el.value ? codecToTimps(el.value) : undefined;
    if (map.type === "rc") return el.value ? rcToTimps(el.value) : undefined;
    if (map.type === "str") return el.value;
    var n = parseInt(el.value, 10);
    return isNaN(n) ? undefined : n;
  }

  function send(suffix, map) {
    var value = readValue(suffix, map);
    if (value === undefined) return;
    var el = $id(P + suffix);
    var inner = {};
    inner[map.key] = value;
    var video = {};
    video[idx] = inner;
    if (el) el.classList.add("opacity-75");
    window.timpsApi
      .set({ video: video })
      .then(restartHint, function (err) {
        console.error("timps set failed:", err);
        toast("danger", "Failed to save setting: " + (err.message || err));
      })
      .then(function () { if (el) el.classList.remove("opacity-75"); });
  }

  function sendAudio() {
    var el = $id(P + "audio_enabled");
    if (!el) return;
    el.classList.add("opacity-75");
    window.timpsApi
      .set({ audio: { enabled: el.checked ? 1 : 0 } })
      .then(restartHint, function (err) {
        console.error("timps set failed:", err);
        toast("danger", "Failed to save setting: " + (err.message || err));
      })
      .then(function () { el.classList.remove("opacity-75"); });
  }

  function populate(suffix, map, video) {
    var el = $id(P + suffix);
    if (!el) return;
    var v = video[map.key];
    if (v === undefined || v === null) return;
    if (map.type === "bool") el.checked = !!Number(v);
    else if (map.type === "codec") el.value = codecFromTimps(v);
    else if (map.type === "rc") el.value = rcFromTimps(v);
    else el.value = v;
  }

  function wireControls() {
    populateSelectors();
    Object.keys(FIELD_MAP).forEach(function (suffix) {
      var el = $id(P + suffix);
      if (!el) return;
      setEnabled(P + suffix, false); // enabled once timps answers
      el.addEventListener("change", function () { send(suffix, FIELD_MAP[suffix]); });
    });

    // "Audio in stream" has no per-stream key in timps (audio is global);
    // bind it to the global audio.enabled switch.
    var au = $id(P + "audio_enabled");
    if (au) {
      setEnabled(P + "audio_enabled", false);
      au.addEventListener("change", sendAudio);
    }

    var saveBtn = $id("save-prudynt-config");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        toast(
          "success",
          "Encoder settings are saved live to the streamer configuration; restart the streamer to apply them.",
          5000,
        );
      });
    }
  }

  function offlineNotice() {
    if ($id("timps-offline-notice")) return;
    var div = document.createElement("div");
    div.id = "timps-offline-notice";
    div.className = "alert alert-warning mt-2";
    div.innerHTML =
      '<i class="bi bi-exclamation-triangle me-1"></i>' +
      "The streamer is not reachable, encoder controls are disabled. " +
      "Check that the timps service is running, then reload this page.";
    var h3 = document.querySelector("main h3");
    if (h3 && h3.parentNode) h3.parentNode.insertBefore(div, h3.nextSibling);
    else {
      var c = document.querySelector("main .container");
      if (c) c.appendChild(div);
    }
  }

  function load() {
    if (!window.timpsApi) {
      console.error("timps-api.js not loaded");
      offlineNotice();
      return;
    }
    window.timpsApi
      .get()
      .then(function (json) {
        var video = (json.video && json.video[idx]) || {};
        var audio = json.audio || {};
        Object.keys(FIELD_MAP).forEach(function (suffix) {
          populate(suffix, FIELD_MAP[suffix], video);
          setEnabled(P + suffix, true);
        });
        var au = $id(P + "audio_enabled");
        if (au) {
          if (audio.enabled !== undefined) au.checked = !!Number(audio.enabled);
          setEnabled(P + "audio_enabled", true);
        }
        var offline = $id("timps-offline-notice");
        if (offline) offline.remove();
      })
      .catch(function (err) {
        console.warn("timps unreachable, encoder controls stay disabled:", err);
        offlineNotice();
      });
  }

  function init() {
    wireControls();
    load();
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
