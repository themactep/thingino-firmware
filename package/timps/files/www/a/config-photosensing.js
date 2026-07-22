/* config-photosensing.js - timps day/night (photosensing) settings.
 *
 * Overlay replacing the stock thingino page script, which POSTed the gain
 * thresholds to /x/json-config-daynight.cgi (thingino.json) - a file the
 * timps streamer never reads, so the thresholds did nothing. This version
 * talks DIRECTLY to timps via GET/POST /control (a/timps-api.js):
 *   #daynight_enabled                     -> daynight.enabled
 *   #daynight_total_gain_night_threshold  -> daynight.total_gain_night_threshold
 *   #daynight_total_gain_day_threshold    -> daynight.total_gain_day_threshold
 * timps persists them into /etc/timps.conf itself and the detection thread
 * picks them up live (gain-based decision, prudynt scale: 256 = 1x gain,
 * lower gain = brighter = day).
 *
 * The Controls (color/ircut/IR850/IR940/white) and Time Schedule columns
 * configure the BOARD daynight script, not timps - they stay on the stock
 * /x/json-config-daynight.cgi backend, loaded and saved best-effort. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-photosensing") return;
  if (!window.timpsApi) {
    console.error("[photosensing] timps-api.js not loaded");
    return;
  }

  var LEGACY = "/x/json-config-daynight.cgi"; // board script config (controls/schedule)
  var CONTROLS = ["color", "ircut", "ir850", "ir940", "white"];
  var SCHEDULE = ["enabled", "start_at", "stop_at"];

  var $ = function (id) { return document.getElementById(id); };

  var reloadBtn = $("photosensing-reload");
  var saveBtn = $("save-prudynt-config");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[photosensing]", type + ":", msg);
  }

  /* ---- timps part: enabled + gain thresholds -------------------------- */

  function fillTimps(dn) {
    dn = dn || {};
    var en = $("daynight_enabled");
    if (en) en.checked = (dn.enabled === true || dn.enabled === 1);
    ["total_gain_night_threshold", "total_gain_day_threshold"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = dn[k];
      el.value = (v === null || typeof v === "undefined") ? "" : Math.round(v);
    });
  }

  function collectTimps() {
    var out = {};
    var en = $("daynight_enabled");
    if (en) out.enabled = !!en.checked;
    ["total_gain_night_threshold", "total_gain_day_threshold"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = parseInt(el.value, 10);
      if (!isNaN(v) && v >= 0) out[k] = v;
    });
    return out;
  }

  /* ---- legacy part: controls + schedule (board daynight script) ------- */

  function fillLegacy(dn) {
    dn = dn || {};
    if (dn.controls) CONTROLS.forEach(function (c) {
      var el = $("daynight_controls_" + c);
      if (el && Object.prototype.hasOwnProperty.call(dn.controls, c))
        el.checked = !!dn.controls[c];
    });
    if (dn.schedule) SCHEDULE.forEach(function (p) {
      var el = $("daynight_schedule_" + p);
      if (!el || !Object.prototype.hasOwnProperty.call(dn.schedule, p)) return;
      if (el.type === "checkbox") el.checked = !!dn.schedule[p];
      else el.value = dn.schedule[p] || "";
    });
  }

  function collectLegacy() {
    var controls = {}, schedule = {};
    CONTROLS.forEach(function (c) {
      var el = $("daynight_controls_" + c);
      if (el) controls[c] = !!el.checked;
    });
    SCHEDULE.forEach(function (p) {
      var el = $("daynight_schedule_" + p);
      if (!el) return;
      schedule[p] = (el.type === "checkbox") ? !!el.checked : (el.value || "");
    });
    return { controls: controls, schedule: schedule };
  }

  function loadLegacy() {
    return fetch(LEGACY, { cache: "no-store" })
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (data) { if (data) fillLegacy(data); })
      .catch(function () {
        console.warn("[photosensing] " + LEGACY + " unavailable - controls/schedule not loaded");
      });
  }

  function saveLegacy() {
    return fetch(LEGACY, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ daynight: collectLegacy() }),
    }).then(function (res) {
      if (!res.ok) throw new Error("HTTP " + res.status);
    });
  }

  /* ---- load / save ----------------------------------------------------- */

  function load() {
    if (reloadBtn) reloadBtn.disabled = true;
    var t = window.timpsApi.get().then(function (json) {
      fillTimps(json && json.daynight);
    }).catch(function (e) {
      toast("danger", "Unable to load timps day/night settings: " + (e.message || e));
    });
    Promise.allSettled([t, loadLegacy()]).then(function () {
      if (typeof window.attachSliderButtons === "function") window.attachSliderButtons();
      if (reloadBtn) reloadBtn.disabled = false;
    });
  }

  function save(ev) {
    if (ev) { ev.preventDefault(); ev.stopImmediatePropagation(); }
    if (saveBtn) saveBtn.disabled = true;
    window.timpsApi.set({ daynight: collectTimps() }).then(function () {
      // controls/schedule stay on the board-script backend; best-effort
      return saveLegacy().catch(function (e) {
        toast("warning", "Thresholds saved to timps.conf, but controls/schedule not saved (" +
          (e.message || e) + ").", 6000);
      });
    }).then(function () {
      toast("success", "Photosensing settings saved (thresholds live in timps.conf).", 4000);
      load();
    }).catch(function (e) {
      toast("danger", "Failed to save photosensing settings: " + (e.message || e));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  /* ---- live sync: another open tab/client changing enabled/thresholds ---- */

  var TIMPS_REVERSE = {
    "daynight.enabled": "daynight_enabled",
    "daynight.total_gain_night_threshold": "daynight_total_gain_night_threshold",
    "daynight.total_gain_day_threshold": "daynight_total_gain_day_threshold",
  };

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; }
    var id = TIMPS_REVERSE[data.key];
    if (!id) return;
    var el = $(id);
    // don't fight the user mid-edit on this same field
    if (!el || document.activeElement === el) return;
    if (id === "daynight_enabled") el.checked = (data.value === "1" || data.value === "true");
    else el.value = Math.round(Number(data.value));
  }

  if (saveBtn) saveBtn.addEventListener("click", save, { capture: true });
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  window.timpsApi.events("config", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
