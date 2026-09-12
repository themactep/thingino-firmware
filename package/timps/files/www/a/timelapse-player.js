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
  var frames = [];    // [{f, s}] of curSeq, ascending
  var idx = 0;        // frame on screen
  var playing = false;
  var timer = null;
  var prefetched = {}; // idx -> Image, kept only as a sliding window
  var intervalS = 0;   // timelapse.interval_s, for the "x real time" hint

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

  function relPath(i) {
    var f = frames[i] && frames[i].f;
    if (!f) return "";
    return curSeq === "." ? f : curSeq + "/" + f;
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

  // How much faster than life this plays: one frame is interval_s of real
  // time, so N fps compresses N*interval_s seconds into one second.
  function speedHint() {
    if (!frames.length) { hintEl.innerHTML = "&nbsp;"; return; }
    var bits = [frames.length + " frame" + (frames.length === 1 ? "" : "s")];
    if (frames.length === 1) {
      bits.push("nothing to animate - showing it as a still");
    } else if (intervalS > 0) {
      var factor = Math.round(fps() * intervalS);
      var span = (frames.length - 1) * intervalS;
      bits.push("~" + factor + "x real time");
      bits.push("covering ~" + Math.round(span / 60) + " min in " +
        Math.round((frames.length - 1) / fps()) + " s");
    }
    hintEl.textContent = bits.join(" · ");
  }

  function loadSeq(seq) {
    setPlaying(false);
    curSeq = seq;
    prefetched = {};
    if (!seq) { setEmpty("Select a sequence."); return; }
    emptyEl.hidden = false;
    emptyEl.textContent = "Loading frames…";
    frameEl.hidden = true;
    fetch(CGI + "?seq=" + encodeURIComponent(seq), { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (data) {
        // sort by name rather than trusting the listing order: the default
        // template makes the name sort BE the chronological order
        frames = (data.frames || []).slice().sort(function (a, b) {
          return a.f < b.f ? -1 : a.f > b.f ? 1 : 0;
        });
        if (!frames.length) {
          setEmpty("This folder holds no shots (it may have just been pruned). Try Reload.");
          return;
        }
        idx = 0;
        scrubEl.max = String(frames.length - 1);
        scrubEl.disabled = frames.length < 2;
        playBtn.disabled = frames.length < 2;
        emptyEl.hidden = true;
        speedHint();
        showFrame(0);
        if (window.location.hash !== "#seq=" + seq)
          window.history.replaceState(null, "", "#seq=" + seq);
      })
      .catch(function (e) {
        setEmpty("Failed to list frames: " + (e.message || e));
      });
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
        // deep link (#seq=20260912/09) wins, else the newest folder
        var want = /^#seq=(.+)$/.exec(window.location.hash);
        var pick = want ? decodeURIComponent(want[1]) : "";
        var known = seqs.some(function (s) { return s.seq === pick; });
        if (!known) pick = seqs[seqs.length - 1].seq;
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
