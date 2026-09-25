// config-photosensing.js - timps day/night (photosensing) settings.
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-photosensing") return;
  if (!window.timpsApi) {
    console.error("[photosensing] timps-api.js not loaded");
    return;
  }

  var LEGACY = "/x/timps-dn-controls.cgi"; // daynight.controls for /usr/sbin/daynight
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

  // every way this column can be saved into a no-op.
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
      onNow(json && json.daynight);
      durHints();
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
      var corr = r && r.corrections;
      if (corr) Object.keys(corr).forEach(function (k) {
        applyTimpsKV(k, corr[k]);
      });
      corr = window.timpsApi.takeCorrections(r);
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

  /* ---- "Now" box: mode, gain against both limits, what comes next ------ */

  var now = {};
  function drawNow() {
    var d = now, night = Number(d.mode) === 1, g = Number(d.total_gain);
    var lo = Number(d.day_gain), hi = Number(d.night_gain);
    $("dn-icon").className = night ? "bi bi-moon-stars" : "bi bi-sun";
    $("dn-now").textContent = d.mode === undefined ? "–" : night ? "Night" : "Day";
    var auto = d.dn_mode !== "schedule";
    $("dn-src").textContent = !(d.enabled === 1 || d.enabled === true) ? "automatic switching off"
      : auto ? "auto · light level" : "auto · calendar";
    var sc = $("dn-scale"), mk = $("dn-mark");
    if (lo > 0 && hi > lo) {
      var span = Math.max(hi * 2, g * 1.05 || 0), p = function (v) { return (v / span * 100).toFixed(2) + "%"; };
      sc.style.background = "linear-gradient(90deg,#f0c040 0 " + p(lo) + ",#555 " + p(lo) + " " + p(hi) + ",#3a5fcd " + p(hi) + ")";
      sc.querySelectorAll(".tk,.lb").forEach(function (e) { e.remove(); });
      sc.insertAdjacentHTML("beforeend",
        '<span class="lb" style="left:' + p(lo / 2) + ';color:#f0c040">Day</span>' +
        '<span class="lb" style="left:' + p((lo + hi) / 2) + '">hysteresis</span>' +
        '<span class="lb" style="left:' + p((hi + span) / 2) + ';color:#7b9cff">Night</span>' +
        '<span class="tk" style="left:' + p(lo) + '">' + lo + '</span><span class="tk" style="left:' + p(hi) + '">' + hi + "</span>");
      if (g >= 0) { mk.style.left = p(Math.min(g, span)); mk.hidden = false; }
    }
    var next = "";
    if (!auto) next = "the calendar decides";
    else if (night && d.day_trigger > 0) next = "probe for day when gain <b>&lt; " + Math.round(d.day_trigger) + "</b>";
    else if (night) next = "day when gain <b>&lt; " + lo + "</b>";
    else if (hi > 0) next = "night when gain <b>&gt; " + hi + "</b>" + (d.day_confirm_s ? " for " + d.day_confirm_s + " s" : "");
    $("dn-next").innerHTML = (next ? "next: " + next : "") + (g >= 0 ? "<br>gain now " + Math.round(g) : "");
  }
  function onNow(d) {
    if (!d) return;
    Object.keys(d).forEach(function (k) { now[k] = d[k]; });
    drawNow();
  }

  // hour/minute reading next to the second-valued fields
  function durHints() {
    ["heartbeat_s", "heartbeat_max_s", "probe_min_gap_s"].forEach(function (k) {
      var el = $("daynight_" + k), lab = el && document.querySelector('label[for="daynight_' + k + '"]');
      if (!lab) return;
      var h = lab.querySelector(".dur") || lab.appendChild(Object.assign(document.createElement("span"), { className: "dur ms-1 text-body-secondary" }));
      var v = parseInt(el.value, 10);
      h.textContent = v >= 3600 ? "≈ " + +(v / 3600).toFixed(1) + " h" : v >= 60 ? "≈ " + Math.round(v / 60) + " min" : "";
    });
  }
  document.addEventListener("input", function (e) { if (/daynight_(heartbeat|probe_min_gap)/.test(e.target.id)) durHints(); });

  function onConfigEvent(type, data) {
    if (type === "daynight") { onNow(data); return; }
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
  window.timpsApi.events("config,daynight", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
