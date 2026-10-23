(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-photosensing") return;
  if (!window.timpsApi) {
    console.error("[photosensing] timps-api.js not loaded");
    return;
  }

  var LEGACY = "/x/timps-dn-controls.cgi";
  var CONTROLS = ["color", "ircut", "ir850", "ir940", "white"];

  var $ = function (id) { return document.getElementById(id); };

  var reloadBtn = $("photosensing-reload");
  var saveBtn = $("save-prudynt-config");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[photosensing]", type + ":", msg);
  }

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

  var INT_FIELDS = [
    "total_gain_night_threshold", "total_gain_day_threshold",
    "day_confirm_s", "jump_pct", "color_pct",
    "heartbeat_s", "heartbeat_max_s", "interval_ms",
  ];
  var STR_FIELDS = ["time_night_start", "time_day_start"];
  var reported = {};

  function lookEngine(dn) { return !!dn && typeof dn.jump_pct === "number"; }

  function fillTimps(dn) {
    dn = dn || {};
    var en = $("daynight_enabled");
    if (en) en.checked = (dn.enabled === true || dn.enabled === 1);

    var io = $("daynight_ir_idle_off");
    if (io) io.checked = Number(dn.ir_idle_off) === 1;
    var il = $("daynight_ir_idle_linger_s");
    if (il && typeof dn.ir_idle_linger_s === "number") il.value = dn.ir_idle_linger_s;

    var mode = $("daynight_mode");
    if (mode && typeof dn.dn_mode === "string") mode.value = dn.dn_mode;
    var cal = $("daynight_calendar");
    if (cal) cal.value = calFromValues(dn.time_night_start, dn.time_day_start,
                                       dn.sun_latitude, dn.sun_longitude);

    reported = {};
    INT_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el) return;
      var v = dn[k];
      if (typeof v === "number") reported[k] = true;
      el.value = (v === null || typeof v === "undefined") ? "" : Math.round(v);
    });
    var jr = $("dn-jump-row");
    if (jr) jr.hidden = !reported.jump_pct;
    var cr = $("dn-color-row");
    if (cr) cr.hidden = !reported.color_pct;
    var ch = $("dn-color-help");
    if (ch && dn.color_trigger === "unavailable")
      ch.textContent = "This camera's ISP gives no colour statistics: the setting has no effect here.";
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

    var mode = $("daynight_mode");
    if (mode) out.mode = mode.value;

    if (idleShown) {
      var io = $("daynight_ir_idle_off");
      if (io) out.ir_idle_off = io.checked ? 1 : 0;
      var lv = parseInt(($("daynight_ir_idle_linger_s") || {}).value, 10);
      if (!isNaN(lv) && lv >= 0) out.ir_idle_linger_s = lv;
    }

    INT_FIELDS.forEach(function (k) {
      var el = $("daynight_" + k);
      if (!el || !reported[k]) return;
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
        out[k] = el ? el.value : "";
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
      var v = parseInt(el.value, 10);
      if (!isNaN(v)) out[k] = v;
    });
    return out;
  }

  // pure: timps scripts/test_webui_idle.js extracts it by name
  function idleView(dn, caps, ageS) {
    var ii = dn && dn.ir_idle;
    if (!ii || typeof ii !== "object") return null;
    var cfg = Number(ii.cfg) === 1;
    var cd = caps && caps.daynight;
    if (cd && !Number(cd.ir_idle) && !cfg) return null;
    var R = {
      disabled: ["switching off", "Needs “Enable photosensing on boot” (daynight.enabled)."],
      schedule: ["calendar mode", "Works only when “Decided by” is “Light level” (daynight.mode = auto)."],
      keepalive: ["no keepalive", "Needs general.fs_keepalive (auto on T23/T41 with OpenIMP). Elsewhere set general.fs_keepalive = 1 in /etc/timps.conf and restart timps (untested there)."],
      no_illuminator: ["no switchable IR light", "daynight.irprobe_cmd is empty, or the IR light failed to switch twice and is retired until timps restarts. Check that IR 850/940 nm is ticked under “On switch, toggle”."],
      white_light: ["white light in the set", "Untick “White light” under “On switch, toggle”: it would light every reading while idle."],
      hook: ["IR hook not usable", "timps-irprobe has no “idle” verb (firmware older than 2026-10), has nothing to switch, or failed twice. Update the firmware or check the log; turning this off and on retries."],
    };
    if (!cfg) return { chip: "off", cls: "secondary", why: "The IR light follows day and night as usual." };
    if (!Number(ii.available)) {
      var r = R[ii.reason] || [ii.reason || "unknown", "See the timps log."];
      return { chip: "not available: " + r[0], cls: "warning", why: r[1] };
    }
    if (Number(ii.dark))
      return { chip: "IR off (idle)", cls: "primary",
               why: typeof dn.jump_pct === "number"
                 ? "Nobody is watching. The camera keeps reading the scene without the IR light; if it stays bright enough for 30 s it tries the day picture. The next viewer gets the IR light at once."
                 : "Nobody is watching. The next viewer gets the IR light at once, or day if the scene is bright enough without it." };
    if (Number(dn.mode) !== 1)
      return { chip: "ready (day)", cls: "success", why: "Acts at night only; by day the IR light is off anyway." };
    if (Number(ii.watched))
      return { chip: "IR on · watched", cls: "info",
               why: "A stream, snapshot, recording or motion detection is using the camera." };
    var left = Math.ceil(Number(ii.linger_left_s) - (Number(ageS) || 0));
    if (left > 0)
      return { chip: "IR on · off in " + left + " s", cls: "info", why: "Nobody is watching; the linger is running.", countdown: true };
    return { chip: "IR on · going dark", cls: "info",
             why: typeof dn.jump_pct === "number"
               ? "Nobody is watching; the light goes off at the next quiet moment (not during a look, a day check or right after a switch). If it stays on, look for “idle” warnings in the log."
               : "Nobody is watching; the light goes off at the next quiet moment (not during a probe or right after a switch). If it stays on, look for “exposure did not move” in the log." };
  }

  var caps = null, idleShown = false, idleAt = 0, idleTimer = null;

  function drawIdle() {
    var v = idleView(now, caps, (Date.now() - idleAt) / 1000);
    var card = $("dn-idle-card");
    idleShown = !!v;
    if (card) card.hidden = !v;
    clearTimeout(idleTimer);
    if (!v) return;
    var chip = $("dn-idle-chip");
    chip.textContent = v.chip;
    chip.className = "ms-auto badge rounded-pill fw-normal text-wrap text-end text-bg-" + v.cls;
    $("dn-idle-why").textContent = v.why;
    if (v.countdown) idleTimer = setTimeout(drawIdle, 1000);
  }

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

  function load() {
    if (reloadBtn) reloadBtn.disabled = true;
    var t = window.timpsApi.get().then(function (json) {
      caps = (json && json.caps) || null;
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
      var errs = r && r.errors && window.timpsErrors ? window.timpsErrors.list(r.errors) : [];
      if (errs.length)
        toast("warning", "Saved, but: " + errs.join(". ") + ".", 8000);
      else if (r && r.rejected > 0)
        toast("warning", "Saved, but the streamer refused " + r.rejected +
          " value(s) (empty or invalid).", 6000);
      else if (corr)
        toast("info", "Saved. " + window.timpsApi.correctionsText(corr) + ".", 6000);
      else
        toast("success", "Photosensing settings saved (live in timps.conf).", 4000);
      load();
    }).catch(function (e) {
      var errs = e && e.result && e.result.errors;
      toast("danger", "Failed to save photosensing settings: " + (errs && window.timpsErrors
        ? window.timpsErrors.list(errs).join(". ") : (e.message || e)));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  var TIMPS_REVERSE = {
    "daynight.night_gain": "daynight_total_gain_night_threshold",
    "daynight.day_gain": "daynight_total_gain_day_threshold",
  };

  var CAL_KEYS = ["daynight.time_night_start", "daynight.time_day_start",
                  "daynight.sun_latitude", "daynight.sun_longitude"];

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
      el.value = value;
    }
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

  var now = {};
  function drawNow() {
    var d = now, night = Number(d.mode) === 1;
    var g = Number(d.exposure) >= 0 ? Number(d.exposure) : Number(d.total_gain);
    var lo = Number(d.day_gain), hi = Number(d.night_gain);
    $("dn-icon").className = night ? "bi bi-moon-stars" : "bi bi-sun";
    $("dn-now").textContent = d.mode === undefined ? "–" : night ? "Night" : "Day";
    var auto = d.dn_mode !== "schedule";
    $("dn-src").textContent = !(d.enabled === 1 || d.enabled === true) ? "automatic switching off"
      : auto ? "auto · light level" : "auto · calendar";
    var sc = $("dn-scale"), mk = $("dn-mark");
    sc.querySelectorAll(".tk,.lb").forEach(function (e) { e.remove(); });
    mk.style.opacity = "";
    var ns = night ? nightScale(d) : null;
    if (ns) {
      var bar = ns.bar, ref = ns.ref;
      var span = Math.max(bar > 0 ? bar * 2 : 0, ref > 0 ? ref * 1.3 : 0,
                          ref > 0 ? Math.min(g * 1.05 || 0, ref * 2.5) : g * 1.05 || 0, 1),
          p = function (v) { return (v / span * 100).toFixed(2) + "%"; };
      if (bar > 0) {
        sc.style.background = "linear-gradient(90deg,#f0c040 0 " + p(bar) + ",#3a5fcd " + p(bar) + ")";
        sc.insertAdjacentHTML("beforeend",
          '<span class="lb" style="left:' + p(bar / 2) + ';color:#f0c040">' + ns.barName + '</span>' +
          '<span class="lb" style="left:' + p((bar + span) / 2) + ';color:#7b9cff">Night</span>' +
          '<span class="tk" style="left:' + p(bar) + '">' + Math.round(bar) + "</span>" +
          (ref > 0 && (ref - bar) / span > 0.25 ? '<span class="tk" style="left:' + p(ref) + '">' + ns.refName + " " + Math.round(ref) + "</span>" : ""));
      } else {
        sc.style.background = "#3a5fcd";
        sc.insertAdjacentHTML("beforeend",
          '<span class="lb" style="left:50%;color:#7b9cff">Night · ' + ns.pending + '</span>');
        mk.style.opacity = ".4";
      }
      if (g >= 0) { mk.style.left = p(Math.min(g, span)); mk.hidden = false; }
    } else if (lo > 0 && hi > lo) {
      var span2 = Math.max(hi * 2, g * 1.05 || 0), q = function (v) { return (v / span2 * 100).toFixed(2) + "%"; };
      sc.style.background = "linear-gradient(90deg,#f0c040 0 " + q(lo) + ",#555 " + q(lo) + " " + q(hi) + ",#3a5fcd " + q(hi) + ")";
      sc.insertAdjacentHTML("beforeend",
        '<span class="lb" style="left:' + q(lo / 2) + ';color:#f0c040">Day</span>' +
        '<span class="lb" style="left:' + q((lo + hi) / 2) + '">hysteresis</span>' +
        '<span class="lb" style="left:' + q((hi + span2) / 2) + ';color:#7b9cff">Night</span>' +
        '<span class="tk" style="left:' + q(lo) + '">' + lo + '</span><span class="tk" style="left:' + q(hi) + '">' + hi + "</span>");
      if (g >= 0) { mk.style.left = q(Math.min(g, span2)); mk.hidden = false; }
    }
    var next = "";
    if (!auto) next = "the calendar decides";
    else if (ns) next = ns.next;
    else if (hi > 0) next = "night when exposure <b>&gt; " + hi + "</b>" + (d.day_confirm_s ? " for " + d.day_confirm_s + " s" : "");
    $("dn-next").innerHTML = (next ? "next: " + next : "") + (g >= 0 ? "<br>exposure now " + Math.round(g) : "");
    mk.title = ns ? ns.markTitle : "";
    drawLive();
  }

  function nightScale(d) {
    var A = Number(d.night_baseline), T = Number(d.day_trigger);
    var tTxt = T > 0 ? "; day if the look reads <b>&lt; " + Math.round(T) + "</b>" : "";
    if (!lookEngine(d))
      return { bar: T, ref: A, barName: "probe day", refName: "ref", pending: "reference pending",
               next: T > 0 ? "probe for day when exposure <b>&lt; " + Math.round(T) + "</b>" : "night reference still being taken",
               markTitle: "night-pipeline exposure: IR-lit, not comparable with the day thresholds" };
    if (d.ir_idle && Number(d.ir_idle.dark))
      return { bar: T, ref: -1, barName: "day check", pending: "idle, IR off",
               next: T > 0 ? "day check when exposure <b>&lt; " + Math.round(T) + "</b> for 30 s" : "reading the scene without IR",
               markTitle: "exposure without the IR light (idle-dark)" };
    if (d.ir_idle && d.ir_idle.reason === "no_illuminator") {
      var H = A > 0 ? A * 0.5 : -1;
      return { bar: H, ref: A, barName: "day check", refName: "ref", pending: "level pending",
               next: H > 0 ? "day check when exposure <b>&lt; " + Math.round(H) + "</b> for 20 s, else every " +
                             Math.round((Number(d.heartbeat_s) || 14400) / 360) / 10 + " h" : "night level still being taken",
               markTitle: "night-pipeline exposure, lit by IR" };
    }
    var J = A > 0 ? A * (1 - Number(d.jump_pct) / 100) : -1;
    var lookMin = Math.round(Math.min(2700, Number(d.heartbeat_s) || 2700) / 60);
    return { bar: J, ref: A, barName: "new light", refName: "last look", pending: "IR-lit level pending",
             next: (J > 0 ? "look when exposure <b>&lt; " + Math.round(J) + "</b> for 20 s (last look " +
                            Math.round(A) + "), else every " + lookMin + " min"
                          : "IR-lit level still being taken") + tTxt,
             markTitle: "night-pipeline exposure, lit by the camera's own IR: not comparable with the day thresholds" };
  }

  function drawLive() {
    var el = $("dn-live");
    if (!el) return;
    var d = now, A = Number(d.night_baseline), T = Number(d.day_trigger);
    var n = function (v) { return v >= 0 ? String(Math.round(v)) : "-"; };
    var night = Number(d.mode) === 1;
    if (lookEngine(d))
      el.textContent = night
        ? "Live: IR-lit level at the last look " + n(A) + ", day check if the reading without IR is below " + n(T) + "." +
          (Number(d.color_dev_pct) >= 0 ? " Colour change since the look " + Number(d.color_dev_pct).toFixed(1) + " %." : "")
        : "Live: looks run at night only.";
    else
      el.textContent = "Live: night reference " + (night ? n(A) : "-") + ", probe below " + (night ? n(T) : "-") + ".";
    var b = $("dn-look-now");
    if (b) {
      var can = night && d.dn_mode !== "schedule" && (d.enabled === 1 || d.enabled === true);
      b.disabled = !can || lookBusy;
      b.title = can ? "Switch the IR light off for a few seconds and read the scene without it"
                    : "Only at night with automatic switching by light level";
    }
  }

  var lookBusy = false;
  function lookNow() {
    var res = $("dn-look-res");
    lookBusy = true;
    drawLive();
    res.textContent = "…";
    window.timpsApi.set({ daynight: { probe: 1 } }).then(function (r) {
      res.textContent = r && r.accepted > 0 ? "accepted: the IR light goes off for a few seconds"
        : "refused: no switchable IR light";
    }).catch(function (e) {
      res.textContent = e && e.status === 409 ? "refused: no switchable IR light (daynight.irprobe_cmd)"
        : "failed: " + ((e && e.message) || e);
    }).finally(function () {
      lookBusy = false;
      drawLive();
    });
  }

  function onNow(d) {
    if (!d) return;
    Object.keys(d).forEach(function (k) { now[k] = d[k]; });
    if (d.ir_idle) idleAt = Date.now();
    drawNow();
    drawIdle();
  }

  function durHints() {
    ["heartbeat_s", "heartbeat_max_s", "ir_idle_linger_s"].forEach(function (k) {
      var el = $("daynight_" + k), lab = el && document.querySelector('label[for="daynight_' + k + '"]');
      if (!lab) return;
      var h = lab.querySelector(".dur") || lab.appendChild(Object.assign(document.createElement("span"), { className: "dur ms-1 text-body-secondary" }));
      var v = parseInt(el.value, 10);
      h.textContent = v >= 3600 ? "≈ " + +(v / 3600).toFixed(1) + " h" : v >= 60 ? "≈ " + Math.round(v / 60) + " min" : "";
    });
  }
  document.addEventListener("input", function (e) { if (/daynight_(heartbeat|ir_idle_linger)/.test(e.target.id)) durHints(); });

  function onConfigEvent(type, data) {
    if (type === "daynight") { onNow(data); return; }
    if (!data) return;
    if (data.resync) { load(); return; }
    var id = fieldId(data.key);
    var el = id ? $(id) : null;
    if (!el || document.activeElement === el) return;
    applyTimpsKV(data.key, data.value);
  }

  if (saveBtn) saveBtn.addEventListener("click", save, { capture: true });
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  var lookBtn = $("dn-look-now");
  if (lookBtn) lookBtn.addEventListener("click", lookNow);
  var calSel = $("daynight_calendar");
  if (calSel) calSel.addEventListener("change", syncCalendarUI);
  window.timpsApi.events("config,daynight", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
