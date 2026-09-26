// streamer-image.js - Image Quality page (cards with sliders).
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-image") return;

  // page field id -> timps image.* key (ids are prudynt-era names)
  var FIELD_MAP = {
    brightness: "brightness",
    contrast: "contrast",
    sharpness: "sharpness",
    saturation: "saturation",
    backlight: "backlight_compensation",
    wide_dynamic_range: "drc_strength",
    tone: "highlight_depress",
    defog: "defog_strength",
    noise_reduction: "sinter_strength", // set() also mirrors temper_strength
    image_core_wb_mode: "core_wb_mode",
    image_wb_bgain: "wb_bgain",
    image_wb_rgain: "wb_rgain",
    image_ae_compensation: "ae_compensation",
    image_hflip: "hflip",
    image_vflip: "vflip",
  };

  function $id(id) { return document.getElementById(id); }

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function")
      window.showAlert(type, message, ms);
    else console.log("[streamer-image]", type + ":", message);
  }

  var LABEL = {};
  var unsupported = {};

  // unsupported on this SoC: hidden and named under the preview
  function setEnabled(id, on) {
    var el = $id(id);
    if (!el) return;
    el.disabled = !on;
    var wrap = el.closest("[data-f]");
    if (wrap) wrap.classList.toggle("d-none", !on);
    if (on) delete unsupported[id]; else unsupported[id] = true;
  }

  function showValue(id) {
    var o = $id(id + "-v"), el = $id(id);
    if (o && el) o.textContent = el.value;
  }

  // RGB gains only act in manual/custom white balance
  function wbGate() {
    var mode = $id("image_core_wb_mode");
    var manual = mode && isManual(mode.value);
    ["image_wb_rgain", "image_wb_bgain"].forEach(function (id) {
      var w = $id(id) && $id(id).closest("[data-f]");
      if (w && !unsupported[id]) w.classList.toggle("d-none", !manual);
    });
    var note = $id("img-wb-note");
    if (note) note.textContent = manual || unsupported.image_wb_rgain ? "" :
      "Red/blue gain apply in Manual or Custom mode.";
  }

  function renderUnsupported() {
    var names = Object.keys(unsupported).map(function (id) { return LABEL[id] || id; });
    var el = $id("img-unsupported");
    if (el) el.textContent = names.length ? "Not supported on this camera: " + names.join(", ") + "." : "";
  }

  function populate(id, value) {
    var el = $id(id);
    if (!el || value === undefined || value === null) return;
    if (el.type === "checkbox") el.checked = !!Number(value);
    else el.value = value;
    showValue(id);
    if (id === "image_core_wb_mode") wbGate();
  }

  var REVERSE = {};
  Object.keys(FIELD_MAP).forEach(function (id) {
    REVERSE["image." + FIELD_MAP[id]] = id;
  });

  function applyCorrections(r) {
    var corr = r && r.corrections;
    if (!corr) return;
    // the single NR slider mirrors sinter -> temper; naming both in the toast
    // would report the same knob twice
    if (corr["image.temper_strength"] !== undefined &&
        corr["image.sinter_strength"] !== undefined)
      delete corr["image.temper_strength"];
    Object.keys(corr).forEach(function (k) {
      var id = REVERSE[k];
      if (id) populate(id, corr[k]);
    });
    // take-once: a debounced flush settles every queued waiter with the same
    // result; the element writes above are idempotent, the toast is not
    var t = window.timpsApi.takeCorrections(r);
    if (t) toast("info", window.timpsApi.correctionsText(t));
  }

  // one changed control -> debounced POST {"image":{key:val}} to timps.
  // The page's single NR slider drives both spatial+temporal NR strengths.
  function send(id) {
    var el = $id(id);
    var key = FIELD_MAP[id];
    if (!el || !key) return;
    var value;
    if (el.type === "checkbox") value = el.checked ? 1 : 0;
    else {
      value = parseInt(el.value, 10);
      if (isNaN(value)) return;
    }
    var image = {};
    image[key] = value;
    if (id === "noise_reduction") image.temper_strength = value;
    el.classList.add("opacity-75");
    window.timpsApi
      .setDebounced({ image: image }, 150)
      .then(applyCorrections, function (err) {
        console.error("timps set failed:", err);
        toast("danger", "Failed to apply setting: " + (err.message || err));
      })
      .then(function () {
        el.classList.remove("opacity-75");
      });
  }

  function isManual(v) { return v === "1" || v === "9"; }

  // entering manual/custom: start from the gains AWB applies now, so the picture doesn't jump
  function wbEnterManual(el) {
    el.classList.add("opacity-75");
    window.timpsApi.get().then(function (json) {
      var live = json.image && json.image.wb_live;
      var image = { core_wb_mode: parseInt(el.value, 10) };
      if (live) {
        image.wb_rgain = live.rgain;
        image.wb_bgain = live.bgain;
        populate("image_wb_rgain", live.rgain);
        populate("image_wb_bgain", live.bgain);
      }
      return window.timpsApi.set({ image: image });
    }).then(applyCorrections, function (err) {
      toast("danger", "Failed to apply setting: " + (err.message || err));
    }).then(function () { el.classList.remove("opacity-75"); });
  }

  function wireControls() {
    var wbPrev = null;
    Object.keys(FIELD_MAP).forEach(function (id) {
      var el = $id(id);
      if (!el) return;
      var lab = document.querySelector('label[for="' + id + '"]');
      LABEL[id] = lab ? lab.textContent.replace(/\s+\d*\s*$/, "").trim() : id;
      el.disabled = true; // until caps confirm support
      el.addEventListener("input", function () { showValue(id); });
      if (id === "image_core_wb_mode")
        el.addEventListener("focus", function () { wbPrev = el.value; });
      el.addEventListener("change", function () {
        if (id === "image_core_wb_mode") {
          var from = wbPrev;
          wbPrev = el.value;
          wbGate();
          if (isManual(el.value) && !isManual(from)) return wbEnterManual(el);
        }
        send(id);
      });
      // double-click resets a numeric field to the midpoint of its range
      if (el.type !== "checkbox" && el.tagName !== "SELECT") {
        el.addEventListener("dblclick", function () {
          var min = Number(el.min || 0);
          var max = Number(el.max || 255);
          el.value = Math.round((min + max) / 2);
          showValue(id);
          send(id);
        });
      }
    });
  }

  function offlineNotice() {
    if ($id("timps-offline-notice")) return;
    var div = document.createElement("div");
    div.id = "timps-offline-notice";
    div.className = "alert alert-warning mt-2";
    div.innerHTML =
      '<i class="bi bi-exclamation-triangle me-1"></i>' +
      "The streamer is not reachable, image controls are disabled. " +
      "Check that the timps service is running, then reload this page.";
    var h3 = document.querySelector("main h3");
    if (h3 && h3.parentNode) h3.parentNode.insertBefore(div, h3.nextSibling);
    else document.querySelector("main .container")?.appendChild(div);
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
        var image = json.image || {};
        var capsImage = (json.caps && json.caps.image) || [];
        Object.keys(FIELD_MAP).forEach(function (id) {
          var key = FIELD_MAP[id];
          populate(id, image[key]);
          setEnabled(id, capsImage.indexOf(key) >= 0);
        });
        renderUnsupported();
        wbGate();
      })
      .catch(function (err) {
        console.warn("timps unreachable, image controls stay disabled:", err);
        offlineNotice();
      });
  }

  var REVERSE = {};
  Object.keys(FIELD_MAP).forEach(function (id) {
    REVERSE["image." + FIELD_MAP[id]] = id;
  });
  REVERSE["image.temper_strength"] = "noise_reduction"; // after the loop: a
  // future FIELD_MAP entry literally named "temper_strength" must not win
  // over this intentional alias (mirrors send()'s special case).

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; } // this client lapped an eviction
    var id = REVERSE[data.key];
    if (!id) return;
    var el = $id(id);
    // don't fight the user mid-drag on this same page; the value will
    // land anyway once they let go and post their own change
    if (!el || document.activeElement === el) return;
    populate(id, data.value);
  }

  function initIq() {
    var c = $id("iq");
    if (!c || !window.timpsUi) return;
    window.timpsUi.uploadCard(c, "iq", "sensor IQ file");
    if (location.hash === "#iq") c.scrollIntoView();
  }

  function init() {
    wireControls();
    initIq();
    load();
    if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
