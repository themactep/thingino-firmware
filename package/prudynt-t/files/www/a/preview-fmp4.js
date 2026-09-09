(function () {
  "use strict";

  const video = document.getElementById("fmp4-video");
  const statusEl = document.getElementById("fmp4-status");
  if (!video) return;

  const HTTP_PORT = 8080;
  let mediaSource = null;
  let sourceBuffer = null;
  let abortController = null;
  let channel = 0;
  let sessionId = 0;

  const host = () => window.location.hostname || "localhost";
  const streamUrl = (ch) => `http://${host()}:${HTTP_PORT}/ch${ch}.mp4`;
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
      ((u8[off] << 24) | (u8[off + 1] << 16) | (u8[off + 2] << 8) | u8[off + 3]) >>>
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

  function appendSegment(buf, mySession) {
    const sb = sourceBuffer;
    const ms = mediaSource;
    return new Promise((resolve) => {
      const done = () => resolve();
      const tryAppend = () => {
        if (mySession !== sessionId || !sb || !ms || ms.readyState !== "open") {
          done();
          return;
        }
        if (sb.updating) {
          sb.addEventListener("updateend", tryAppend, { once: true });
          return;
        }
        sb.addEventListener("updateend", done, { once: true });
        try {
          sb.appendBuffer(buf);
        } catch (e) {
          done();
        }
      };
      tryAppend();
    });
  }

  function teardown() {
    sessionId++;
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

  async function run(ch, mySession) {
    abortController = new AbortController();
    let resp;
    try {
      resp = await fetch(streamUrl(ch), {
        signal: abortController.signal,
        cache: "no-store",
      });
    } catch (e) {
      if (mySession === sessionId) {
        setStatus(
          window.location.protocol === "https:"
            ? "fMP4 is served over HTTP. Open this page via http://" +
                host() +
                "/ to use it."
            : "Failed to connect to " + streamUrl(ch) + ".",
        );
      }
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
          await appendSegment(buf.subarray(0, moovEnd).slice(), mySession);
          buf = buf.subarray(moovEnd);
          initDone = true;
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
            await appendSegment(buf.subarray(off, segEnd).slice(), mySession);
            if (mySession !== sessionId) return;
            off = segEnd;
          } else {
            off += box.size;
          }
        }
        buf = buf.subarray(off);
      }
      if (mySession === sessionId) setStatus("Stream ended.");
    } catch (e) {
      if (mySession === sessionId) setStatus("Stream stopped.");
    }
  }

  function start(ch) {
    teardown();
    channel = ch;
    setStatus("Connecting to /ch" + ch + ".mp4 ...");
    if (!("MediaSource" in window)) {
      setStatus("This browser does not support MediaSource.");
      return;
    }
    const mySession = sessionId;
    mediaSource = new MediaSource();
    video.src = URL.createObjectURL(mediaSource);
    mediaSource.addEventListener("sourceopen", () => run(ch, mySession), {
      once: true,
    });
    video.play().catch(() => {
      /* autoplay may be blocked */
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

  const list = document.getElementById("preview-endpoint-list");
  const dropdown = document.getElementById("preview-endpoint-dropdown-menu");
  const entries = [
    { label: "fMP4 Main", url: streamUrl(0) },
    { label: "fMP4 Sub", url: streamUrl(1) },
  ];

  async function copyUrl(ev) {
    ev.preventDefault();
    const link = ev.currentTarget;
    const url = link.dataset.copyUrl || link.href || "";
    try {
      if (navigator.clipboard && navigator.clipboard.writeText) {
        await navigator.clipboard.writeText(url);
      }
    } catch (e) {
      /* noop */
    }
    link.classList.add("copied");
    window.setTimeout(() => link.classList.remove("copied"), 1200);
  }

  entries.forEach((entry) => {
    if (list) {
      const a = document.createElement("a");
      a.className = "preview-endpoint-link";
      a.href = entry.url;
      a.rel = "noopener";
      a.dataset.copyUrl = entry.url;
      a.title = entry.label + ": " + entry.url;
      a.innerHTML =
        '<span class="preview-endpoint-short">' +
        entry.label +
        '</span> <i class="bi bi-clipboard"></i>';
      a.addEventListener("click", copyUrl);
      list.appendChild(a);
    }
    if (dropdown) {
      const li = document.createElement("li");
      const a = document.createElement("a");
      a.className = "dropdown-item preview-endpoint-dropdown-item";
      a.href = entry.url;
      a.dataset.copyUrl = entry.url;
      a.title = entry.label + ": " + entry.url;
      a.innerHTML =
        '<span class="preview-endpoint-short">' +
        entry.label +
        '</span> <i class="bi bi-clipboard"></i>';
      a.addEventListener("click", copyUrl);
      li.appendChild(a);
      dropdown.appendChild(li);
    }
  });

  // Custom controls: mute + fullscreen only; the preview stays playing.
  const muteBtn = document.getElementById("fmp4-mute");
  const zoomBtn = document.getElementById("fmp4-zoom");
  const frame = document.getElementById("frame");

  function setMuteIcon() {
    if (muteBtn) {
      muteBtn.querySelector("i").className = video.muted
        ? "bi bi-volume-mute"
        : "bi bi-volume-up";
      muteBtn.title = video.muted ? "Unmute" : "Mute";
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
      video.muted = !video.muted;
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

  start(0);
})();
