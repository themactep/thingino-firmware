/* timps-auth-gate.js - pre-paint session gate. Injected into <head> by
 * assemble_plugins.py, so it runs before <body> is parsed: it hides the
 * document, asks /x/session-status.cgi, then reveals or leaves for
 * /login.html. Fails OPEN - any error, non-JSON, 5xx or timeout reveals the
 * page and defers to main.js's own load-time check. See WEBUI-NOTES.md. */
(function () {
  "use strict";

  /* Pages main.js does not gate either: the login form, the 401 page, the
   * reboot splash, the Google Photos OAuth landing, and the empty
   * meta-refresh stub at /. */
  var SKIP = {
    "/": 1,
    "/index.html": 1,
    "/login.html": 1,
    "/401.html": 1,
    "/wait.html": 1,
    "/gphotos-auth-callback.html": 1,
  };

  if (SKIP[window.location.pathname]) return;
  if (window.__timpsAuthGate) return;
  if (typeof window.fetch !== "function") return; /* nothing to gate with */
  window.__timpsAuthGate = true;

  var REVEAL_MS = 1500; /* same-origin CGI measures ~30 ms on a LAN */
  var root = document.documentElement;
  var prev = root.style.visibility;
  var settled = false;
  var timer = null;

  function reveal() {
    if (settled) return;
    settled = true;
    if (timer) clearTimeout(timer);
    root.style.visibility = prev;
  }

  function toLogin() {
    if (settled) return;
    settled = true;
    if (timer) clearTimeout(timer);
    /* replace(), not href=: this fires before paint, so a history entry for
     * a never-shown page would make Back bounce straight forward again. */
    window.location.replace("/login.html");
  }

  root.style.visibility = "hidden";
  timer = setTimeout(reveal, REVEAL_MS);

  try {
    var ctl = typeof AbortController === "function" ? new AbortController() : null;
    if (ctl) setTimeout(function () { ctl.abort(); }, REVEAL_MS);

    fetch("/x/session-status.cgi", {
      cache: "no-store",
      credentials: "same-origin", /* HttpOnly session cookie rides along */
      signal: ctl ? ctl.signal : undefined,
    })
      .then(function (res) {
        if (res.status === 401 || res.status === 403) {
          toLogin();
          return null;
        }
        if (!res.ok) return null; /* 5xx etc - fail open */
        return res.json();
      })
      .then(function (data) {
        if (!data || typeof data.authenticated === "undefined") {
          reveal();
        } else if (data.authenticated) {
          reveal();
        } else {
          toLogin();
        }
      })
      .catch(reveal);
  } catch (e) {
    reveal();
  }
})();
