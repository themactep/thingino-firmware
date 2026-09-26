(function () {
  "use strict";

  function $(sel) {
    return document.querySelector(sel);
  }

  var apiPromise = null;
  function timpsApiReady() {
    if (window.timpsApi) return Promise.resolve(window.timpsApi);
    if (apiPromise) return apiPromise;
    apiPromise = new Promise(function (resolve, reject) {
      var sc = document.createElement("script");
      sc.src = "/a/timps-api.js";
      sc.onload = function () {
        window.timpsApi
          ? resolve(window.timpsApi)
          : reject(new Error("timps-api.js loaded but window.timpsApi missing"));
      };
      sc.onerror = function () {
        reject(new Error("failed to load timps-api.js"));
      };
      document.head.appendChild(sc);
    });
    return apiPromise;
  }
  window.timpsApiReady = timpsApiReady;

  /* ---- control-bar actions ------------------------------------------ */

  // timps records ONE channel at a time (record.channel).
  function toggleRecording(channel) {
    var button = $("#recorder-ch" + channel);
    var want = button && button.classList.contains("active") ? 0 : 1;
    if (button) button.classList.add("pending");

    var payload = want
      ? { record: { channel: channel, active: 1 } }
      : { record: { active: 0 } };
    timpsApiReady()
      .then(function (api) {
        return api.set(payload).then(function () {
          window.updateRecordingState({
            ch0: !!want && channel === 0,
            ch1: !!want && channel === 1,
          });
          if (want) {
            setTimeout(function () {
              api.get().then(function (info) {
                var rec = info && info.record;
                if (!rec || rec.recording) return;
                var fresh =
                  rec.last_error &&
                  rec.last_error_age_s != null &&
                  rec.last_error_age_s >= 0 &&
                  rec.last_error_age_s < 5;
                if (!fresh) return;
                window.updateRecordingState({ ch0: false, ch1: false });
                if (button) button.classList.remove("active");
                if (typeof window.showAlert === "function")
                  window.showAlert(
                    "danger",
                    "Recording did not start: " + rec.last_error,
                  );
              });
            }, 2000);
          }
        });
      })
      .catch(function (err) {
        console.error("Recording toggle error", err);
        if (button) button.classList.remove("pending");
        if (typeof window.showAlert === "function")
          window.showAlert(
            "danger",
            "Failed to toggle recording: " + (err.message || err),
          );
      });
  }

  // timps motion detection is toggled through /control (live, no restart).
  function toggleMotion(state) {
    var button = $("#motion");
    if (button) button.classList.add("pending");

    timpsApiReady()
      .then(function (api) {
        return api.set({ motion: { enabled: state ? 1 : 0 } });
      })
      .then(function () {
        window.updateHeartbeatUi({ motion_enabled: state ? 1 : 0 });
      })
      .catch(function (err) {
        console.error("Motion toggle error", err);
        if (button) button.classList.remove("pending");
      });
  }

  // timps privacy is per-region (no global switch), so this quick toggle
  // enables/disables ALL configured cover regions on every stream.
  function togglePrivacy(state) {
    var button = $("#privacy");
    if (button) button.classList.add("pending");

    timpsApiReady()
      .then(function (api) {
        return api.get().then(function (json) {
          var priv = (json && json.privacy) || {};
          var payload = {};
          Object.keys(priv).forEach(function (s) {
            payload[s] = {};
            Object.keys(priv[s]).forEach(function (n) {
              payload[s][n] = { enabled: state ? 1 : 0 };
            });
          });
          return Object.keys(payload).length ? api.set({ privacy: payload }) : null;
        });
      })
      .then(function () {
        window.updateHeartbeatUi({ privacy_enabled: state ? 1 : 0 });
      })
      .catch(function (err) {
        console.error("Privacy toggle error", err);
        if (button) button.classList.remove("pending");
      });
  }

  // Grey out an audio control-bar button the streamer declared unsupported
  // (the Speaker on timps, which has no audio-output pipeline).
  function disableAudioButton(device, reason) {
    var button = $("#" + device);
    if (!button) return;
    button.classList.remove("pending", "active");
    button.disabled = true;
    button.classList.add("disabled");
    if (reason) button.title = reason;
  }

  function toggleAudio(device, state) {
    var button = $("#" + device);
    if (button) button.classList.add("pending");

    // timps has no audio-output (AO) pipeline: grey the speaker button out.
    if (device !== "microphone") {
      disableAudioButton(device, "No speaker output on timps");
      if (typeof window.showOverlayMessage === "function")
        window.showOverlayMessage("The timps streamer has no speaker output.", "info");
      return;
    }

    // The mic button is the live mute: mic_enabled=false -> audio.mute 1.
    timpsApiReady()
      .then(function (api) {
        return api.set({ audio: { mute: state ? 0 : 1 } });
      })
      .then(function () {
        window.updateHeartbeatUi({ mic_enabled: state });
      })
      .catch(function (err) {
        console.error("Audio toggle error", err);
        if (button) button.classList.remove("pending");
      });
  }

  // /x/timps-imp.cgi is timps's own day/night + IR/white-light bridge.
  var IMP_CGI = "/x/timps-imp.cgi";

  function impPost(payload) {
    return fetch(IMP_CGI, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify(payload),
    }).then(function (res) {
      if (!res.ok) throw new Error("HTTP error " + res.status);
      return res.text();
    });
  }

  // Core routes day/night through the thingino agent; timps owns day/night
  // itself, so the command goes to the timps bridge instead.
  function toggleDayNight(mode) {
    var button = $("#daynight");
    if (button) button.classList.add("pending");

    impPost({ cmd: "daynight", val: mode })
      .then(function (text) {
        if (text) {
          try {
            console.log(window.ts ? window.ts() : "", "<===", text);
          } catch (e) {
            /* logging only */
          }
        }
        // Update button state immediately from the known target mode
        window.updateHeartbeatUi({ daynight_mode: mode, daynight_enabled: false });
      })
      .catch(function (err) {
        console.error("DayNight toggle error", err);
        if (button) button.classList.remove("pending");
      });
  }

  function toggleButton(el) {
    if (!el) return Promise.resolve();
    var currentState = el.classList.contains("active") ? 1 : 0;
    var newState = currentState ? 0 : 1;

    // color button: ISP mode 0=color, 1=b&w, so the value is inverted
    if (el.id === "color") newState = currentState ? 1 : 0;

    el.classList.add("pending");

    return impPost({ cmd: el.id, val: newState })
      .then(function (text) {
        var keyMap = {
          color: { color_mode: newState },
          ircut: { ircut_state: newState },
          ir850: { ir850_state: newState },
          ir940: { ir940_state: newState },
          white: { white_state: newState },
          auto: { daynight_enabled: newState },
        };
        var update = keyMap[el.id] ? Object.assign({}, keyMap[el.id]) : {};
        // Leaving auto mode pins the mode the camera is in right now; the
        // bridge clears daynight.enabled for the manual IR/ircut commands.
        if (el.id === "auto" && !newState) {
          var dn = $("#daynight");
          update.daynight_mode =
            dn && dn.classList.contains("is-night") ? "night" : "day";
        } else if (
          el.id === "ircut" ||
          el.id === "ir850" ||
          el.id === "ir940" ||
          el.id === "white"
        ) {
          update.daynight_enabled = false;
        }
        if (Object.keys(update).length) {
          window.updateHeartbeatUi(update);
        } else {
          el.classList.remove("pending");
        }
      })
      .catch(function (err) {
        console.error("toggleButton error", err);
        el.classList.remove("pending");
      });
  }

  /* ---- install ------------------------------------------------------- */

  function install() {
    window.toggleRecording = toggleRecording;
    window.toggleMotion = toggleMotion;
    window.togglePrivacy = togglePrivacy;
    window.toggleAudio = toggleAudio;
    window.toggleDayNight = toggleDayNight;
    window.toggleButton = toggleButton;

    var coreUpdateHeartbeatUi = window.updateHeartbeatUi;
    if (typeof coreUpdateHeartbeatUi === "function") {
      window.updateHeartbeatUi = function (json) {
        coreUpdateHeartbeatUi(json);
        if (json && json.spk_supported === false) {
          disableAudioButton("speaker", "No speaker output on timps");
        }
      };
    }

    var coreSetValue = window.setValue;
    if (typeof coreSetValue === "function") {
      window.setValue = function (data, domain, name) {
        coreSetValue(data, domain, name);
        if (!data || typeof data[name] === "undefined") return;
        var el = document.getElementById(domain + "_" + name);
        if (!el) return;
        var wrapper = el.closest(".form-switch");
        if (wrapper) wrapper.classList.remove("disabled");
      };
    }

    document.addEventListener("visibilitychange", function () {
      if (document.hidden) return;
      if (typeof window.restartStreamPreview === "function")
        window.restartStreamPreview();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", install, { once: true });
  } else {
    // main.js already ran (e.g. script injected late) - override immediately.
    install();
  }
})();
