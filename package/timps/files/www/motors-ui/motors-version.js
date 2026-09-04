/* motors-version.js - tiny build-version badge for the PTZ motors daemon,
 * appended into the page footer (unlike timps-version.js this has no
 * floating-corner fallback: motors is optional and a stray badge for an
 * absent/irrelevant feature would be more confusing than useful). Reads
 * json-motor.cgi's "version" field (motors -j's compiled-in git-describe
 * string) via the CGI's status command (d=j). No-ops silently if the footer
 * isn't mounted, the CGI 404s (no motors package on this build), or the
 * daemon isn't running.
 *
 * Same reasoning as timps-version.js: footer.js (core, thingino-webui) has
 * no id slot or plugin-manifest hook for this, so this script finds the
 * already-mounted footer itself instead of forking that core file. Declared
 * in motors.webui.json's "preview.scripts" (feature-flag gated on
 * BR2_PACKAGE_THINGINO_MOTORS, preview.html only), which assemble_plugins.py
 * injects right before </body> - guaranteed to run after footer.js's
 * DOMContentLoaded listener (registered earlier, in <head>/mid-body) has
 * mounted the footer. Do NOT move this into the manifest's top-level
 * "scripts" array: those get injected in <head> and would run before the
 * footer exists. */
(function () {
  "use strict";

  function footerRightCol() {
    var footer = document.querySelector('footer[data-generated-footer="true"]');
    return footer ? footer.querySelector(".text-sm-end") : null;
  }

  function tryRender() {
    var rightCol = footerRightCol();
    if (!rightCol) return;

    fetch("/x/json-motor.cgi?d=j", { cache: "no-store" })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (j) {
        // json-motor.cgi's json_ok() wraps every payload as
        // {"code":200,"result":"success","message":<motors -j's own object>} -
        // the version field lives at j.message.version, not j.version.
        var v = j && j.message && j.message.version;
        if (!v) return;
        var el = document.createElement("div");
        el.className = "small";
        el.textContent = "motors " + v;
        el.title = "motors-daemon build version";
        rightCol.appendChild(el);
      })
      .catch(function () {});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", tryRender, { once: true });
  } else {
    tryRender();
  }
})();
