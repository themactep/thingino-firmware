/* streamer-image.js - NATIVE Image Quality page. Talks directly to the timps
 * streamer over window.timpsApi (GET/POST /control on timps's own port, per-
 * boot token) - no json-imaging.cgi / json-prudynt*.cgi bridge for this page.
 *
 * Load:  timpsApi.get() -> populate every control from the "image" object and
 *        enable ONLY the controls whose timps key is listed in caps.image
 *        (the SoC capability matrix); everything else stays greyed out.
 * Save:  every change goes straight to timpsApi.set({image:{key:val}}) -
 *        debounced, so a burst of quick changes coalesces into one POST.
 *        timps applies live AND persists to its config file immediately, so
 *        the "Save configuration" button is just a confirmation toast.
 * Offline: if timps is unreachable the controls stay disabled and a small
 *        notice appears; nothing throws.
 */
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

  // same disabled styling the page always used: input.disabled + a
  // "disabled" class on the wrapping <p>/.select/.boolean block
  function setEnabled(id, on) {
    var el = $id(id);
    if (!el) return;
    el.disabled = !on;
    var wrap =
      el.closest("p, .number-range, .select, .boolean, .col") ||
      el.parentElement;
    if (wrap) wrap.classList.toggle("disabled", !on);
  }

  function populate(id, value) {
    var el = $id(id);
    if (!el || value === undefined || value === null) return;
    if (el.type === "checkbox") el.checked = !!Number(value);
    else el.value = value;
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
      .catch(function (err) {
        console.error("timps set failed:", err);
        toast("danger", "Failed to apply setting: " + (err.message || err));
      })
      .then(function () {
        el.classList.remove("opacity-75");
      });
  }

  function wireControls() {
    Object.keys(FIELD_MAP).forEach(function (id) {
      var el = $id(id);
      if (!el) return;
      setEnabled(id, false); // disabled until caps confirm support
      el.addEventListener("change", function () { send(id); });
      // double-click resets a numeric field to the midpoint of its range
      if (el.type !== "checkbox" && el.tagName !== "SELECT") {
        el.addEventListener("dblclick", function () {
          var min = Number(el.dataset.min || 0);
          var max = Number(el.dataset.max || 255);
          el.value = Math.round((min + max) / 2);
          send(id);
        });
      }
    });

    // timps applies + persists every change immediately; the button is
    // kept only to reassure users trained on the old save-to-file step.
    var saveBtn = $id("save-prudynt-config");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        toast(
          "success",
          "Nothing to do: image settings are applied live and already saved to the streamer configuration.",
          4000,
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
      })
      .catch(function (err) {
        console.warn("timps unreachable, image controls stay disabled:", err);
        offlineNotice();
      });
  }

  // reverse of FIELD_MAP (timps "image.<key>" -> page field id), so another
  // open tab/client changing a setting (e.g. brightness) via /control shows
  // up here live instead of only on next reload. temper_strength mirrors
  // send()'s noise_reduction special case (one slider, two backend keys).
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

  function init() {
    wireControls();
    load();
    if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
