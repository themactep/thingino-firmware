(function () {
  "use strict";

  const video = document.getElementById("fmp4-video");
  const statusEl = document.getElementById("fmp4-status");
  if (!video) return;

  const HTTP_PORT = 8080;
  let mediaSource = null;
  let sourceBuffer = null;
  let abortController = null;
  let channel = 1;
  let sessionId = 0;
  let runPromise = Promise.resolve();
  // Resolver of the active session's append pump, woken on teardown so the
  // pump does not stay parked on a promise that will never resolve.
  let pumpWake = null;

  const host = () => window.location.hostname || "localhost";
  const API_KEY_PROMISE = fetch("/x/api-key.cgi", { cache: "no-store" })
    .then((r) => (r.ok ? r.json() : { exists: false }))
    .then((d) => (d.exists && d.api_key ? d.api_key : ""))
    .catch(() => "");

  const streamUrl = async (ch) => {
    const key = await API_KEY_PROMISE;
    const qs = key ? "?token=" + encodeURIComponent(key) : "";
    return `http://${host()}:${HTTP_PORT}/ch${ch}.mp4${qs}`;
  };
  const setStatus = (text) => {
    if (statusEl) statusEl.textContent = text;
  };
  const hex = (v) => v.toString(16).toUpperCase().padStart(2, "0");

  function codecFromInit(u8) {
    let videoCodec = "avc1.42E01E";
    let hasAudio = false;
    for (let i = 0; i + 8 <= u8.length; i++) {
      if (
        u8[i] === 0x61 &&
        u8[i + 1] === 0x76 &&
        u8[i + 2] === 0x63 &&
        u8[i + 3] === 0x43
      ) {
        videoCodec = `avc1.${hex(u8[i + 5])}${hex(u8[i + 6])}${hex(u8[i + 7])}`;
      } else if (
        u8[i] === 0x6d &&
        u8[i + 1] === 0x70 &&
        u8[i + 2] === 0x34 &&
        u8[i + 3] === 0x61
      ) {
        hasAudio = true;
      }
    }
    return hasAudio
      ? `video/mp4; codecs="${videoCodec}, mp4a.40.2"`
      : `video/mp4; codecs="${videoCodec}"`;
  }

  function boxAt(u8, off) {
    if (off + 8 > u8.length) return null;
    const size =
      ((u8[off] << 24) |
        (u8[off + 1] << 16) |
        (u8[off + 2] << 8) |
        u8[off + 3]) >>>
      0;
    if (size < 8 || off + size > u8.length) return null;
    return {
      type: String.fromCharCode(
        u8[off + 4],
        u8[off + 5],
        u8[off + 6],
        u8[off + 7],
      ),
      size,
    };
  }

  function concat(a, b) {
    const out = new Uint8Array(a.length + b.length);
    out.set(a, 0);
    out.set(b, a.length);
    return out;
  }

  // Seconds of already-played media to keep behind the playhead. Everything
  // older is removed; without this the SourceBuffer grows for the whole
  // session and the tab eventually runs out of memory.
  const KEEP_BEHIND_S = 10;
  // If playback falls this far behind the live edge, jump back to it.
  const MAX_AHEAD_S = 20;
  // Hard ceiling on the buffered window. Trimming is capped against the live
  // edge as well as the playhead, so a stalled decoder or a suspended tab
  // cannot let the SourceBuffer grow for the whole session.
  const MAX_BUFFERED_S = 30;
  // Parsed fragments waiting to be appended, bounded by bytes. The network
  // reader must never block on MSE: prudynt closes the chunked response after
  // a 2s send timeout, which is what ends a long preview. If appends cannot
  // keep up, drop the oldest fragments -- this is a live view, so skipping
  // ahead beats unbounded memory.
  const MAX_QUEUED_BYTES = 4 * 1024 * 1024;
  // Reopen the stream after it drops so the preview survives a flushed socket
  // or a prudynt restart instead of going black.
  const RECONNECT_DELAY_MS = 2000;
  const UPDATE_TIMEOUT_MS = 5000;

  // Resolve once the SourceBuffer has no pending operation. The listeners are
  // always torn down, including error/abort, which otherwise never fire and
  // keep the closure (and the appended segment) alive forever.
  function waitIdle(sb) {
    return new Promise((resolve) => {
      let timer = null;
      const done = () => {
        sb.removeEventListener("updateend", done);
        sb.removeEventListener("error", done);
        sb.removeEventListener("abort", done);
        if (timer !== null) {
          window.clearTimeout(timer);
          timer = null;
        }
        resolve();
      };
      sb.addEventListener("updateend", done);
      sb.addEventListener("error", done);
      sb.addEventListener("abort", done);
      timer = window.setTimeout(done, UPDATE_TIMEOUT_MS);
    });
  }

  async function appendSegment(buf, mySession) {
    const sb = sourceBuffer;
    const ms = mediaSource;
    if (mySession !== sessionId || !sb || !ms || ms.readyState !== "open")
      return;
    while (sb.updating) {
      await waitIdle(sb);
      if (mySession !== sessionId) return;
    }
    try {
      sb.appendBuffer(buf);
    } catch (e) {
      return;
    }
    await waitIdle(sb);
  }

  async function trimBuffer(mySession) {
    const sb = sourceBuffer;
    const ms = mediaSource;
    if (mySession !== sessionId || !sb || !ms || ms.readyState !== "open")
      return;
    while (sb.updating) {
      await waitIdle(sb);
      if (mySession !== sessionId) return;
    }
    if (sb.buffered.length === 0) return;
    const start = sb.buffered.start(0);
    const end = sb.buffered.end(sb.buffered.length - 1);

    // Pin playback near the live edge first, so the trim bound below does not
    // depend on a playhead that a suspended tab or a stalled decoder froze.
    if (end - video.currentTime > MAX_AHEAD_S || video.currentTime < start) {
      video.currentTime = Math.max(start, end - 0.5);
      if (video.paused) video.play().catch(() => {});
    }

    // Never keep more than MAX_BUFFERED_S of media, even if the playhead never
    // moves. Both bounds are evaluated against the live edge: keep behind the
    // playhead, but always drop anything past the hard ceiling.
    const keep = Math.max(
      video.currentTime - KEEP_BEHIND_S,
      end - MAX_BUFFERED_S,
    );
    if (keep > start) {
      try {
        sb.remove(start, keep);
        await waitIdle(sb);
      } catch (e) {
        /* keep going; a failed trim must not kill the stream */
      }
    }
  }

  function teardown() {
    sessionId++;
    if (pumpWake) {
      const wake = pumpWake;
      pumpWake = null;
      wake();
    }
    if (abortController) {
      abortController.abort();
      abortController = null;
    }
    sourceBuffer = null;
    mediaSource = null;
    if (video.src) {
      try {
        URL.revokeObjectURL(video.src);
      } catch (e) {
        /* noop */
      }
      video.removeAttribute("src");
      video.load();
    }
  }

  // Read the socket and parse boxes on one task, append to the SourceBuffer on
  // another. Awaiting MSE work in the read loop lets the response socket go
  // unread; prudynt's 2s send timeout then closes the chunked response, which
  // is what ended long previews with ERR_INCOMPLETE_CHUNKED_ENCODING.
  async function run(ch, mySession) {
    if (mySession !== sessionId) return;
    abortController = new AbortController();

    const queue = [];
    let queuedBytes = 0;
    let closed = false;

    const wakePump = () => {
      if (pumpWake) {
        const wake = pumpWake;
        pumpWake = null;
        wake();
      }
    };
    const enqueue = (segment) => {
      queue.push(segment);
      queuedBytes += segment.length;
      while (queuedBytes > MAX_QUEUED_BYTES && queue.length > 1)
        queuedBytes -= queue.shift().length;
      wakePump();
    };
    const pump = async () => {
      while (mySession === sessionId) {
        if (queue.length === 0) {
          if (closed) return;
          await new Promise((resolve) => (pumpWake = resolve));
          continue;
        }
        const segment = queue.shift();
        queuedBytes -= segment.length;
        await appendSegment(segment, mySession);
        if (mySession !== sessionId) return;
        await trimBuffer(mySession);
      }
    };

    let resp;
    let url;
    try {
      url = await streamUrl(ch);
      resp = await fetch(url, {
        signal: abortController.signal,
        cache: "no-store",
      });
    } catch (e) {
      if (mySession !== sessionId) return;
      if (window.location.protocol === "https:") {
        setStatus(
          "fMP4 is served over HTTP. Open this page via http://" +
            host() +
            "/ to use it.",
        );
        return;
      }
      scheduleReconnect(mySession, "Failed to connect to " + url + ".");
      return;
    }
    if (mySession !== sessionId) return;
    if (!resp.ok || !resp.body) {
      setStatus("Stream unavailable (HTTP " + resp.status + ").");
      return;
    }

    const reader = resp.body.getReader();
    let buf = new Uint8Array(0);
    let initDone = false;
    let pumpRun = null;

    try {
      while (!initDone) {
        const { done, value } = await reader.read();
        if (mySession !== sessionId) return;
        if (done) {
          setStatus("Stream ended before init segment.");
          return;
        }
        buf = concat(buf, value);
        let off = 0;
        let ftypEnd = -1;
        let moovEnd = -1;
        while (true) {
          const box = boxAt(buf, off);
          if (!box) break;
          if (box.type === "ftyp") ftypEnd = off + box.size;
          else if (box.type === "moov" && ftypEnd >= 0 && off === ftypEnd)
            moovEnd = off + box.size;
          off += box.size;
        }
        if (moovEnd > 0) {
          if (mySession !== sessionId) return;
          const codecs = codecFromInit(buf.subarray(0, moovEnd));
          try {
            sourceBuffer = mediaSource.addSourceBuffer(codecs);
            sourceBuffer.mode = "segments";
          } catch (e) {
            setStatus("Unsupported codec: " + codecs);
            return;
          }
          enqueue(buf.subarray(0, moovEnd).slice());
          buf = buf.slice(moovEnd);
          initDone = true;
          pumpRun = pump().catch(() => {});
          setStatus("Live: /ch" + ch + ".mp4");
        }
      }

      while (true) {
        const { done, value } = await reader.read();
        if (mySession !== sessionId) return;
        if (done) break;
        buf = concat(buf, value);
        let off = 0;
        while (true) {
          const box = boxAt(buf, off);
          if (!box) break;
          if (box.type === "moof") {
            const mdat = boxAt(buf, off + box.size);
            if (!mdat || mdat.type !== "mdat") break;
            const segEnd = off + box.size + mdat.size;
            enqueue(buf.subarray(off, segEnd).slice());
            off = segEnd;
          } else {
            off += box.size;
          }
        }
        buf = buf.slice(off);
      }
      closed = true;
      wakePump();
      if (pumpRun) await pumpRun;
      scheduleReconnect(mySession, "Stream ended.");
    } catch (e) {
      closed = true;
      wakePump();
      scheduleReconnect(mySession, "Stream stopped.");
    }
  }

  function scheduleReconnect(mySession, why) {
    if (mySession !== sessionId) return;
    setStatus(why + " Reconnecting...");
    window.setTimeout(() => {
      if (mySession === sessionId) {
        // The run that scheduled this has settled, so start a fresh chain
        // instead of extending it once per reconnect.
        runPromise = Promise.resolve();
        start(channel);
      }
    }, RECONNECT_DELAY_MS);
  }

  function beginStream(ch, mySession) {
    channel = ch;
    setStatus("Connecting to /ch" + ch + ".mp4 ...");
    mediaSource = new MediaSource();
    video.src = URL.createObjectURL(mediaSource);
    mediaSource.addEventListener(
      "sourceopen",
      () => {
        if (mySession !== sessionId) return;
        runPromise = run(ch, mySession);
      },
      { once: true },
    );
    video.play().catch(() => {
      /* autoplay may be blocked */
    });
  }

  function start(ch) {
    teardown();
    const mySession = sessionId;
    runPromise = runPromise
      .catch(() => {})
      .then(() => {
        if (mySession === sessionId) beginStream(ch, mySession);
      });
  }

  function selectChannel(ch) {
    const b0 = document.getElementById("fmp4-ch0");
    const b1 = document.getElementById("fmp4-ch1");
    if (b0) b0.classList.toggle("active", ch === 0);
    if (b1) b1.classList.toggle("active", ch === 1);
    start(ch);
  }

  document
    .getElementById("fmp4-ch0")
    .addEventListener("click", () => selectChannel(0));
  document
    .getElementById("fmp4-ch1")
    .addEventListener("click", () => selectChannel(1));

  // Endpoint links are rendered by the shared /a/preview-endpoints.js
  // module. Refresh the RTSP credentials it shows once the config answers;
  // until then it renders the thingino/thingino/554 defaults.
  API_KEY_PROMISE.then((key) =>
    fetch("http://" + host() + ":8080/api/v1/config/rtsp", {
      cache: "no-store",
      headers: key ? { "X-API-Key": key } : {},
    }),
  )
    .then((r) => (r.ok ? r.json() : null))
    .then((rtsp) => {
      if (rtsp && window.thinginoPreviewEndpoints) {
        window.thinginoPreviewEndpoints.updateState({ rtsp });
      }
    })
    .catch(() => {});

  // Custom controls: mute + volume + fullscreen; preview stays playing.
  const muteBtn = document.getElementById("fmp4-mute");
  const volumeSlider = document.getElementById("fmp4-volume");
  const zoomBtn = document.getElementById("fmp4-zoom");
  const frame = document.getElementById("frame");

  function setMuteIcon() {
    if (muteBtn) {
      const silent = video.muted || video.volume === 0;
      muteBtn.querySelector("i").className = silent
        ? "bi bi-volume-mute"
        : "bi bi-volume-up";
      muteBtn.title = silent ? "Unmute" : "Mute";
    }
  }

  function setZoomIcon() {
    if (zoomBtn) {
      zoomBtn.querySelector("i").className = document.fullscreenElement
        ? "bi bi-fullscreen-exit"
        : "bi bi-arrows-fullscreen";
    }
  }

  if (muteBtn) {
    muteBtn.addEventListener("click", () => {
      if (video.muted || video.volume === 0) {
        video.muted = false;
        if (video.volume === 0) {
          video.volume = 1;
          if (volumeSlider) volumeSlider.value = "100";
        }
      } else {
        video.muted = true;
      }
      setMuteIcon();
    });
  }
  if (volumeSlider) {
    volumeSlider.addEventListener("input", () => {
      video.volume = Number(volumeSlider.value) / 100;
      if (video.volume > 0) video.muted = false;
      setMuteIcon();
    });
  }
  if (zoomBtn) {
    zoomBtn.addEventListener("click", () => {
      if (document.fullscreenElement) {
        document.exitFullscreen();
      } else if (frame && frame.requestFullscreen) {
        frame.requestFullscreen();
      }
    });
  }
  document.addEventListener("fullscreenchange", setZoomIcon);
  video.addEventListener("pause", () => {
    video.play().catch(() => {});
  });
  setMuteIcon();
  setZoomIcon();

  start(channel);
})();
