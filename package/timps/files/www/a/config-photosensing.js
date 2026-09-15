/* config-photosensing.js - timps day/night (photosensing) settings.
 *
 * Overlay replacing the stock thingino page script, which POSTed the gain
 * thresholds to /x/json-config-daynight.cgi (thingino.json) - a file the
 * timps streamer never reads, so the thresholds did nothing. This version
 * talks DIRECTLY to timps via GET/POST /control (a/timps-api.js); fields
 * follow the "daynight_<key>" -> "daynight.<key>" convention (see
 * fillTimps()/collectTimps() below). The Decision source column mirrors the
 * daemon's two independent axes: daynight.mode (auto = light level, schedule
 * = the calendar decides outright) and WHICH calendar is stored, which timps
 * derives from the values rather than from a field of its own.
 *
 * The Controls (color/ircut/IR850/IR940/white) column is a SEPARATE feature:
 * it configures the BOARD daynight script (/sbin/daynight hardware toggles),
 * not timps, and legitimately stays on the stock /x/json-config-daynight.cgi
 * backend, loaded and saved best-effort. */
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

  /* ---- calendar UI: show only the selected calendar's sub-fields ------- */

  function calValue() {
    var el = $("daynight_calendar");
    return el ? el.value : "none";
  }

  // mirrors dn_cal_kind() in daynight.c: a COMPLETE time window outranks
  // lat/long, and 0/0 is "no location". timps has no field saying which
  // calendar was meant, so the page has to derive it the daemon's way -
  // anything else lets the selector show a calendar that isn't running.
  function calFromValues(night, day, lat, lon) {
    if (night && day) return "time";
    if (Number(lat) || Number(lon)) return "sun";
    return "none";
  }

  function syncCalendarUI() {
    var cal = calValue();
    var timeF = $("daynight_time_fields");
    var sunF = $("daynight_sun_fields");
    if (timeF) timeF.hidden = (cal !== "time");
    if (sunF) sunF.hidden = (cal !== "sun");
  }

  // every way this column can be saved into a no-op. The daemon reads its
  // calendar out of the values, so a half-filled one is simply no calendar
  // (daynight.c: "mode=schedule but no usable calendar - forcing nothing").
  function calendarProblem() {
    var cal = calValue();
    var mode = $("daynight_mode");
    var n = $("daynight_time_night_start"), d = $("daynight_time_day_start");
    var la = $("daynight_sun_latitude"), lo = $("daynight_sun_longitude");
    if (cal === "time" && !(n && d && n.value && d.value))
      return "A fixed time window needs both a night and a day time.";
    if (cal === "sun" && !(la && lo && (parseFloat(la.value) || parseFloat(lo.value))))
      return "Sunrise / sunset needs a latitude and a longitude.";
    if (mode && mode.value === "schedule" && cal === "none")
      return "Deciding by the calendar alone needs a calendar - pick a fixed " +
             "time window or sunrise / sunset.";
    return null;
  }

  /* ---- timps part: enabled + gain thresholds + decision source -------- */

  var INT_FIELDS = [
    "total_gain_night_threshold", "total_gain_day_threshold",
    "day_confirm_s", "probe_confirm_s", "probe_min_gap_s",
    "heartbeat_s", "heartbeat_max_s", "interval_ms",
  ];
  var STR_FIELDS = ["time_night_start", "time_day_start"];
  var BOOL_FIELDS = ["boot_probe", "diagnose_thresholds"];
  // constants since the 2026-08-22 consolidation (see the DN_* block in
  // daynight.h) - reported by timps, shown, not settable
  var FIXED_FIELDS = ["probe_jump_pct", "ref_delay_s", "boot_settle_s"];

  function fillTimps(dn) {
    dn = dn || {};
    var en = $("daynight_enabled");
    if (en) en.checked = (dn.enabled === true || dn.enabled === 1);
    BOOL_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (el) el.checked = (dn[k] === true || dn[k] === 1);
    });

    var mode = $("daynight_mode");
    if (mode && typeof dn.dn_mode === "string") mode.value = dn.dn_mode;
    var cal = $("daynight_calendar");
    if (cal) cal.value = calFromValues(dn.time_night_start, dn.time_day_start,
                                       dn.sun_latitude, dn.sun_longitude);

    INT_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = dn[k];
      el.value = (v === null || typeof v === "undefined") ? "" : Math.round(v);
    });
    FIXED_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (el) el.textContent = (typeof dn[k] === "number") ? Math.round(dn[k]) : "-";
    });

    // read-only night-reference feedback (only meaningful in night mode;
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

    syncCalendarUI();
  }

  function collectTimps() {
    var out = {};
    var en = $("daynight_enabled");
    if (en) out.enabled = !!en.checked;

    BOOL_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (el) out[k] = el.checked ? 1 : 0;
    });

    var mode = $("daynight_mode");
    if (mode) out.mode = mode.value;

    INT_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = parseInt(el.value, 10);
      if (!isNaN(v) && v >= 0) out[k] = v;
    });

    // The unselected calendar is always CLEARED, never just left alone: timps
    // picks its calendar from the values (calFromValues above), so a time
    // window left over from an earlier configuration would keep outranking a
    // location the user just typed in, and the save would report success.
    var cal = calValue();
    var num = function (id) {
      var el = $(id);
      var v = el ? parseFloat(el.value) : NaN;
      return isNaN(v) ? 0 : v;
    };
    if (cal === "time") {
      STR_FIELDS.forEach(function (k) {
        var el = $("daynight_" + k);
        out[k] = el ? el.value : "";         // "HH:MM"
      });
      out.sun_latitude = 0;
      out.sun_longitude = 0;
    } else {
      out.time_night_start = "";
      out.time_day_start = "";
      out.sun_latitude = (cal === "sun") ? num("daynight_sun_latitude") : 0;
      out.sun_longitude = (cal === "sun") ? num("daynight_sun_longitude") : 0;
    }
    ["sun_sunrise_offset_min", "sun_sunset_offset_min"].forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el || el.value === "") return;
      var v = parseInt(el.value, 10);      // negatives allowed
      if (!isNaN(v)) out[k] = v;
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
    var problem = calendarProblem();
    if (problem) { toast("danger", problem, 6000); return; }
    if (saveBtn) saveBtn.disabled = true;
    window.timpsApi.set({ daynight: collectTimps() }).then(function (r) {
      // controls stay on the board-script backend; best-effort
      return saveLegacy().catch(function (e) {
        toast("warning", "Photosensing saved to timps.conf, but controls not saved (" +
          (e.message || e) + ").", 6000);
      }).then(function () { return r; });
    }).then(function (r) {
      // corrected (clamped) values go straight back into their fields from
      // the "applied" echo; load() still runs for the computed/adaptive
      // read-only feedback and the legacy half, but the user need not wait
      // for it to see what really got stored
      var corr = r && r.corrections;
      if (corr) Object.keys(corr).forEach(function (k) {
        applyTimpsKV(k, corr[k]);
      });
      corr = window.timpsApi.takeCorrections(r);
      // a 200 can still carry rejected>0: the daemon refused SOME value
      // (empty/invalid) while applying the rest - a plain "saved" would lie
      // about those; the reload below shows what it actually kept
      if (r && r.rejected > 0)
        toast("warning", "Saved, but the streamer refused " + r.rejected +
          " value(s) (empty or invalid).", 6000);
      else if (corr)
        toast("info", "Saved. " + window.timpsApi.correctionsText(corr) + ".", 6000);
      else
        toast("success", "Photosensing settings saved (live in timps.conf).", 4000);
      load();
    }).catch(function (e) {
      toast("danger", "Failed to save photosensing settings: " + (e.message || e));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  /* ---- live sync: another open tab/client changing a timps field ------- */

  // config.c echoes SSE/GET under the canonical day_gain/night_gain name, not
  // the pre-2026-08-17 alias this page's two threshold fields still use.
  // Everything else follows the "daynight_<key>" id convention.
  var TIMPS_REVERSE = {
    "daynight.night_gain": "daynight_total_gain_night_threshold",
    "daynight.day_gain": "daynight_total_gain_day_threshold",
  };

  var CAL_KEYS = ["daynight.time_night_start", "daynight.time_day_start",
                  "daynight.sun_latitude", "daynight.sun_longitude"];

  // the section guard matters: without it a key like "record.enabled" would
  // fall back onto "daynight_enabled"
  function fieldId(key) {
    if (key.indexOf("daynight.") !== 0) return null;
    return TIMPS_REVERSE[key] || "daynight_" + key.slice(9);
  }

  // write one "daynight.<key>" value into its field - shared by the config-
  // sync push and the save-time "applied" corrections, so a clamped value
  // renders exactly like a remote edit.
  function applyTimpsKV(key, value) {
    var id = fieldId(key);
    var el = id ? $(id) : null;
    if (!el) return;
    if (el.type === "checkbox") {
      el.checked = (value === "1" || value === "true");
    } else if (id.indexOf("threshold") !== -1) {
      el.value = Math.round(Number(value));
    } else {
      el.value = value;   // mode, times ("HH:MM"), lat/long, offsets, s/ms ints
    }
    // a remote change to any of the four calendar values can change which
    // calendar timps will actually use, so re-derive the selector with them
    if (CAL_KEYS.indexOf(key) !== -1) {
      var cal = $("daynight_calendar");
      if (cal && document.activeElement !== cal) {
        cal.value = calFromValues($("daynight_time_night_start").value,
                                  $("daynight_time_day_start").value,
                                  $("daynight_sun_latitude").value,
                                  $("daynight_sun_longitude").value);
        syncCalendarUI();
      }
    }
  }

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; }
    var id = fieldId(data.key);
    var el = id ? $(id) : null;
    // don't fight the user mid-edit on this same field
    if (!el || document.activeElement === el) return;
    applyTimpsKV(data.key, data.value);
  }

  if (saveBtn) saveBtn.addEventListener("click", save, { capture: true });
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  var calSel = $("daynight_calendar");
  if (calSel) calSel.addEventListener("change", syncCalendarUI);
  window.timpsApi.events("config", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
