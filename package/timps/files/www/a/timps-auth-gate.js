(function () {
  "use strict";

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
  if (typeof window.fetch !== "function") return;
  window.__timpsAuthGate = true;

  var REVEAL_MS = 1500;
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
    /* replace(): a history entry for a never-shown page breaks Back */
    window.location.replace("/login.html");
  }

  root.style.visibility = "hidden";
  timer = setTimeout(reveal, REVEAL_MS);

  try {
    var ctl = typeof AbortController === "function" ? new AbortController() : null;
    if (ctl) setTimeout(function () { ctl.abort(); }, REVEAL_MS);

    fetch("/x/session-status.cgi", {
      cache: "no-store",
      credentials: "same-origin",
      signal: ctl ? ctl.signal : undefined,
    })
      .then(function (res) {
        if (res.status === 401 || res.status === 403) {
          toLogin();
          return null;
        }
        if (!res.ok) return null;
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
