/* streamer-sensor.js - Sensor IQ File page helper.
 *
 * The page has no timps-settable fields: the sensor model / resolution / fps
 * are read-only (shown by preview.js via /x/json-sensor-info.cgi, a filesystem
 * helper that reads /proc/jz/sensor and the /etc/sensor/*.bin md5 - NOT a timps
 * bridge), and the IQ binary is changed through the upload form. This replaces
 * the old a/streamer-config.js (/x/json-prudynt.cgi bridge) whose only job here
 * was the "Save configuration" button. timps persists every /control change
 * live, so the button just reassures + points at the restart for the sensor
 * re-init (sensor keys are restart-required). Kept intentionally tiny. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-streamer-sensor") return;

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, message, ms);
    else console.log("[streamer-sensor]", type + ":", message);
  }

  function init() {
    var saveBtn = document.getElementById("save-prudynt-config");
    if (saveBtn) {
      saveBtn.addEventListener("click", function () {
        toast(
          "success",
          "Sensor settings are saved live to the streamer configuration; restart the streamer to re-initialise the sensor.",
          5000,
        );
      });
    }
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init, { once: true });
  else init();
})();
