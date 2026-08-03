/* config-photosensing.js - timps day/night (photosensing) settings.
 *
 * Overlay replacing the stock thingino page script, which POSTed the gain
 * thresholds to /x/json-config-daynight.cgi (thingino.json) - a file the
 * timps streamer never reads, so the thresholds did nothing. This version
 * talks DIRECTLY to timps via GET/POST /control (a/timps-api.js):
 *   #daynight_enabled                     -> daynight.enabled
 *   #daynight_total_gain_night_threshold  -> daynight.total_gain_night_threshold
 *   #daynight_total_gain_day_threshold    -> daynight.total_gain_day_threshold
 *   #daynight_day_gain_pct                -> daynight.day_gain_pct
 *   #daynight_baseline_delay_s            -> daynight.baseline_delay_s
 *   #daynight_night_reconfirm_s           -> daynight.night_reconfirm_s
 *   #daynight_boot_settle_s/_max_s        -> daynight.boot_settle_s/_max_s
 *   #daynight_boot_stable_pct             -> daynight.boot_stable_pct
 *   (read-only: #daynight_night_baseline/#daynight_day_trigger from the
 *    status fields of the same names - the adaptive trigger in effect)
 *   #daynight_mode                        -> daynight.mode (sensor/time/sun)
 *   #daynight_time_night_start/day_start  -> daynight.time_night_start/day_start
 *   #daynight_sun_latitude/longitude      -> daynight.sun_latitude/longitude
 *   #daynight_sun_sunrise/sunset_offset_min -> daynight.sun_sunrise/sunset_offset_min
 * timps persists them into /etc/timps.conf itself and the detection thread
 * picks them up live. The Override Mode selector chooses the decision source:
 * sensor (gain-based, default), a fixed local-clock window, or today's real
 * sunrise/sunset for a lat/long. All three are timps-native.
 *
 * The Controls (color/ircut/IR850/IR940/white) column is a SEPARATE feature:
 * it configures the BOARD daynight script (/sbin/daynight hardware toggles),
 * not timps, and legitimately stays on the stock /x/json-config-daynight.cgi
 * backend, loaded and saved best-effort. (The old "Time Schedule" column that
 * also lived on that cgi was dead orphaned config nothing read - it has been
 * replaced by the timps-native Override Mode above.) */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-photosensing") return;
  if (!window.timpsApi) {
    console.error("[photosensing] timps-api.js not loaded");
    return;
  }

  var LEGACY = "/x/json-config-daynight.cgi"; // board script config (controls only)
  var CONTROLS = ["color", "ircut", "ir850", "ir940", "white"];

  var $ = function (id) { return document.getElementById(id); };

  var reloadBtn = $("photosensing-reload");
  var saveBtn = $("save-prudynt-config");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[photosensing]", type + ":", msg);
  }

  /* ---- mode UI: show only the selected sub-fields ---------------------- */

  function syncModeUI() {
    var sel = $("daynight_mode");
    var mode = sel ? sel.value : "sensor";
    var timeF = $("daynight_time_fields");
    var sunF = $("daynight_sun_fields");
    if (timeF) timeF.hidden = (mode !== "time");
    if (sunF) sunF.hidden = (mode !== "sun");
  }

  /* ---- timps part: enabled + gain thresholds + override mode ---------- */

  var NUM_FIELDS = [
    "total_gain_night_threshold", "total_gain_day_threshold",
    "sun_latitude", "sun_longitude",
    "sun_sunrise_offset_min", "sun_sunset_offset_min",
  ];
  var STR_FIELDS = ["time_night_start", "time_day_start"];

  function fillTimps(dn) {
    dn = dn || {};
    var en = $("daynight_enabled");
    if (en) en.checked = (dn.enabled === true || dn.enabled === 1);

    var mode = $("daynight_mode");
    if (mode && typeof dn.dn_mode === "string") mode.value = dn.dn_mode;

    // gain thresholds + adaptive/boot tunables are rounded ints; the rest
    // keep their given value
    ["total_gain_night_threshold", "total_gain_day_threshold",
     "day_gain_pct", "baseline_delay_s", "night_reconfirm_s",
     "boot_settle_s", "boot_settle_max_s", "boot_stable_pct"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = dn[k];
      el.value = (v === null || typeof v === "undefined") ? "" : Math.round(v);
    });

    // read-only adaptive-baseline feedback (only meaningful in night mode;
    // timps reports -1 when none is in effect)
    var nb = $("daynight_night_baseline");
    var dt = $("daynight_day_trigger");
    if (nb) nb.textContent = (typeof dn.night_baseline === "number" && dn.night_baseline >= 0)
      ? Math.round(dn.night_baseline) : "-";
    if (dt) dt.textContent = (typeof dn.day_trigger === "number" && dn.day_trigger >= 0)
      ? Math.round(dn.day_trigger) : "-";
    ["sun_latitude", "sun_longitude",
     "sun_sunrise_offset_min", "sun_sunset_offset_min"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = dn[k];
      el.value = (v === null || typeof v === "undefined") ? "" : v;
    });
    STR_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (el) el.value = dn[k] || "";
    });

    // read-only computed sunrise/sunset feedback for the sun mode
    var sr = $("daynight_sun_computed_sunrise");
    var ss = $("daynight_sun_computed_sunset");
    if (sr) sr.textContent = dn.sun_computed_sunrise || "--:--";
    if (ss) ss.textContent = dn.sun_computed_sunset || "--:--";

    syncModeUI();
  }

  function collectTimps() {
    var out = {};
    var en = $("daynight_enabled");
    if (en) out.enabled = !!en.checked;

    var mode = $("daynight_mode");
    if (mode) out.mode = mode.value;

    ["total_gain_night_threshold", "total_gain_day_threshold",
     "day_gain_pct", "baseline_delay_s", "night_reconfirm_s",
     "boot_settle_s", "boot_settle_max_s", "boot_stable_pct"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = parseInt(el.value, 10);
      if (!isNaN(v) && v >= 0) out[k] = v;
    });
    ["sun_latitude", "sun_longitude"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el || el.value === "") return;
      var v = parseFloat(el.value);
      if (!isNaN(v)) out[k] = v;
    });
    ["sun_sunrise_offset_min", "sun_sunset_offset_min"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el || el.value === "") return;
      var v = parseInt(el.value, 10);      // negatives allowed
      if (!isNaN(v)) out[k] = v;
    });
    STR_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (el && el.value) out[k] = el.value;   // "HH:MM"
    });
    return out;
  }

  /* ---- legacy part: controls only (board daynight script) ------------- */

  function fillLegacy(dn) {
    dn = dn || {};
    if (dn.controls) CONTROLS.forEach(function (c) {
      var el = $("daynight_controls_" + c);
      if (el && Object.prototype.hasOwnProperty.call(dn.controls, c))
        el.checked = !!dn.controls[c];
    });
  }

  function collectLegacy() {
    var controls = {};
    CONTROLS.forEach(function (c) {
      var el = $("daynight_controls_" + c);
      if (el) controls[c] = !!el.checked;
    });
    return { controls: controls };
  }

  function loadLegacy() {
    return fetch(LEGACY, { cache: "no-store" })
      .then(function (res) { return res.ok ? res.json() : null; })
      .then(function (data) { if (data) fillLegacy(data); })
      .catch(function () {
        console.warn("[photosensing] " + LEGACY + " unavailable - controls not loaded");
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
      // controls stay on the board-script backend; best-effort
      return saveLegacy().catch(function (e) {
        toast("warning", "Photosensing saved to timps.conf, but controls not saved (" +
          (e.message || e) + ").", 6000);
      });
    }).then(function () {
      toast("success", "Photosensing settings saved (live in timps.conf).", 4000);
      load();
    }).catch(function (e) {
      toast("danger", "Failed to save photosensing settings: " + (e.message || e));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  /* ---- live sync: another open tab/client changing a timps field ------- */

  var TIMPS_REVERSE = {
    "daynight.enabled": "daynight_enabled",
    "daynight.mode": "daynight_mode",
    "daynight.total_gain_night_threshold": "daynight_total_gain_night_threshold",
    "daynight.total_gain_day_threshold": "daynight_total_gain_day_threshold",
    "daynight.time_night_start": "daynight_time_night_start",
    "daynight.time_day_start": "daynight_time_day_start",
    "daynight.sun_latitude": "daynight_sun_latitude",
    "daynight.sun_longitude": "daynight_sun_longitude",
    "daynight.sun_sunrise_offset_min": "daynight_sun_sunrise_offset_min",
    "daynight.sun_sunset_offset_min": "daynight_sun_sunset_offset_min",
  };

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; }
    var id = TIMPS_REVERSE[data.key];
    if (!id) return;
    var el = $(id);
    // don't fight the user mid-edit on this same field
    if (!el || document.activeElement === el) return;
    if (id === "daynight_enabled") {
      el.checked = (data.value === "1" || data.value === "true");
    } else if (id === "daynight_mode") {
      el.value = data.value;
      syncModeUI();
    } else if (data.key.indexOf("threshold") !== -1) {
      el.value = Math.round(Number(data.value));
    } else {
      el.value = data.value;   // times ("HH:MM"), lat/long, offsets
    }
  }

  if (saveBtn) saveBtn.addEventListener("click", save, { capture: true });
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  var modeSel = $("daynight_mode");
  if (modeSel) modeSel.addEventListener("change", syncModeUI);
  window.timpsApi.events("config", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
