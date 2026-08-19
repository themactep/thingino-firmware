/* tool-timelapse.js - timps native Timelapse Recorder settings.
 *
 * Replaces the stock thingino timelapse page (which edited /etc/timelapse.json
 * + a cron entry calling a prudynt-derived capture script). This version talks
 * DIRECTLY to the timps native timelapse via GET/POST /control (a/timps-api.js):
 * every field maps to a timelapse.* config key, timps persists the changed
 * keys into /etc/timps.conf itself and the running timelapse thread reads
 * them live. Same structure as a/tool-record.js. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-tool-timelapse") return;
  if (!window.timpsApi) {
    console.error("[tool-timelapse] timps-api.js not loaded");
    return;
  }

  var $ = function (id) { return document.getElementById(id); };

  // field id -> {key, type}. type: bool | int | str
  var FIELDS = [
    { id: "tl_enabled",  key: "enabled",    type: "bool" },
    { id: "tl_dir",      key: "dir",        type: "str"  },
    { id: "tl_name",     key: "name",       type: "str"  },
    { id: "tl_channel",  key: "channel",    type: "int"  },
    { id: "tl_interval", key: "interval_s", type: "int"  },
    { id: "tl_keepdays", key: "keep_days",  type: "int"  },
  ];

  // reverse of FIELDS (timps "timelapse.<key>" -> page field id), so another
  // open tab/client changing a setting shows up here live instead of only on
  // next reload.
  var REVERSE = {};
  FIELDS.forEach(function (f) { REVERSE["timelapse." + f.key] = f.id; });

  var form = $("tlForm");
  var reloadBtn = $("tl-reload");
  var saveBtn = $("tl-save");
  var statusEl = $("tl-status");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[tool-timelapse]", type + ":", msg);
  }

  function setStatus(tl) {
    if (!statusEl) return;
    if (!tl || !tl.available) { statusEl.textContent = "Timelapse not available in this build."; return; }
    var bits = [];
    bits.push(tl.enabled ? "running" : "off");
    if (tl.count > 0) bits.push(tl.count + " shot" + (tl.count === 1 ? "" : "s") + " since start");
    if (tl.free_mb != null && tl.free_mb >= 0) bits.push(tl.free_mb + " MB free");
    if (tl.last_file) bits.push(tl.last_file);
    statusEl.textContent = bits.join(" · ");
  }

  function fill(tl) {
    tl = tl || {};
    FIELDS.forEach(function (f) {
      var el = $(f.id);
      if (!el) return;
      var v = tl[f.key];
      if (f.type === "bool") el.checked = (v === true || v === 1);
      else if (v === null || typeof v === "undefined") el.value = "";
      else el.value = v;
    });
  }

  function collect() {
    var out = {};
    FIELDS.forEach(function (f) {
      var el = $(f.id);
      if (!el) return;
      if (f.type === "bool") out[f.key] = !!el.checked;
      else if (f.type === "int") out[f.key] = parseInt(el.value, 10) || 0;
      else out[f.key] = el.value || "";
    });
    return out;
  }

  function load() {
    if (reloadBtn) reloadBtn.disabled = true;
    window.timpsApi.get().then(function (json) {
      fill(json && json.timelapse);
      setStatus(json && json.timelapse);
    }).catch(function (e) {
      toast("danger", "Unable to load timelapse settings: " + (e.message || e));
    }).finally(function () {
      if (reloadBtn) reloadBtn.disabled = false;
    });
  }

  function save(ev) {
    if (ev) ev.preventDefault();
    if (saveBtn) saveBtn.disabled = true;
    window.timpsApi.set({ timelapse: collect() }).then(function (r) {
      // corrected (clamped) values go straight back into their fields from
      // the "applied" echo - no follow-up GET on the happy path
      var corr = r && r.corrections;
      if (corr) Object.keys(corr).forEach(function (k) {
        var id = REVERSE[k];
        if (id) applyKV(id, corr[k]);
      });
      corr = window.timpsApi.takeCorrections(r);
      // refused values keep their OLD stored value, which is NOT echoed
      // (nothing changed), and a truncated echo is incomplete - only a
      // reload shows the truth in those two cases
      var needReload = r && (r.rejected > 0 || r.truncated);
      if (r && r.rejected > 0)
        toast("warning", "Saved, but the streamer refused " + r.rejected +
          " value(s) (empty or invalid).", 6000);
      else if (corr)
        toast("info", "Saved. " + window.timpsApi.correctionsText(corr) + ".", 6000);
      else
        toast("success", "Timelapse settings saved to timps.conf (applied live).", 4000);
      if (needReload) load();
    }).catch(function (e) {
      toast("danger", "Failed to save timelapse settings: " + (e.message || e));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  // write one field's timps value into its element - shared by the config-
  // sync push and the save-time "applied" corrections, so a clamped value
  // renders exactly like a remote edit
  function applyKV(id, value) {
    var f = FIELDS.find(function (x) { return x.id === id; });
    var el = $(id);
    if (!f || !el) return;
    if (f.type === "bool") el.checked = (value === "1" || value === "true");
    else el.value = value;
  }

  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(); return; }
    var id = REVERSE[data.key];
    var el = id ? $(id) : null;
    // don't fight the user mid-edit on this same field
    if (!el || document.activeElement === el) return;
    applyKV(id, data.value);
  }

  if (form) form.addEventListener("submit", save);
  if (reloadBtn) reloadBtn.addEventListener("click", load);
  window.timpsApi.events("config", onConfigEvent);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
