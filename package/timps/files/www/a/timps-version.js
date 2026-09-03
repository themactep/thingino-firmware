/* timps-version.js - tiny build-version badge, in the page footer (falls
 * back to a floating bottom-right corner badge if no footer is mounted), on
 * every page that includes this script. Reads GET /control's "version" key
 * (the daemon's compiled-in MS_VERSION, a git-describe string) so "which
 * commit is this camera actually running" is visible at a glance (see
 * WEBUI-NOTES.md). No-ops silently if timps-api.js isn't loaded or the
 * daemon build predates the "version" field.
 *
 * footer.js (core, thingino-webui) builds the footer's DOM at runtime and
 * has no id slot or plugin-manifest hook for this - so instead of forking
 * that core file just to add one <div>, this script finds the already-
 * mounted footer itself and appends its own element. Requires footer.js's
 * <script> tag to appear before this one so its DOMContentLoaded listener
 * (which mounts the footer) runs first; every page that includes this file
 * already orders it that way. */
(function () {
  "use strict";
  if (!window.timpsApi) return;

  function footerRightCol() {
    var footer = document.querySelector('footer[data-generated-footer="true"]');
    return footer ? footer.querySelector(".text-sm-end") : null;
  }

  function render(v) {
    var rightCol = footerRightCol();
    if (rightCol) {
      var el = document.createElement("div");
      el.className = "small";
      el.textContent = "timps " + v;
      el.title = "timps build version";
      rightCol.appendChild(el);
      return;
    }
    var badge = document.createElement("div");
    badge.textContent = v;
    badge.title = "timps build version";
    badge.style.cssText =
      "position:fixed;right:6px;bottom:3px;font-size:.7rem;opacity:.35;" +
      "font-family:monospace;pointer-events:none;z-index:1;user-select:none;";
    document.body.appendChild(badge);
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
