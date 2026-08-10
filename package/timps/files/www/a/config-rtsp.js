/* config-rtsp.js - timps RTSP/ONVIF access page.
 *
 * Replaces the stock thingino-webui script, which fetched
 *   http://<host>:8080/api/v1/config/rtsp   (X-API-Key from /x/api-key.cgi)
 * a REST config server that exists only for the other streamer. A timps image
 * has no listener on port 8080 at all, so every request from the stock page
 * hangs/fails, loadConfig()'s try block never completes and the page is stuck
 * with four "Loading..." URLs and empty credential fields forever. The
 * RTSP/ONVIF password simply could not be changed from the WebUI.
 *
 * Two data sources here, because timps splits them deliberately:
 *
 *   GET /control (a/timps-api.js)   videoN.rtsp_path + videoN.enabled, live.
 *                                   rtsp_path is runtime-mutable, so this is
 *                                   the authoritative mount point.
 *   GET /x/json-config-rtsp.cgi     rtsp.user / rtsp.pass / rtsp.port /
 *                                   rtsp.tls* from /etc/timps.conf, plus the
 *                                   ONVIF port from /etc/onvif.json.
 *
 * The credentials are NOT available over /control: GET never emits an "rtsp"
 * section and rtsp.user/rtsp.pass carry no F_CTRL flag, timps' mandatory
 * per-field allowlist for POST /control (see apply_ctrl_fields() in
 * src/control.c, which names "every rtsp.* / http.* credential/token" as
 * intentionally unreachable from the network API). Reading and writing them
 * therefore goes through the session-authenticated CGI on the camera - the
 * same split config-photosensing.js already uses for the board-script keys it
 * cannot reach over /control.
 *
 * Behaviour kept from the stock page: readonly username, password edit +
 * save, Reload button, and the ONVIF / RTSP main / RTSP sub ready-to-use URLs.
 * The one honest change is "RTSP microphone only": timps has no audio-only
 * mount point (rtsp.c's find_video_by_path() falls back to the first enabled
 * VIDEO stream for an unknown path, so a /mic URL would quietly serve ch0),
 * so that row says so instead of printing a URL that does not work.
 */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-config-rtsp") return;

  var CGI = "/x/json-config-rtsp.cgi";

  var form = $("#rtspForm");
  var usernameInput = $("#rtsp_username");
  var passwordInput = $("#rtsp_password");
  var submitButton = $("#rtsp_submit");
  var reloadButton = $("#rtsp-reload");
  var disabledWarn = $("#rtsp-disabled");

  // last merged view of the settings, so save() can re-render without a reload
  var state = null;

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[config-rtsp]", type + ":", msg);
  }

  function busy(on, label) {
    if (passwordInput) passwordInput.disabled = on;
    if (submitButton) submitButton.disabled = on;
    if (on) {
      if (typeof window.showBusy === "function") window.showBusy(label || "Working...");
    } else if (typeof window.hideBusy === "function") {
      window.hideBusy();
    }
  }

  function ipv6Wrap(host) {
    return host && host.indexOf(":") >= 0 && host.charAt(0) !== "[" ? "[" + host + "]" : host;
  }

  // Only append the port when it is not the scheme's default, matching the
  // stock page (and what a user would type by hand).
  function hostWithPort(host, port, defaults) {
    var n = parseInt(port, 10);
    if (!port || isNaN(n) || defaults.indexOf(n) >= 0) return host;
    return host + ":" + n;
  }

  function credential(user, pass) {
    if (!user) return ""; // timps treats an empty rtsp.user as "auth disabled"
    return encodeURIComponent(user) + ":" + encodeURIComponent(pass || "") + "@";
  }

  function renderUrls(d) {
    var host = ipv6Wrap(window.network_address || window.location.hostname || "localhost");
    var auth = credential(d.username, d.password);
    var onvifTarget = hostWithPort(host, d.onvif_port, [80, 443]);
    var rtspTarget = hostWithPort(host, d.rtsp_port, d.rtsp_scheme === "rtsps" ? [322] : [554]);

    setText("#url-onvif", "onvif://" + auth + onvifTarget + "/onvif/device_service");
    setText("#url-rtsp-main", d.rtsp_scheme + "://" + auth + rtspTarget + "/" + d.rtsp_ch0);

    // Class list is left alone on purpose: main.js's initCopyToClipboard()
    // binds its click handler once, to whatever carried .cb at page init, so
    // toggling the class later would not actually attach or detach copying -
    // only the text is ours to change.
    setText("#url-rtsp-sub", d.ch1_enabled === false
      ? "Substream is disabled (video1.enabled = 0)."
      : d.rtsp_scheme + "://" + auth + rtspTarget + "/" + d.rtsp_ch1);

    setText("#url-rtsp-mic",
      "Not available — timps serves no audio-only mount point. " +
      "Audio is carried as a track inside the streams above.");

    if (disabledWarn) disabledWarn.classList.toggle("d-none", d.rtsp_enabled !== 0);
  }

  function setText(sel, text) {
    var el = $(sel);
    if (el) el.textContent = text;
  }

  /* ---- load ---- */

  // The CGI is the required half (credentials + ports); /control is the
  // preferred-but-optional half (live mount points and which streams are
  // published). A dead streamer must therefore NOT blank the page: the CGI's
  // timps.conf fallbacks still produce correct URLs, so /control failing is
  // logged and ignored rather than surfaced as an error.
  function load() {
    busy(true, "Loading RTSP settings...");
    return fetch(CGI, { cache: "no-store", headers: { Accept: "application/json" } })
      .then(function (res) {
        if (!res.ok) throw new Error("Failed to load RTSP configuration (HTTP " + res.status + ")");
        return res.json();
      })
      .then(function (cfg) {
        if (cfg && cfg.error) throw new Error(cfg.error.message || "Failed to load RTSP configuration");
        return liveMountPoints().then(function (live) {
          state = {
            username: cfg.username || "",
            password: cfg.password || "",
            onvif_port: cfg.onvif_port || "80",
            rtsp_scheme: cfg.rtsp_scheme || "rtsp",
            rtsp_port: cfg.rtsp_port || "554",
            rtsp_ch0: live.ch0 || cfg.rtsp_ch0 || "ch0",
            rtsp_ch1: live.ch1 || cfg.rtsp_ch1 || "ch1",
            ch1_enabled: live.ch1_enabled,
            rtsp_enabled: typeof cfg.rtsp_enabled === "number" ? cfg.rtsp_enabled : 1,
          };
          if (usernameInput) usernameInput.value = state.username || "(auth disabled)";
          if (passwordInput) passwordInput.value = state.password || "";
          renderUrls(state);
        });
      })
      .catch(function (err) {
        console.error("[config-rtsp] load failed:", err);
        toast("danger", err.message || "Unable to load RTSP configuration.");
        ["#url-onvif", "#url-rtsp-main", "#url-rtsp-sub", "#url-rtsp-mic"].forEach(function (s) {
          setText(s, "Unavailable");
        });
      })
      .then(function () { busy(false); });
  }

  // videoN.rtsp_path / videoN.enabled straight off the running daemon. Never
  // rejects - resolves {} when timps is unreachable so load() falls back to
  // the config-file values from the CGI.
  function liveMountPoints() {
    if (!window.timpsApi) return Promise.resolve({});
    return window.timpsApi.get().then(function (json) {
      var v = json && json.video;
      if (!v) return {};
      var v0 = v[0] || v["0"] || {};
      var v1 = v[1] || v["1"] || {};
      return {
        ch0: v0.rtsp_path ? String(v0.rtsp_path).replace(/^\//, "") : "",
        ch1: v1.rtsp_path ? String(v1.rtsp_path).replace(/^\//, "") : "",
        ch1_enabled: v1.enabled === undefined ? undefined : v1.enabled !== 0,
      };
    }).catch(function (err) {
      console.warn("[config-rtsp] /control unreachable, using timps.conf values:", err);
      return {};
    });
  }

  /* ---- save ---- */

  function save(password) {
    busy(true, "Saving RTSP settings...");
    return fetch(CGI, {
      method: "POST",
      cache: "no-store",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ password: password }),
    })
      .then(function (res) {
        return res.json().catch(function () { return {}; }).then(function (body) {
          if (!res.ok || (body && body.error)) {
            throw new Error((body && body.error && body.error.message) ||
              "Failed to update password (HTTP " + res.status + ")");
          }
          return body;
        });
      })
      .then(function () {
        toast("success", "RTSP/ONVIF password updated. The streamer and ONVIF services were restarted.", 8000);
        // Render the new credential immediately. Re-reading from the camera is
        // pointless for several seconds: the CGI just restarted timps, so
        // /control refuses connections until it is back up, and a failed reload
        // would replace a correct page with "Unavailable".
        if (state) {
          state.password = password;
          renderUrls(state);
        }
        if (passwordInput) passwordInput.value = password;
      })
      .catch(function (err) {
        console.error("[config-rtsp] save failed:", err);
        toast("danger", err.message || "Failed to update password.");
      })
      .then(function () { busy(false); });
  }

  /* ---- wiring ---- */

  if (form) {
    form.addEventListener("submit", function (ev) {
      ev.preventDefault();
      var pw = passwordInput ? passwordInput.value.trim() : "";
      if (!pw) { toast("warning", "Please provide a password."); return; }
      if (pw.length < 4) { toast("warning", "Password must be at least 4 characters."); return; }
      save(pw);
    });
  }

  if (reloadButton) {
    reloadButton.addEventListener("click", function () {
      reloadButton.disabled = true;
      load().then(function () { reloadButton.disabled = false; });
    });
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
