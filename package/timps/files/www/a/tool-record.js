/* tool-record.js - timps Video Recorder settings.
 *
 * Replaces the stock thingino recorder page (which POSTed to
 * /x/tool-record.cgi and wrote thingino's OWN recorder config, never touching
 * timps.conf). This version talks DIRECTLY to the timps native recorder via
 * GET/POST /control (a/timps-api.js): every field maps to a record.* config
 * key, and timps persists the changed keys into /etc/timps.conf itself
 * (config_write_keys) while the running recorder reads them live. So the path
 * you set here is the path timps actually records to and the Recordings page
 * lists from. Dependency-free; no bridge CGI. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-tool-record-video") return;
  if (!window.timpsApi) {
    console.error("[tool-record] timps-api.js not loaded");
    return;
  }

  var $ = function (id) { return document.getElementById(id); };

  // field id -> {key, type}. type: bool | int | str
  var FIELDS = [
    { id: "rec_enabled",  key: "enabled",     type: "bool" },
    { id: "rec_dir",      key: "dir",         type: "str"  },
    { id: "rec_name",     key: "name",        type: "str"  },
    { id: "rec_audio",    key: "audio",       type: "bool" },
    { id: "rec_mode",     key: "mode",        type: "int"  },
    { id: "rec_channel",  key: "channel",     type: "int"  },
    { id: "rec_segment",  key: "segment_s",   type: "int"  },
    { id: "rec_preroll",  key: "pre_roll_s",  type: "int"  },
    { id: "rec_postroll", key: "post_roll_s", type: "int"  },
    { id: "rec_minfree",  key: "min_free_mb", type: "int"  },
  ];

  var form = $("recForm");
  var reloadBtn = $("rec-reload");
  var saveBtn = $("rec-save");
  var statusEl = $("rec-status");

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[tool-record]", type + ":", msg);
  }

  function setStatus(rec) {
    if (!statusEl) return;
    if (!rec || !rec.available) { statusEl.textContent = "Recorder not available in this build."; return; }
    var bits = [];
    bits.push(rec.recording ? "recording now" : "idle");
    if (rec.free_mb != null && rec.free_mb >= 0) bits.push(rec.free_mb + " MB free");
    if (rec.recording && rec.file) bits.push(rec.file);
    statusEl.textContent = bits.join(" · ");
  }

  function fill(rec) {
    rec = rec || {};
    FIELDS.forEach(function (f) {
      var el = $(f.id);
      if (!el) return;
      var v = rec[f.key];
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

  function motionHint(json) {
    // motion-triggered recording only fires when motion DETECTION is enabled
    // (Streamer -> Motion), which is a different switch from this "mode" select
    var modeEl = $("rec_mode");
    var isMotion = modeEl && String(modeEl.value) === "1";
    var m = json && json.motion;
    if (isMotion && m && m.available && !m.enabled) {
      toast(
        "warning",
        "Recording mode is “Motion-triggered”, but motion detection is OFF — enable it under Streamer → Motion, otherwise nothing will be recorded.",
        9000,
      );
    }
  }

  function load() {
    if (reloadBtn) reloadBtn.disabled = true;
    window.timpsApi.get().then(function (json) {
      fill(json && json.record);
      setStatus(json && json.record);
      motionHint(json);
    }).catch(function (e) {
      toast("danger", "Unable to load recorder settings: " + (e.message || e));
    }).finally(function () {
      if (reloadBtn) reloadBtn.disabled = false;
    });
  }

  function save(ev) {
    if (ev) ev.preventDefault();
    if (saveBtn) saveBtn.disabled = true;
    window.timpsApi.set({ record: collect() }).then(function () {
      toast("success", "Recorder settings saved to timps.conf (applies to the next clip).", 4000);
      load();
    }).catch(function (e) {
      toast("danger", "Failed to save recorder settings: " + (e.message || e));
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
