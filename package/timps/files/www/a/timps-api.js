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
        // POST /control grades its answer (timps src/control.h, src/mp4/httpd.c).
        // Error bodies carry a machine-readable "reason"; 200 bodies are
        // unchanged byte-for-byte (that is the path a dragged slider posts on).
        //
        //   400 not_json        the body was not a JSON object - a bug in the
        //                       calling page, keep it loud
        //   422 unknown_fields  it parsed, but no field in it is known to THIS
        //                       build - the key NAMES are wrong for this binary
        //   409 values_rejected the names were right, every value was refused
        //   503 oom             the daemon could not allocate - not our fault
        //
        // Key off "reason", not off counter arithmetic. 422 and 409 are the
        // opposite advice and a client that confuses them loops forever:
        // retrying a 422 unchanged can never succeed (this binary will never
        // know that key), while a 409 is worth re-sending with valid values.
        // That is exactly why the daemon split them - see timps commit
        // "control: say what this build can do, and stop overloading 422".
        //
        // Every one of these carries the same {ok,accepted,changed,rejected}
        // body as a 200, so parse BEFORE deciding and hang the counters off the
        // error - a bare "HTTP 422" would send the user hunting for a network
        // problem that does not exist. A 200 with changed:0 stays a plain
        // success on purpose: the field already held the posted value (accepted
        // counts that write), and clamped writes are 200 too - clamping is the
        // documented contract, not an error.
        return res.json().catch(function () { return {}; }).then(function (json) {
          if (!res.ok) {
            var reason = json && typeof json.reason === "string" ? json.reason : "";
            // Fallback for daemons older than the split, which answer 422 to
            // BOTH failures and carry no "reason" at all. There the counters
            // are the only signal there has ever been, and rejected>0 does
            // discriminate correctly - so use it, but ONLY when the daemon did
            // not tell us. On a current build this branch never runs.
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

  // flatten one POST body into the daemon's config-key space - the same names
  // the response's "applied" echo uses: {image:{brightness}} ->
  // "image.brightness", {video:{0:{fps}}} -> "video0.fps" (config-file
  // spelling: the stream index fuses into the section), {osd0:{1:{text}}} ->
  // "osd0.1.text", {privacy:{0:{3:{x}}}} -> "privacy0.3.x". Only used to
  // look up what THIS client sent for a key the
  // daemon echoed, so a shape this flattening does not know simply misses the
  // lookup and produces no correction - never a false one.
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
        // video and privacy fuse the stream index INTO the section name in
        // the daemon's key space (video0.fps, privacy0.3.x) - a plain dotted
        // join would never match their echoes
        var pfx = (sec === "video" || sec === "privacy") ? sec + k : sec + "." + k;
        flattenInto(out, pfx, v[k]);
      });
    });
    return out;
  }

  // entries of result.applied whose EFFECTIVE (post-clamp) value differs from
  // what this POST sent - i.e. the daemon corrected the caller's value.
  // Numeric comparison when both sides parse as numbers (so true == "1" and
  // 60 == "60" are NOT corrections), string comparison otherwise. Returns
  // null when nothing differs.
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

  // one-shot toast gate: a debounced flush settles MANY waiters with the SAME
  // result object and each waiter runs the same page handler - without the
  // take-once semantics one clamped slider drag would toast once per queued
  // waiter. Element updates should read r.corrections directly instead
  // (setting the same value twice is harmless, missing it is not).
  function takeCorrections(r) {
    if (!r || !r.corrections || r._corrShown) return null;
    r._corrShown = true;
    return r.corrections;
  }

  // shared wording for a corrections map. Deliberately informational: a
  // clamped write SUCCEEDED (clamping is the documented contract), so pages
  // show this as "info", never as an error.
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
      // hang the correction diff off the result: the daemon echoes the
      // effective values of everything it CHANGED ("applied"), so a page can
      // put a clamped value straight back into its control - no follow-up
      // GET. Computed here rather than per caller so debounced writes compare
      // against the MERGED payload that actually went out. When the echo
      // overflowed (result.truncated) the diff may be incomplete - pages that
      // skip a reload based on it must check r.truncated themselves.
      if (r && typeof r === "object") r.corrections = computeCorrections(obj, r);
      return r;
    });
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
    takeCorrections: takeCorrections,
    correctionsText: correctionsText,
    caps: caps,
    events: events,
  };
})();
