(function () {
  "use strict";

  var DEFAULT_PORT = 8880;
  var info = null; // cached {token, port} from /x/timps-token.cgi
  var infoPending = null; // in-flight token fetch (dedup)
  var controlCache = null; // last successful GET /control JSON (for caps())

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
            scheme: data && data.scheme ? String(data.scheme) : "",
          };
          return info;
        });
    }
    return infoPending;
  }

  // http.https is a tri-state; timps-token.cgi reports it as "scheme".
  function schemeOf(i) {
    if (!i) return "http";
    if (i.scheme === "both") {
      return window.location.protocol === "https:" ? "https" : "http";
    }
    if (i.scheme === "https" || i.scheme === "http") return i.scheme;
    return i.tls ? "https" : "http";
  }

  function base() {
    var host = window.location.hostname || "127.0.0.1";
    if (host.indexOf(":") >= 0 && host.charAt(0) !== "[") host = "[" + host + "]"; // IPv6
    return schemeOf(info) + "://" + host + ":" + (info ? info.port : DEFAULT_PORT);
  }

  function request(method, body, retried, query) {
    return fetchInfo(false).then(function (i) {
      var opts = { method: method, cache: "no-store", headers: {} };
      if (i.token) opts.headers["X-Timps-Token"] = i.token;
      if (body !== undefined) {
        opts.headers["Content-Type"] = "application/json";
        opts.body = JSON.stringify(body);
      }
      return fetch(base() + "/control" + (query || ""), opts).then(function (res) {
        if ((res.status === 401 || res.status === 403) && !retried) {
          return fetchInfo(true).then(function () {
            return request(method, body, true, query);
          });
        }
        return res.json().catch(function () { return {}; }).then(function (json) {
          if (!res.ok) {
            var reason = json && typeof json.reason === "string" ? json.reason : "";
            // Pre-split daemons answer 422 to both failures with no "reason";
            // fall back to the counters only then (never on a current build).
            if (!reason && res.status === 422)
              reason = json.rejected > 0 ? "values_rejected" : "unknown_fields";
            var msg = "timps /control HTTP " + res.status;
            if (reason === "values_rejected" || res.status === 409)
              msg = "the streamer refused the value (empty/invalid); nothing was applied";
            else if (reason === "unknown_fields" || res.status === 422)
              msg = "no setting in this request is known to this timps build; nothing was applied";
            else if (reason === "not_json" || res.status === 400)
              msg = "malformed /control request (client bug); nothing was applied";
            else if (reason === "oom" || res.status === 503)
              msg = "the streamer is out of memory; nothing was applied - try again shortly";
            var err = new Error(msg);
            err.status = res.status;
            err.reason = reason;   // pages that need to branch should use THIS
            err.result = json;
            throw err;
          }
          return json;
        });
      });
    });
  }

  function flattenInto(out, prefix, v) {
    if (v !== null && typeof v === "object") {
      Object.keys(v).forEach(function (k) {
        flattenInto(out, prefix + "." + k, v[k]);
      });
    } else {
      out[prefix] = v;
    }
  }
  function flattenBody(obj) {
    var out = {};
    Object.keys(obj || {}).forEach(function (sec) {
      var v = obj[sec];
      if (v === null || typeof v !== "object") { out[sec] = v; return; }
      Object.keys(v).forEach(function (k) {
        var pfx = (sec === "video" || sec === "privacy") ? sec + k : sec + "." + k;
        flattenInto(out, pfx, v[k]);
      });
    });
    return out;
  }

  // entries of result.applied whose EFFECTIVE (post-clamp) value differs from what this POST sent.
  function computeCorrections(body, result) {
    if (!result || !result.applied) return null;
    var sent = flattenBody(body);
    var out = null;
    Object.keys(result.applied).forEach(function (key) {
      if (!(key in sent)) return;
      var a = result.applied[key], s = sent[key];
      var an = Number(a), sn = Number(s);
      var same = (isFinite(an) && isFinite(sn) && String(a) !== "" && String(s) !== "")
        ? an === sn
        : String(s) === String(a);
      if (!same) { out = out || {}; out[key] = a; }
    });
    return out;
  }

  function takeCorrections(r) {
    if (!r || !r.corrections || r._corrShown) return null;
    r._corrShown = true;
    return r.corrections;
  }

  // shared wording for a corrections map.
  function correctionsText(corr) {
    return Object.keys(corr).map(function (k) {
      return k.split(".").pop().replace(/_/g, " ") +
        " was outside the allowed range - the streamer applied " + corr[k];
    }).join(". ");
  }

  function get() {
    return request("GET").then(function (json) {
      controlCache = json;
      return json;
    });
  }

  function set(obj) {
    return request("POST", obj).then(function (r) {
      if (r && typeof r === "object") r.corrections = computeCorrections(obj, r);
      return r;
    });
  }

  // merge rapid set() calls (slider drags) into one POST per quiet period.
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

  function statsExtra() {
    return request("GET", undefined, false, "?stats=1");
  }

  // who streams what: [{ip, port, proto, chn, since_s, kbps}]
  function clients() {
    return request("GET", undefined, false, "?clients=1");
  }

  function dnHistory(opts) {
    var q = "?dn_history=1";
    if (opts && opts.last > 0) q += "&last=" + (opts.last | 0);
    else if (opts && opts.since !== undefined) q += "&since=" + (opts.since >>> 0);
    if (opts && opts.max > 0) q += "&max=" + (opts.max | 0);
    return request("GET", undefined, false, q);
  }

  function events(streams, onEvent, onError) {
    var es = null, closed = false, down = false;
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
        es.onopen = function () {
          // after a streamer restart: tell the page (preview reconnect etc.)
          if (down) { down = false; document.dispatchEvent(new Event("timps-back")); }
        };
        types.forEach(function (t) {
          es.addEventListener(t, function (ev) {
            var data = null;
            try { data = JSON.parse(ev.data); } catch (e) { /* keep null */ }
            if (onEvent) onEvent(t, data);
          });
        });
        es.onerror = function (err) {
          if (closed) return;
          stop();
          down = true;
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
    takeCorrections: takeCorrections,
    correctionsText: correctionsText,
    caps: caps,
    statsExtra: statsExtra,
    clients: clients,
    dnHistory: dnHistory,
    events: events,
  };
})();
