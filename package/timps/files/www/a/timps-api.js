/* timps-api.js - tiny dependency-free browser client for the timps streamer's
 * native HTTP API (GET/POST /control, GET /events SSE). Pages talk DIRECTLY
 * to timps on its own port instead of going through local bridge CGIs.
 *
 * Auth: /x/timps-token.cgi (WebUI-session protected) hands out the per-boot
 * timps token as {"token":"...","port":8880}. fetch() sends it as the
 * X-Timps-Token header; EventSource cannot set headers, so /events gets it
 * as ?token=. The token changes on every camera reboot: one transparent
 * re-fetch + retry is done on a 401/403. If the token endpoint is
 * unreachable, requests are still attempted token-less (works on open timps
 * configs and from localhost).
 */
(function () {
  "use strict";

  var DEFAULT_PORT = 8880;
  var info = null; // cached {token, port} from /x/timps-token.cgi
  var infoPending = null; // in-flight token fetch (dedup)
  var controlCache = null; // last successful GET /control JSON (for caps())

  // fetch {token, port} once and memoize; force=true drops the cache
  // (used after a 401/403 - the camera may have rebooted with a new token).
  // Never rejects: on failure it resolves {token:"", port:DEFAULT_PORT}.
  function fetchInfo(force) {
    if (info && !force) return Promise.resolve(info);
    if (!infoPending) {
      infoPending = fetch("/x/timps-token.cgi", { cache: "no-store" })
        .then(function (res) { return res.ok ? res.json() : null; })
        .catch(function () { return null; })
        .then(function (data) {
          infoPending = null;
          info = {
            token: data && data.token ? String(data.token) : "",
            port: data && data.port ? parseInt(data.port, 10) : DEFAULT_PORT,
            tls: !!(data && data.tls),
          };
          return info;
        });
    }
    return infoPending;
  }

  function base() {
    var host = window.location.hostname || "127.0.0.1";
    if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") host = "[" + host + "]"; // IPv6
    var scheme = (info && info.tls) ? "https" : "http";
    return scheme + "://" + host + ":" + (info ? info.port : DEFAULT_PORT);
  }

  // one /control round trip with the token header; retries ONCE with a
  // freshly fetched token when the answer is 401/403 (rebooted camera).
  function request(method, body, retried) {
    return fetchInfo(false).then(function (i) {
      var opts = { method: method, cache: "no-store", headers: {} };
      if (i.token) opts.headers["X-Timps-Token"] = i.token;
      if (body !== undefined) {
        opts.headers["Content-Type"] = "application/json";
        opts.body = JSON.stringify(body);
      }
      return fetch(base() + "/control", opts).then(function (res) {
        if ((res.status === 401 || res.status === 403) && !retried) {
          return fetchInfo(true).then(function () {
            return request(method, body, true);
          });
        }
        if (!res.ok) throw new Error("timps /control HTTP " + res.status);
        return res.json().catch(function () { return {}; });
      });
    });
  }

  function get() {
    return request("GET").then(function (json) {
      controlCache = json;
      return json;
    });
  }

  function set(obj) {
    return request("POST", obj);
  }

  // merge rapid set() calls (slider drags) into one POST per quiet period.
  // Only image-style two-level objects are merged ({section:{key:val}}).
  // Every caller's promise settles with the outcome of the single flush.
  var debounceBuf = null, debounceTimer = null, debounceWaiters = [];
  function setDebounced(obj, ms) {
    if (!debounceBuf) debounceBuf = {};
    Object.keys(obj || {}).forEach(function (sec) {
      if (obj[sec] && typeof obj[sec] === "object") {
        debounceBuf[sec] = debounceBuf[sec] || {};
        Object.keys(obj[sec]).forEach(function (k) {
          debounceBuf[sec][k] = obj[sec][k];
        });
      } else {
        debounceBuf[sec] = obj[sec];
      }
    });
    if (debounceTimer) clearTimeout(debounceTimer);
    return new Promise(function (resolve, reject) {
      debounceWaiters.push({ resolve: resolve, reject: reject });
      debounceTimer = setTimeout(function () {
        var payload = debounceBuf, waiters = debounceWaiters;
        debounceBuf = null;
        debounceTimer = null;
        debounceWaiters = [];
        set(payload).then(
          function (r) { waiters.forEach(function (w) { w.resolve(r); }); },
          function (e) { waiters.forEach(function (w) { w.reject(e); }); },
        );
      }, ms === undefined ? 150 : ms);
    });
  }

  // caps object from a cached GET /control (fetches once when not cached)
  function caps() {
    if (controlCache && controlCache.caps)
      return Promise.resolve(controlCache.caps);
    return get().then(function (json) { return json.caps || {}; });
  }

  // /events SSE: streams = "motion,daynight,stats" (or "" for all).
  // onEvent(type, data) gets each parsed event; onError(err) any failure.
  // Auto-pauses while the tab is hidden and resumes on visibilitychange.
  // Returns {close()}.
  function events(streams, onEvent, onError) {
    var es = null, closed = false;
    var types = String(streams || "motion,daynight,stats")
      .split(",").map(function (s) { return s.trim(); })
      .filter(Boolean);

    function open() {
      fetchInfo(false).then(function (i) {
        if (closed || document.hidden) return;
        var url = base() + "/events?stream=" + encodeURIComponent(types.join(","));
        if (i.token) url += "&token=" + encodeURIComponent(i.token);
        try { es = new EventSource(url); } catch (e) {
          if (onError) onError(e);
          return;
        }
        types.forEach(function (t) {
          es.addEventListener(t, function (ev) {
            var data = null;
            try { data = JSON.parse(ev.data); } catch (e) { /* keep null */ }
            if (onEvent) onEvent(t, data);
          });
        });
        es.onerror = function (err) {
          // token may be stale after a reboot: drop the cache so the
          // browser's automatic EventSource reconnect... cannot change the
          // URL, so reopen ourselves with a fresh token instead.
          if (closed) return;
          stop();
          if (onError) onError(err);
          fetchInfo(true).then(function () {
            if (!closed && !document.hidden) setTimeout(open, 3000);
          });
        };
      });
    }

    function stop() {
      if (es) { es.close(); es = null; }
    }

    function onVis() {
      if (document.hidden) stop();
      else if (!es && !closed) open();
    }
    document.addEventListener("visibilitychange", onVis);
    open();

    return {
      close: function () {
        closed = true;
        document.removeEventListener("visibilitychange", onVis);
        stop();
      },
    };
  }

  window.timpsApi = {
    base: base,
    token: function () {
      return fetchInfo(false).then(function (i) { return i.token; });
    },
    get: get,
    set: set,
    setDebounced: setDebounced,
    caps: caps,
    events: events,
  };
})();
