/* timps-version.js - tiny build-version badge, bottom-right corner, on every
 * page that includes this script. Reads GET /control's "version" key (the
 * daemon's compiled-in MS_VERSION, a git-describe string) - added after a
 * 2026-08 incident where a stale cached build kept getting reflashed
 * undetected; this makes "which commit is this camera actually running"
 * visible at a glance from the WebUI, not just via a manual /control fetch.
 * No-ops silently if timps-api.js isn't loaded or the daemon build predates
 * the "version" field. */
(function () {
  "use strict";
  if (!window.timpsApi) return;

  function render(v) {
    var slot = document.getElementById("footer-timps-version");
    if (slot) {
      slot.textContent = "timps " + v;
      slot.title = "timps build version";
      return;
    }
    var el = document.createElement("div");
    el.textContent = v;
    el.title = "timps build version";
    el.style.cssText =
      "position:fixed;right:6px;bottom:3px;font-size:.7rem;opacity:.35;" +
      "font-family:monospace;pointer-events:none;z-index:1;user-select:none;";
    document.body.appendChild(el);
  }

  function tryRender() {
    window.timpsApi.get().then(function (j) {
      var v = j && j.version;
      if (!v) return;
      render(v);
    }).catch(function () {});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", tryRender, { once: true });
  } else {
    tryRender();
  }
})();
