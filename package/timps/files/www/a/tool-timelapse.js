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
    window.timpsApi.set({ timelapse: collect() }).then(function () {
      toast("success", "Timelapse settings saved to timps.conf (applied live).", 4000);
      load();
    }).catch(function (e) {
      toast("danger", "Failed to save timelapse settings: " + (e.message || e));
    }).finally(function () {
      if (saveBtn) saveBtn.disabled = false;
    });
  }

  if (form) form.addEventListener("submit", save);
  if (reloadBtn) reloadBtn.addEventListener("click", load);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
