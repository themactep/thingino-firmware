/**
 * Doorbell chime status banner.
 *
 * Loaded globally when the doorbell plugin is installed.  Checks whether
 * any chimes are configured and shows a warning banner on every page if
 * none are found.
 */
(function () {
  "use strict";

  var done = false;

  function showBanner() {
    if (done) return;
    done = true;

    fetch("/x/json-chime-status.cgi")
      .then(function (r) { return r.json(); })
      .then(function (data) {
        if (data.configured === false) {
          var banner = document.createElement("div");
          banner.className =
            "alert alert-warning text-center rounded-0 mb-3 py-2";
          banner.innerHTML =
            '<i class="bi bi-exclamation-triangle-fill me-2"></i>' +
            "No doorbell chime configured. " +
            '<a href="/config-doorbell.html" class="alert-link">Pair a chime</a> ' +
            "to enable the doorbell.";
          var container = document.querySelector("main .container");
          if (container) {
            var section = container.querySelector("section");
            if (section) {
              container.insertBefore(banner, section);
            } else {
              container.appendChild(banner);
            }
          }
        }
      })
      .catch(function () {
        /* Silently ignore */
      });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", showBanner, { once: true });
  } else {
    showBanner();
  }
})();
