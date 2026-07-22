/* config-audio.js - NATIVE Audio Settings page. Talks directly to the timps
 * streamer over window.timpsApi (GET/POST /control on timps's own port, per-
 * boot token) - no json-prudynt.cgi bridge for this page (a/audio.js and
 * a/streamer-config.js are no longer loaded here).
 *
 * Load:  timpsApi.get() -> populate every control from the "audio" object.
 *        LIVE controls are enabled only when their timps key is listed in
 *        caps.audio (the SoC capability matrix); the persist+restart keys
 *        (codec/samplerate/bitrate) are deliberately NOT in caps.audio, so
 *        they enable when the audio object carries them. Speaker and stereo
 *        controls stay greyed out: timps has no audio-output (AO) pipeline.
 * Save:  LIVE keys (volume/gain/alc_gain/high_pass/agc/agc_target_dbfs/
 *        agc_compression_db/ns) go straight to timpsApi.set({audio:{...}}),
 *        debounced so slider drags coalesce into one POST; timps applies
 *        them live AND persists immediately. PERSIST+RESTART keys (codec/
 *        samplerate/bitrate) are saved the same way but only take effect
 *        after a streamer restart, so those changes show the existing
 *        "Restart streamer" hint (the menu entry calls /x/restart-prudynt.cgi).
 * Offline: if timps is unreachable the controls stay disabled and a small
 *        notice appears; nothing throws.
 */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-audio") return;

  // page field id (prudynt-era name) -> timps audio.* key.
  // live:true = in caps.audio and applied immediately by the HAL;
  // live:false = persist-only, needs a streamer restart to take effect.
  // (The page has no mic on/off switch - the control bar's mic button is the
  // live mute; it maps to audio.mute elsewhere.)
  var FIELD_MAP = {
    audio_mic_vol: { key: "volume", live: true },
    audio_mic_gain: { key: "gain", live: true },
    audio_mic_alc_gain: { key: "alc_gain", live: true },
    // high_pass/agc/ns are restart-required: libimp runs these DSP modules on
    // its own record thread and frees them unlocked, so a live toggle races the
    // vendor thread -> crash. Persist + "applies on restart", like codec.
    audio_mic_high_pass_filter: { key: "high_pass", live: false },
    audio_mic_agc_enabled: { key: "agc", live: false },
    audio_mic_agc_target_level_dbfs: { key: "agc_target_dbfs", live: false },
    audio_mic_agc_compression_gain_db: { key: "agc_compression_db", live: false },
    audio_mic_noise_suppression: { key: "ns", live: false },
    audio_mic_format: { key: "codec", live: false },
    audio_mic_sample_rate: { key: "samplerate", live: false },
    audio_mic_bitrate: { key: "bitrate", live: false },
  };

  // no audio output (AO) pipeline in timps: these controls never enable
  var UNSUPPORTED = [
    "audio_spk_vol",
    "audio_spk_gain",
    "audio_spk_sample_rate",
    "audio_force_stereo",
  ];

  // page codec names <-> timps canonical codec spelling. The page options
  // timps cannot encode (G726/OPUS/PCM) are disabled in wireControls().
  var CODEC_TO_TIMPS = { AAC: "aac", G711U: "pcmu", G711A: "pcma" };
  var CODEC_FROM_TIMPS = { aac: "AAC", pcmu: "G711U", pcma: "G711A" };

  // reverse of FIELD_MAP (timps "audio.<key>" -> page field id), so another
  // open tab/client changing a setting shows up here live instead of only on
  // next reload.
  var REVERSE = {};
  Object.keys(FIELD_MAP).forEach(function (id) {
    REVERSE["audio." + FIELD_MAP[id].key] = id;
  });

  function $id(id) { return document.getElementById(id); }

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function")
      window.showAlert(type, message, ms);
    else console.log("[config-audio]", type + ":", message);
  }

  function restartHint() {
    toast(
      "warning",
      "Setting saved. Restart the streamer (Restart streamer in the menu) for it to take effect.",
      8000,
    );
  }

  // same disabled styling audio.js/main.js always used: input.disabled + a
  // "disabled" class on the wrapping block
  function setEnabled(id, on) {
    var el = $id(id);
    if (!el) return;
    el.disabled = !on;
    var wrap =
      el.closest(
        ".range, .number-range, .number, .select, .boolean, .file, .form-switch",
      ) || el.parentElement;
    if (wrap) wrap.classList.toggle("disabled", !on);
  }

  // rebuild the sample-rate/bitrate <select> options from the data-* hints
  // (same behavior initDynamicSelects() in a/audio.js provided)
  function populateDynamicSelect(select) {
    if (!select || select.dataset.dynamicOptionsReady === "1") return;
    var values = null;
    if (select.dataset.optionValues) {
      values = select.dataset.optionValues
        .split(",").map(function (s) { return s.trim(); }).filter(Boolean);
    } else if (select.dataset.rangeMin && select.dataset.rangeMax) {
      var min = Number(select.dataset.rangeMin);
      var max = Number(select.dataset.rangeMax);
      var step = Number(select.dataset.rangeStep) || 1;
      if (isFinite(min) && isFinite(max)) {
        values = [];
        for (var v = min; v <= max; v += step) values.push(String(v));
      }
    }
    if (!values || !values.length) return;
    select.innerHTML = '<option value="">- Select -</option>';
    values.forEach(function (item) {
      var option = document.createElement("option");
      option.value = item;
      option.textContent = item;
      select.appendChild(option);
    });
    select.dataset.dynamicOptionsReady = "1";
  }

  function populate(id, value) {
    var el = $id(id);
    if (!el || value === undefined || value === null) return;
    if (el.type === "checkbox") el.checked = !!Number(value);
    else if (id === "audio_mic_format")
      el.value = CODEC_FROM_TIMPS[String(value).toLowerCase()] || "";
    else el.value = value;
  }

  // one changed control -> POST {"audio":{key:val}} to timps. Live keys are
  // debounced (slider drags coalesce); persist+restart keys go out directly
  // and show the restart hint.
  function send(id) {
    var el = $id(id);
    var map = FIELD_MAP[id];
    if (!el || !map) return;
    var value;
    if (el.type === "checkbox") value = el.checked ? 1 : 0;
    else if (id === "audio_mic_format") {
      value = CODEC_TO_TIMPS[el.value];
      if (!value) return;
    } else {
      value = parseInt(el.value, 10);
      if (isNaN(value)) return;
    }
    var audio = {};
    audio[map.key] = value;
    el.classList.add("opacity-75");
    var done = function () { el.classList.remove("opacity-75"); };
    var fail = function (err) {
      console.error("timps set failed:", err);
      toast("danger", "Failed to apply setting: " + (err.message || err));
    };
    if (map.live) {
      window.timpsApi.setDebounced({ audio: audio }, 150).catch(fail).then(done);
    } else {
      window.timpsApi
        .set({ audio: audio })
        .then(function () { restartHint(); }, fail)
        .then(done);
    }
  }

  function wireControls() {
    populateDynamicSelect($id("audio_mic_sample_rate"));
    populateDynamicSelect($id("audio_mic_bitrate"));
    populateDynamicSelect($id("audio_spk_sample_rate"));

    // codecs timps cannot encode stay listed but not selectable
    var fmt = $id("audio_mic_format");
    if (fmt) {
      Array.prototype.forEach.call(fmt.options, function (opt) {
        if (opt.value && !CODEC_TO_TIMPS[opt.value]) {
          opt.disabled = true;
          opt.textContent = opt.textContent + " (not supported)";
        }
      });
    }

    Object.keys(FIELD_MAP).forEach(function (id) {
      var el = $id(id);
      if (!el) return;
      setEnabled(id, false); // disabled until timps confirms support
      el.addEventListener("change", function () { send(id); });
    });

    // speaker + stereo: no AO pipeline in timps, keep greyed out + a note
    UNSUPPORTED.forEach(function (id) { setEnabled(id, false); });
    var spkHead = Array.prototype.find.call(
      document.querySelectorAll("main h4"),
      function (h) { return /speaker/i.test(h.textContent); },
    );
    if (spkHead && !$id("timps-no-ao-note")) {
      var note = document.createElement("small");
      note.id = "timps-no-ao-note";
      note.className = "d-block text-warning";
      note.textContent =
        "Not available: this streamer has no audio output (speaker) pipeline. Stereo capture is not supported either.";
      spkHead.parentNode.insertBefore(note, spkHead.nextSibling);
    }

    // timps applies + persists every change immediately; the button is
    // kept only to reassure users trained on the old save-to-file step.
    var saveBtn = $id("save-prudynt-config");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        toast(
          "success",
          "Nothing to do: audio settings are applied and already saved to the streamer configuration (codec, sampling and bitrate take effect after a streamer restart).",
          5000,
        );
      });
    }

    var reloadBtn = $id("audio-reload");
    if (reloadBtn) {
      reloadBtn.addEventListener("click", function () {
        reloadBtn.disabled = true;
        load(true).then(function () { reloadBtn.disabled = false; });
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
      "The streamer is not reachable, audio controls are disabled. " +
      "Check that the timps service is running, then reload this page.";
    var section = document.querySelector("main section");
    var container = document.querySelector("main .container");
    if (section && section.parentNode)
      section.parentNode.insertBefore(div, section);
    else if (container) container.appendChild(div);
  }

  // silent=true: reload triggered by the button (toast instead of busy veil)
  function load(silent) {
    if (!window.timpsApi) {
      console.error("timps-api.js not loaded");
      offlineNotice();
      return Promise.resolve();
    }
    if (!silent && typeof window.showBusy === "function")
      window.showBusy("Loading audio settings...");
    return window.timpsApi
      .get()
      .then(function (json) {
        var audio = json.audio || {};
        var capsAudio = (json.caps && json.caps.audio) || [];
        Object.keys(FIELD_MAP).forEach(function (id) {
          var map = FIELD_MAP[id];
          populate(id, audio[map.key]);
          // live keys: only what the SoC can drive (caps.audio); persist+
          // restart keys are not listed in caps by design - enable them
          // whenever timps reports a value for them
          var on = map.live
            ? capsAudio.indexOf(map.key) >= 0
            : audio[map.key] !== undefined;
          setEnabled(id, on);
        });
        var offline = $id("timps-offline-notice");
        if (offline) offline.remove();
        if (silent) toast("info", "Audio settings reloaded.", 3000);
      })
      .catch(function (err) {
        console.warn("timps unreachable, audio controls stay disabled:", err);
        offlineNotice();
      })
      .then(function () {
        if (!silent && typeof window.hideBusy === "function") window.hideBusy();
      });
  }

  // don't fight the user mid-drag on this same page; the value will land
  // anyway once they let go and post their own change
  function onConfigEvent(type, data) {
    if (!data) return;
    if (data.resync) { load(false); return; }
    var id = REVERSE[data.key];
    if (!id) return;
    var el = $id(id);
    if (!el || document.activeElement === el) return;
    populate(id, data.value);
  }

  function init() {
    wireControls();
    load(false);
    if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
