/* timelapse-player.js - play back the timps timelapse shots listed by
 * /x/json-timelapse.cgi (a filesystem helper) as a client-side slideshow.
 *
 * There is no video here and deliberately so: the shots are individual JPEGs
 * on the SD card, and muxing them into a clip would mean an encoder pass on a
 * camera SoC. Playback is an <img> src swap driven by a timer, which costs the
 * camera nothing beyond serving the files.
 *
 * Two things keep that workable for a folder holding thousands of frames:
 *   - only the frame NAMES are fetched up front (one CGI call per folder, no
 *     per-file stat on the camera), never the images;
 *   - the images are pulled one at a time, with a LOOKAHEAD-frame prefetch
 *     into the browser's HTTP cache (the CGI marks shots immutable, so the
 *     src swap that follows is a cache hit, not a second trip to the SD card).
 * Nothing is ever held in the DOM except the single <img> being shown.
 *
 * Dependency-free, same shape as a/recordings.js. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-timelapse-player") return;

  var CGI = "/x/json-timelapse.cgi";
  var LOOKAHEAD = 3;       // frames prefetched ahead of the one on screen
  var MIN_DELAY_MS = 20;   // ceiling of ~50 fps, whatever the select says
  // Whole-day playback stitches one day's hour folders together by asking the
  // per-folder endpoint for each of them. Kept to the same in-flight budget as
  // the JPEG look-ahead: every call forks a shell and an `ls` on the camera,
  // and 24 of those at once for a week-old tree is a needless spike. Three
  // keeps the wall time at ~8 rounds of a cheap listing.
  var DAY_CONCURRENCY = 3;
  // marks a picker row / deep link as "the whole day", not a folder rel. A
  // bare YYYYMMDD is itself a legal folder rel (a name template may write one
  // folder per day), so day mode needs a namespace of its own.
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

  var seqs = [];      // [{seq, frames}] from the index
  var curSeq = "";    // folder currently loaded ("." = the tree root)
  var frames = [];    // [{f, s, d}] ascending; d is the folder each frame is in
  var idx = 0;        // frame on screen
  var playing = false;
  var timer = null;
  var prefetched = {}; // idx -> Image, kept only as a sliding window
  var intervalS = 0;   // timelapse.interval_s, for the "x real time" hint
  var hintExtra = "";  // day-mode note appended to the speed hint (skipped folders)
  var loadGen = 0;     // bumped per pick, so a slow load can't land after a newer one

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[timelapse-player]", type + ":", msg);
  }

  // "20260912T093000.jpg" -> "2026-09-12 09:30:00". Falls back to the bare
  // name when the shot was written with a non-default name template.
  function stampOf(name) {
    var m = /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/.exec(name);
    if (!m) return name.replace(/\.jpe?g$/i, "");
    return m[1] + "-" + m[2] + "-" + m[3] + " " + m[4] + ":" + m[5] + ":" + m[6];
  }

  // Same stamp, as milliseconds since epoch - null when the name carries none
  // (non-default template). Used to measure the REAL span a frame list
  // covers, since frame count * interval_s silently assumes zero gaps and is
  // wrong across a day-mode folder boundary or a missed capture.
  function frameEpochMs(name) {
    var m = /(\d{4})(\d{2})(\d{2})T(\d{2})(\d{2})(\d{2})/.exec(name);
    if (!m) return null;
    return Date.UTC(+m[1], +m[2] - 1, +m[3], +m[4], +m[5], +m[6]);
  }

  // "20260912/09" -> "2026-09-12 09:00", "20260912" -> "2026-09-12",
  // "." -> the tree root. Anything else is shown verbatim.
  function seqLabel(seq) {
    if (seq === ".") return "(timelapse folder root)";
    var m = /^(\d{4})(\d{2})(\d{2})(?:\/(\d{2}))?$/.exec(seq);
    if (!m) return seq;
    var d = m[1] + "-" + m[2] + "-" + m[3];
    return m[4] ? d + " " + m[4] + ":00" : d;
  }

  // day bucket for the <optgroup>, so a week of hour folders reads as seven
  // groups of 24 rather than 168 flat rows
  function dayOf(seq) {
    var m = /^(\d{4})(\d{2})(\d{2})(?:\/|$)/.exec(seq);
    return m ? m[1] + "-" + m[2] + "-" + m[3] : "Other";
  }

  // raw day bucket ("20260912/09" -> "20260912"), "" for a folder whose name
  // the default template did not produce - those get no whole-day row.
  function dayKeyOf(seq) {
    var m = /^(\d{8})(?:\/|$)/.exec(seq);
    return m ? m[1] : "";
  }

  // every indexed folder of one day, ascending (= chronological under the
  // default template). This is the same index the <optgroup>s are built from.
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

  // Each frame carries the folder it was listed from, so a merged whole-day
  // list resolves every frame against ITS OWN hour rather than one shared
  // prefix. Single-folder mode tags them all with that one folder.
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

  // Warm the browser cache for the next few frames. References are dropped
  // as the window slides, so at most LOOKAHEAD decoded images are held alive;
  // the cached HTTP responses outlive them, which is the point.
  function prefetch(from) {
    if (!frames.length) return;
    var keep = {}, i, k;
    for (k = 0; k < LOOKAHEAD; k++) {
      i = from + k;
      if (i >= frames.length) {
        if (!loopEl.checked) break;
        i = i % frames.length;
      }
      keep[i] = true;
      if (!prefetched[i]) {
        var im = new Image();
        im.src = frameUrl(i);
        prefetched[i] = im;
      }
    }
    Object.keys(prefetched).forEach(function (key) {
      if (!keep[key]) delete prefetched[key];
    });
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

  // Show frame i and call done() once its load settles (either way). Pacing
  // playback off the settle rather than off a bare interval keeps the frame
  // rate honest on a slow link instead of queueing up requests.
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
    if (frameEl.getAttribute("src") === url) {
      // same URL (single-frame folder, or a re-show): no load event would
      // fire, so settle on our own instead of stalling the loop
      setTimeout(settle, 0);
    } else {
      frameEl.src = url;
      frameEl.hidden = false;
      // a cache hit can already be complete here and some browsers then fire
      // no further load event on this element
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

  // Coverage + the dialed-in compression - NOT a promise of actual playback
  // duration. Real throughput is bounded by the camera's SD card / network
  // (measured ~1 fps on a T23 over WiFi at a 10 fps setting), so "N fps for
  // M frames finishes in M/N seconds" does not hold; only the span covered
  // and the nominal ratio the fps control is set to are stated.
  function speedHint() {
    if (!frames.length) { hintEl.innerHTML = "&nbsp;"; return; }
    var bits = [frames.length + " frame" + (frames.length === 1 ? "" : "s")];
    if (frames.length === 1) {
      bits.push("nothing to animate - showing it as a still");
    } else {
      // Real span from the first/last frame's OWN timestamps when the name
      // carries one; falls back to the frame-count*interval_s estimate only
      // when it doesn't (non-default name template - no better source then).
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

  // One folder's frames, names only, tagged with the folder they came from.
  // The whole-day loader calls this once per hour folder - the endpoint and
  // its response are exactly what single-folder playback has always used.
  function fetchSeq(seq) {
    return fetch(CGI + "?seq=" + encodeURIComponent(seq), { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (data) {
        // sort by name rather than trusting the listing order: the default
        // template makes the name sort BE the chronological order
        return (data.frames || []).slice().sort(function (a, b) {
          return a.f < b.f ? -1 : a.f > b.f ? 1 : 0;
        }).map(function (fr) {
          return { f: fr.f, s: fr.s, d: seq };
        });
      });
  }

  // The single hand-off into the playback state machine: both loaders end
  // here, and nothing past this point knows whether the list came from one
  // folder or from a day's worth of them.
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

  // Whole day: the day's hour folders, fetched through the SAME per-folder
  // endpoint and concatenated in hour order. No server-side recursion, and
  // one unreadable hour costs that hour only - the rest of the day still
  // plays, with the gap named in the hint and a toast.
  function loadDay(key, gen) {
    var list = daySeqs(key);
    if (!list.length) {
      setEmpty("No folders left for that day - they may have just been pruned. Try Reload.");
      return;
    }
    curSeq = "";
    frameEl.hidden = true;
    emptyEl.hidden = false;

    var parts = new Array(list.length);  // by slot, so hour order survives
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
              if (gen !== loadGen) return;  // a newer pick owns the player now
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
    // newest first in the picker (the index comes back ascending): the shots
    // someone opens this page for are almost always the most recent ones
    seqs.slice().reverse().forEach(function (s) {
      var day = dayOf(s.seq);
      if (day !== groupName) {
        groupName = day;
        group = document.createElement("optgroup");
        group.label = day;
        seqEl.appendChild(group);
        // First row of the group plays the day end to end. Offered only when
        // there is more than one folder to stitch - with a single folder the
        // plain row below already IS the whole day.
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
      // textContent, not innerHTML: folder names come off the SD card and
      // must never be interpreted as HTML
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
        // A deep link wins over the newest folder: #seq=20260912/09 for one
        // folder, #day=20260912 for the whole day. Two keys rather than
        // "#seq= with no /HH", because a bare YYYYMMDD can itself be a real
        // folder rel and the two would then be indistinguishable.
        var pick = "";
        var wantDay = /^#day=(.+)$/.exec(window.location.hash);
        var wantSeq = /^#seq=(.+)$/.exec(window.location.hash);
        if (wantDay) {
          var key = decodeURIComponent(wantDay[1]);
          var members = daySeqs(key);
          // a day pruned down to one folder has no whole-day row any more -
          // resume on the folder that is left rather than on the newest day
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

    // interval_s drives the "x real time" hint; free_mb is a nice extra.
    // Best effort only - the player works without timps answering at all.
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
      }).catch(function () { /* hint stays generic */ });
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
  // scrubbing jumps without stopping: the loop picks up from the new index
  scrubEl.addEventListener("input", function () {
    showFrame(parseInt(scrubEl.value, 10) || 0);
  });

  document.addEventListener("keydown", function (ev) {
    var t = ev.target;
    // never swallow keys aimed at a control (the fps/sequence selects, the
    // scrub slider) or at any other input
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

  // a backgrounded tab throttles timers to ~1/s, which would silently turn
  // playback into a crawl and keep hammering the camera - stop instead
  document.addEventListener("visibilitychange", function () {
    if (document.hidden && playing) setPlaying(false);
  });

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
