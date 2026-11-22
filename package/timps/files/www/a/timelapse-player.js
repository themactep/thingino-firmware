(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-timelapse-player") return;

  var CGI = "/x/json-timelapse.cgi";
  var LOOKAHEAD = 8;
  var MAX_INFLIGHT = 4;
  var MIN_DELAY_MS = 20;
  var DAY_CONCURRENCY = 3;
  var DAY_PREFIX = "day:";

  var $ = function (id) { return document.getElementById(id); };

  var seqEl = $("tlp-seq");
  var fpsEl = $("tlp-fps");
  var loopEl = $("tlp-loop");
  var frameEl = $("tlp-frame");
  var stampEl = $("tlp-stamp");
  var emptyEl = $("tlp-empty");
  var counterEl = $("tlp-counter");
  var scrubEl = $("tlp-scrub");
  var hintEl = $("tlp-hint");
  var infoEl = $("tlp-info");
  var dlEl = $("tlp-dl");
  var playBtn = $("tlp-play");
  var playIcon = $("tlp-play-icon");
  var reloadBtn = $("tlp-reload");

  var seqs = [];
  var curSeq = "";
  var frames = [];
  var idx = 0;
  var playing = false;
  var timer = null;
  var prefetched = {};
  var pfWanted = {};
  var pfQueue = [];
  var pfInflight = 0;
  var intervalS = 0;
  var hintExtra = "";
  var loadGen = 0;

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[timelapse-player]", type + ":", msg);
  }

  function stampOf(name) {
    var m = /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/.exec(name);
    if (!m) return name.replace(/\.jpe?g$/i, "");
    return m[1] + "-" + m[2] + "-" + m[3] + " " + m[4] + ":" + m[5] + ":" + m[6];
  }

  function frameEpochMs(name) {
    var m = /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/.exec(name);
    if (!m) return null;
    return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }

  function seqLabel(seq) {
    if (seq === ".") return "(timelapse folder root)";
    var m = /^(\d{4})(\d{2})(\d{2})(?:\/(\d{2}))?$/.exec(seq);
    if (!m) return seq;
    var d = m[1] + "-" + m[2] + "-" + m[3];
    return m[4] ? d + " " + m[4] + ":00" : d;
  }

  function dayOf(seq) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:\/|$)/.exec(seq);
    return m ? m[1] + "-" + m[2] + "-" + m[3] : "Other";
  }

  function dayKeyOf(seq) {
    var m = /^(\d{8})(?:\/|$)/.exec(seq);
    return m ? m[1] : "";
  }

  function daySeqs(key) {
    return seqs.filter(function (s) { return dayKeyOf(s.seq) === key; })
      .map(function (s) { return s.seq; })
      .sort();
  }

  function dayShots(key) {
    return seqs.reduce(function (n, s) {
      return dayKeyOf(s.seq) === key ? n + (s.frames || 0) : n;
    }, 0);
  }

  function relPath(i) {
    var fr = frames[i];
    if (!fr || !fr.f) return "";
    var d = fr.d == null ? curSeq : fr.d;
    return (!d || d === ".") ? fr.f : d + "/" + fr.f;
  }

  function frameUrl(i) {
    var rel = relPath(i);
    return rel ? CGI + "?file=" + encodeURIComponent(rel) : "";
  }

  function fps() {
    var v = parseFloat(fpsEl.value);
    return isFinite(v) && v > 0 ? v : 10;
  }

  function delayMs() {
    return Math.max(MIN_DELAY_MS, Math.round(1000 / fps()));
  }

  function pumpPrefetch() {
    while (pfInflight < MAX_INFLIGHT && pfQueue.length) {
      (function (i) {
        if (prefetched[i] || !pfWanted[i]) return;
        pfInflight++;
        var im = new Image();
        im.onload = im.onerror = function () {
          pfInflight--;
          if (prefetched[i] === im && !pfWanted[i]) delete prefetched[i];
          pumpPrefetch();
        };
        im.src = frameUrl(i);
        prefetched[i] = im;
      })(pfQueue.shift());
    }
  }

  function prefetch(from) {
    if (!frames.length) return;
    var i, k;
    pfWanted = {};
    for (k = 0; k < LOOKAHEAD; k++) {
      i = from + k;
      if (i >= frames.length) {
        if (!loopEl.checked) break;
        i = i % frames.length;
      }
      pfWanted[i] = true;
      if (!prefetched[i] && pfQueue.indexOf(i) === -1) pfQueue.push(i);
    }
    pfQueue = pfQueue.filter(function (i) { return pfWanted[i]; });
    Object.keys(prefetched).forEach(function (key) {
      if (!pfWanted[key] && prefetched[key].complete) delete prefetched[key];
    });
    pumpPrefetch();
  }

  function updateMeta() {
    var n = frames.length;
    counterEl.textContent = (n ? idx + 1 : 0) + " / " + n;
    scrubEl.value = String(idx);
    if (n) {
      stampEl.hidden = false;
      stampEl.textContent = stampOf(frames[idx].f);
      dlEl.href = frameUrl(idx);
      dlEl.setAttribute("download", relPath(idx).replace(/\//g, "_"));
      dlEl.classList.remove("disabled");
    } else {
      stampEl.hidden = true;
      dlEl.removeAttribute("href");
      dlEl.classList.add("disabled");
    }
  }

  function showFrame(i, done) {
    if (!frames.length) { if (done) done(); return; }
    var n = frames.length;
    idx = ((i % n) + n) % n;
    var url = frameUrl(idx);
    var settled = false;
    function settle() {
      if (settled) return;
      settled = true;
      if (done) done();
    }
    frameEl.onload = settle;
    frameEl.onerror = settle;
    frameEl.hidden = false;
    if (frameEl.getAttribute("src") === url) {
      setTimeout(settle, 0);
    } else {
      frameEl.src = url;
      // a cache hit may already be complete and fire no further load event
      if (frameEl.complete) setTimeout(settle, 0);
    }
    updateMeta();
    prefetch(idx + 1);
  }

  function setPlaying(on) {
    playing = !!on && frames.length > 1;
    if (timer) { clearTimeout(timer); timer = null; }
    playIcon.className = playing ? "bi bi-pause-fill" : "bi bi-play-fill";
    playBtn.title = playing ? "Pause (Space)" : "Play (Space)";
    if (playing) tick();
  }

  function tick() {
    if (!playing) return;
    var t0 = Date.now();
    var next = idx + 1;
    if (next >= frames.length) {
      if (!loopEl.checked) { setPlaying(false); return; }
      next = 0;
    }
    showFrame(next, function () {
      if (!playing) return;
      timer = setTimeout(tick, Math.max(0, delayMs() - (Date.now() - t0)));
    });
  }

  function setEmpty(msg) {
    setPlaying(false);
    frames = [];
    prefetched = {};
    pfWanted = {};
    pfQueue = [];
    idx = 0;
    frameEl.hidden = true;
    frameEl.removeAttribute("src");
    emptyEl.hidden = false;
    emptyEl.textContent = msg;
    scrubEl.max = "0";
    scrubEl.disabled = true;
    playBtn.disabled = true;
    updateMeta();
  }

  function speedHint() {
    if (!frames.length) { hintEl.innerHTML = "&nbsp;"; return; }
    var bits = [frames.length + " frame" + (frames.length === 1 ? "" : "s")];
    if (frames.length === 1) {
      bits.push("nothing to animate - showing it as a still");
    } else {
      var t0 = frameEpochMs(frames[0].f), t1 = frameEpochMs(frames[frames.length - 1].f);
      var spanS = (t0 != null && t1 != null) ? (t1 - t0) / 1000
        : (intervalS > 0 ? (frames.length - 1) * intervalS : 0);
      if (spanS > 0) bits.push("covering ~" + Math.round(spanS / 60) + " min of footage");
      if (intervalS > 0)
        bits.push("target ~" + Math.round(fps() * intervalS) + "x real time at " + fps() + " fps");
    }
    if (hintExtra) bits.push(hintExtra);
    hintEl.textContent = bits.join(" · ");
  }

  function fetchSeq(seq) {
    return fetch(CGI + "?seq=" + encodeURIComponent(seq), { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (data) {
        return (data.frames || []).slice().sort(function (a, b) {
          return a.f < b.f ? -1 : a.f > b.f ? 1 : 0;
        }).map(function (fr) {
          return { f: fr.f, s: fr.s, d: seq };
        });
      });
  }

  function applyFrames(list, emptyMsg, hash) {
    frames = list;
    if (!frames.length) { setEmpty(emptyMsg); return; }
    idx = 0;
    scrubEl.max = String(frames.length - 1);
    scrubEl.disabled = frames.length < 2;
    playBtn.disabled = frames.length < 2;
    emptyEl.hidden = true;
    speedHint();
    showFrame(0);
    if (window.location.hash !== hash)
      window.history.replaceState(null, "", hash);
  }

  function loadSeq(seq) {
    setPlaying(false);
    prefetched = {};
    pfWanted = {};
    pfQueue = [];
    hintExtra = "";
    curSeq = seq;
    var gen = ++loadGen;
    if (!seq) { setEmpty("Select a sequence."); return; }
    if (seq.indexOf(DAY_PREFIX) === 0) {
      loadDay(seq.slice(DAY_PREFIX.length), gen);
      return;
    }
    emptyEl.hidden = false;
    emptyEl.textContent = "Loading frames…";
    frameEl.hidden = true;
    fetchSeq(seq)
      .then(function (list) {
        if (gen !== loadGen) return;
        applyFrames(list,
          "This folder holds no shots (it may have just been pruned). Try Reload.",
          "#seq=" + seq);
      })
      .catch(function (e) {
        if (gen !== loadGen) return;
        setEmpty("Failed to list frames: " + (e.message || e));
      });
  }

  function loadDay(key, gen) {
    var list = daySeqs(key);
    if (!list.length) {
      setEmpty("No folders left for that day - they may have just been pruned. Try Reload.");
      return;
    }
    curSeq = "";
    frameEl.hidden = true;
    emptyEl.hidden = false;

    var parts = new Array(list.length);
    var failed = [];
    var done = 0, next = 0, inflight = 0;

    function progress() {
      emptyEl.textContent = "Loading " + seqLabel(key) + " - folder " +
        done + " / " + list.length + "…";
    }

    function finish() {
      var all = [], i;
      for (i = 0; i < list.length; i++)
        if (parts[i] && parts[i].length) all = all.concat(parts[i]);
      var ok = list.length - failed.length;
      hintExtra = "whole day, " + ok + " folder" + (ok === 1 ? "" : "s");
      if (failed.length) {
        failed.sort();
        var note = "skipped " + failed.length + " unreadable folder" +
          (failed.length === 1 ? "" : "s") + " (" + failed.join(", ") + ")";
        hintExtra += " · " + note;
        toast("warning", "Whole day: " + note, 6000);
      }
      applyFrames(all, failed.length === list.length
        ? "None of that day's folders could be listed. Try Reload."
        : "That day's folders hold no shots any more. Try Reload.",
        "#day=" + key);
    }

    function pump() {
      while (inflight < DAY_CONCURRENCY && next < list.length) {
        (function (slot, seq) {
          inflight++;
          fetchSeq(seq)
            .then(function (fr) { parts[slot] = fr; })
            .catch(function () { parts[slot] = []; failed.push(seq); })
            .then(function () {
              inflight--;
              done++;
              if (gen !== loadGen) return;
              progress();
              if (done === list.length) finish();
              else pump();
            });
        })(next, list[next]);
        next++;
      }
    }

    progress();
    pump();
  }

  function renderSeqs() {
    seqEl.innerHTML = "";
    var group = null, groupName = null;
    seqs.slice().reverse().forEach(function (s) {
      var day = dayOf(s.seq);
      if (day !== groupName) {
        groupName = day;
        group = document.createElement("optgroup");
        group.label = day;
        seqEl.appendChild(group);
        var key = dayKeyOf(s.seq);
        var members = key ? daySeqs(key) : [];
        if (members.length > 1) {
          var all = document.createElement("option");
          all.value = DAY_PREFIX + key;
          all.textContent = "Whole day  (" + members.length + " folders, " +
            dayShots(key) + " shots)";
          group.appendChild(all);
        }
      }
      var opt = document.createElement("option");
      opt.value = s.seq;
      // textContent, not innerHTML: folder names come off the SD card
      opt.textContent = seqLabel(s.seq) + "  (" + s.frames +
        " shot" + (s.frames === 1 ? "" : "s") + ")";
      group.appendChild(opt);
    });
  }

  function load() {
    reloadBtn.disabled = true;
    emptyEl.hidden = false;
    emptyEl.textContent = "Scanning the timelapse folder…";
    fetch(CGI, { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (data) {
        seqs = data.seqs || [];
        if (infoEl) infoEl.textContent = data.base || "";
        if (!data.exists) {
          seqEl.innerHTML = '<option value="">No timelapse folder yet</option>';
          seqEl.disabled = true;
          setEmpty("Nothing recorded yet - " + (data.base || "the timelapse folder") +
            " does not exist. Enable the timelapse recorder in Settings and give it " +
            "one interval to write the first shot.");
          hintEl.innerHTML = "&nbsp;";
          return;
        }
        if (!seqs.length) {
          seqEl.innerHTML = '<option value="">No shots yet</option>';
          seqEl.disabled = true;
          setEmpty("The timelapse folder exists but holds no shots yet. " +
            "If the recorder was just enabled, wait one interval and hit Reload.");
          hintEl.innerHTML = "&nbsp;";
          return;
        }
        seqEl.disabled = false;
        renderSeqs();
        var pick = "";
        var wantDay = /^#day=(.+)$/.exec(window.location.hash);
        var wantSeq = /^#seq=(.+)$/.exec(window.location.hash);
        if (wantDay) {
          var key = decodeURIComponent(wantDay[1]);
          var members = daySeqs(key);
          if (members.length > 1) pick = DAY_PREFIX + key;
          else if (members.length === 1) pick = members[0];
        } else if (wantSeq) {
          var seq = decodeURIComponent(wantSeq[1]);
          if (seqs.some(function (s) { return s.seq === seq; })) pick = seq;
        }
        if (!pick) pick = seqs[seqs.length - 1].seq;
        seqEl.value = pick;
        loadSeq(pick);
      })
      .catch(function (e) {
        setEmpty("Failed to scan the timelapse folder: " + (e.message || e));
        toast("danger", "Timelapse listing failed: " + (e.message || e));
      })
      .finally(function () { reloadBtn.disabled = false; });

    if (window.timpsApi) {
      window.timpsApi.get().then(function (j) {
        var tl = j && j.timelapse;
        if (!tl) return;
        intervalS = parseInt(tl.interval_s, 10) || 0;
        if (infoEl) {
          var bits = [];
          if (intervalS > 0) bits.push("every " + intervalS + "s");
          bits.push(tl.enabled ? "recording" : "recorder off");
          if (tl.free_mb != null && tl.free_mb >= 0) bits.push(tl.free_mb + " MB free");
          infoEl.textContent = bits.join(" · ");
        }
        speedHint();
      }).catch(function () {});
    }
  }

  seqEl.addEventListener("change", function () { loadSeq(seqEl.value); });
  fpsEl.addEventListener("change", speedHint);
  playBtn.addEventListener("click", function () { setPlaying(!playing); });
  $("tlp-first").addEventListener("click", function () { setPlaying(false); showFrame(0); });
  $("tlp-last").addEventListener("click", function () { setPlaying(false); showFrame(frames.length - 1); });
  $("tlp-prev").addEventListener("click", function () { setPlaying(false); showFrame(idx - 1); });
  $("tlp-next").addEventListener("click", function () { setPlaying(false); showFrame(idx + 1); });
  reloadBtn.addEventListener("click", load);
  scrubEl.addEventListener("input", function () {
    showFrame(parseInt(scrubEl.value, 10) || 0);
  });

  document.addEventListener("keydown", function (ev) {
    var t = ev.target;
    if (t && /^(INPUT|SELECT|TEXTAREA)$/.test(t.tagName)) return;
    if (ev.ctrlKey || ev.altKey || ev.metaKey) return;
    switch (ev.key) {
      case " ": setPlaying(!playing); break;
      case "ArrowLeft": setPlaying(false); showFrame(idx - 1); break;
      case "ArrowRight": setPlaying(false); showFrame(idx + 1); break;
      case "Home": setPlaying(false); showFrame(0); break;
      case "End": setPlaying(false); showFrame(frames.length - 1); break;
      default: return;
    }
    ev.preventDefault();
  });

  document.addEventListener("visibilitychange", function () {
    if (document.hidden && playing) setPlaying(false);
  });

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
