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
  // Wall-clock anchor for the current session: the live edge at the first
  // appended fragment and the time it arrived.
  let edgeMediaRef = null;
  let edgeWallRef = null;
  // Browsers without MSE HEVC fall back to WebCodecs. The decision is cached
  // per channel so a reconnect goes straight to the decoder sink.
  const wcMode = {};
  let wcCanvas = null;
  let wcDecoder = null;

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

  // RFC 6381 codec string for an HEVC track, from the hvcC box payload
  // (General_profile/tier/level fields, ISO/IEC 14496-15 Annex E). The camera
  // muxes hvc1 with the parameter sets in hvcC, so the sample entry is always
  // "hvc1".
  function hevcCodecString(base) {
    const b1 = base[1];
    const space = (b1 >> 6) & 0x03;
    const tier = (b1 >> 5) & 0x01;
    const profile = b1 & 0x1f;
    // general_profile_compatibility_flags is a 32-bit value whose RFC 6381
    // rendering is the bit-reversed field as lowercase hex.
    let compat = 0;
    for (let i = 0; i < 4; i++) compat = (compat * 256 + base[2 + i]) >>> 0;
    let rev = 0;
    for (let i = 0; i < 32; i++) {
      rev = ((rev << 1) | (compat & 1)) >>> 0;
      compat >>>= 1;
    }
    // general_constraint_indicator_flags: six bytes with trailing zeros
    // trimmed.
    let constraints = "";
    for (let i = 11; i >= 6; i--) {
      if (base[i] !== 0) {
        for (let k = 6; k <= i; k++) constraints += hex(base[k]);
        break;
      }
    }
    const spaceLetter = ["", "A", "B", "C"][space] || "";
    const tierLetter = tier ? "H" : "L";
    let codec =
      "hvc1." +
      spaceLetter +
      profile +
      "." +
      rev.toString(16) +
      "." +
      tierLetter +
      base[12];
    if (constraints) codec += "." + constraints;
    return codec;
  }

  function codecFromInit(u8) {
    let videoCodec = "avc1.42E01E";
    let hevc = false;
    let hasAudio = false;
    for (let i = 0; i + 8 <= u8.length; i++) {
      if (
        u8[i] === 0x68 &&
        u8[i + 1] === 0x76 &&
        u8[i + 2] === 0x63 &&
        u8[i + 3] === 0x43
      ) {
        videoCodec = hevcCodecString(u8.subarray(i + 4));
        hevc = true;
      } else if (
        !hevc &&
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
    return {
      hevc: hevc,
      codec: videoCodec,
      mime: hasAudio
        ? `video/mp4; codecs="${videoCodec}, mp4a.40.2"`
        : `video/mp4; codecs="${videoCodec}"`,
    };
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

  // Payload of the first direct child box of `type`, or null.
  function findBoxPayload(bytes, type) {
    let off = 0;
    let b;
    while ((b = boxAt(bytes, off))) {
      if (b.type === type) return bytes.subarray(off + 8, off + b.size);
      off += b.size;
    }
    return null;
  }

  function findInPath(bytes, path) {
    let cur = bytes;
    for (let i = 0; i < path.length; i++) {
      cur = findBoxPayload(cur, path[i]);
      if (!cur) return null;
    }
    return cur;
  }

  // The video track's decoder config, geometry and timescale out of the moov,
  // for VideoDecoder.configure. The camera muxes hvc1, so only that sample
  // entry is accepted here.
  function parseVideoTrack(init) {
    const moov = findBoxPayload(init, "moov");
    if (!moov) return null;
    let off = 0;
    let b;
    while ((b = boxAt(moov, off))) {
      if (b.type !== "trak") {
        off += b.size;
        continue;
      }
      const trak = moov.subarray(off + 8, off + b.size);
      const stsd = findInPath(trak, ["mdia", "minf", "stbl", "stsd"]);
      const entry = stsd ? boxAt(stsd, 8) : null;
      if (entry && (entry.type === "hvc1" || entry.type === "hev1")) {
        const payload = stsd.subarray(16, 8 + entry.size);
        // VisualSampleEntry is 78 bytes before its child boxes.
        let config = null;
        let cOff = 78;
        let cb;
        while ((cb = boxAt(payload, cOff))) {
          if (cb.type === "hvcC") {
            config = payload.subarray(cOff + 8, cOff + cb.size);
            break;
          }
          cOff += cb.size;
        }
        if (config) {
          const mdhd = findInPath(trak, ["mdia", "mdhd"]);
          let timescale = 90000;
          if (mdhd && mdhd.length >= 20) {
            const dv = new DataView(mdhd.buffer, mdhd.byteOffset, mdhd.length);
            timescale = mdhd[0] === 1 ? dv.getUint32(20) : dv.getUint32(12);
          }
          const tkhd = findBoxPayload(trak, "tkhd");
          let trackId = 1;
          if (tkhd && tkhd.length >= 24) {
            const dv = new DataView(tkhd.buffer, tkhd.byteOffset, tkhd.length);
            trackId = tkhd[0] === 1 ? dv.getUint32(20) : dv.getUint32(12);
          }
          const dv = new DataView(
            payload.buffer,
            payload.byteOffset,
            payload.length,
          );
          return {
            id: trackId,
            timescale: timescale,
            width: dv.getUint16(24),
            height: dv.getUint16(26),
            config: config.slice(),
          };
        }
      }
      off += b.size;
    }
    return null;
  }

  // Samples out of one moof, resolved as byte offsets relative to the moof
  // start. The muxer writes one trun per fragment; this still walks a multi
  // sample trun. Only the video track is returned.
  function parseMoof(moof, timescale, videoTrackId) {
    const out = [];
    let off = 0;
    let b;
    while ((b = boxAt(moof, off))) {
      if (b.type === "traf") {
        const traf = moof.subarray(off + 8, off + b.size);
        const tfhd = findBoxPayload(traf, "tfhd");
        const trun = findBoxPayload(traf, "trun");
        const tfdt = findBoxPayload(traf, "tfdt");
        if (tfhd && trun) {
          const dvt = new DataView(tfhd.buffer, tfhd.byteOffset, tfhd.length);
          if (dvt.getUint32(4) === videoTrackId) {
            let base = 0;
            if (tfdt) {
              const dvd = new DataView(
                tfdt.buffer,
                tfdt.byteOffset,
                tfdt.length,
              );
              base =
                tfdt[0] === 1 ? Number(dvd.getBigUint64(4)) : dvd.getUint32(4);
            }
            const dvr = new DataView(trun.buffer, trun.byteOffset, trun.length);
            const flags = (trun[1] << 16) | (trun[2] << 8) | trun[3];
            let p = 4;
            const count = dvr.getUint32(p);
            p += 4;
            let rel = 0;
            if (flags & 0x000001) {
              rel = dvr.getUint32(p);
              p += 4;
            }
            if (flags & 0x000004) p += 4; // first_sample_flags
            let t = base;
            for (let i = 0; i < count; i++) {
              let dur = 0;
              let size = 0;
              let sampleFlags = 0;
              let cts = 0;
              if (flags & 0x000100) {
                dur = dvr.getUint32(p);
                p += 4;
              }
              if (flags & 0x000200) {
                size = dvr.getUint32(p);
                p += 4;
              }
              if (flags & 0x000400) {
                sampleFlags = dvr.getUint32(p);
                p += 4;
              }
              if (flags & 0x000800) {
                cts = dvr.getUint32(p);
                p += 4;
              }
              out.push({
                dataOffset: rel,
                size: size,
                timestampUs: ((t + cts) * 1e6) / timescale,
                durationUs: (dur * 1e6) / timescale,
                key: (sampleFlags & 0x00010000) === 0,
              });
              rel += size;
              t += dur;
            }
          }
        }
      }
      off += b.size;
    }
    return out;
  }

  // Canvas sink for decoded frames, sized and shown in place of the video
  // element. Created once and reused across reconnects.
  function ensureCanvas() {
    if (wcCanvas) return wcCanvas;
    wcCanvas = document.createElement("canvas");
    wcCanvas.className = "w-100";
    wcCanvas.style.display = "none";
    const frame = document.getElementById("frame") || video.parentNode;
    if (video.nextSibling) frame.insertBefore(wcCanvas, video.nextSibling);
    else frame.appendChild(wcCanvas);
    return wcCanvas;
  }

  // Seconds of already-played media to keep behind the playhead. Everything
  // older is removed; without this the SourceBuffer grows for the whole
  // session and the tab eventually runs out of memory.
  const KEEP_BEHIND_S = 10;
  // If playback falls this far behind the live edge, jump back to it. A
  // config write (preset save) can stall the camera long enough to push the
  // player behind; 20s was so lax the lag persisted, while 1.5s seeked on
  // every fragment and starved the reader. 5s recovers from a stall without
  // churning during normal play.
  const MAX_AHEAD_S = 5;
  // Camera-side backlog budget. A client that stalls makes prudynt queue
  // fragments, and it drains that queue one per produced frame, so the
  // playhead and the live edge stay close while the whole session plays
  // stale content. Buffer geometry cannot see that; anchor the media
  // timeline to the wall clock and reconnect once the live edge falls this
  // far behind realtime.
  const MAX_DRIFT_S = 5;
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

    // Detect a camera-side backlog the geometry checks cannot see. Only a
    // fresh fetch resets prudynt's per-client queue, so reconnect rather than
    // seek within the stale buffer.
    const now = performance.now();
    if (edgeMediaRef === null) {
      edgeMediaRef = end;
      edgeWallRef = now;
    } else if (edgeMediaRef + (now - edgeWallRef) / 1000 - end > MAX_DRIFT_S) {
      setStatus("Preview drifted behind live edge, resyncing...");
      start(channel);
      return;
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
    edgeMediaRef = null;
    edgeWallRef = null;
    if (pumpWake) {
      const wake = pumpWake;
      pumpWake = null;
      wake();
    }
    if (abortController) {
      abortController.abort();
      abortController = null;
    }
    if (wcDecoder) {
      try {
        wcDecoder.close();
      } catch (e) {
        /* ignore */
      }
      wcDecoder = null;
    }
    if (wcCanvas) wcCanvas.style.display = "none";
    video.style.display = "";
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
          const info = codecFromInit(buf.subarray(0, moovEnd));
          const mseHevc =
            !info.hevc ||
            !!(window.MediaSource && MediaSource.isTypeSupported(info.mime));
          if (!mseHevc || wcMode[ch]) {
            wcMode[ch] = true;
            await startDecoder(
              ch,
              mySession,
              info,
              buf.subarray(0, moovEnd),
              buf.subarray(moovEnd),
              reader,
            );
            return;
          }
          try {
            sourceBuffer = mediaSource.addSourceBuffer(info.mime);
            sourceBuffer.mode = "segments";
          } catch (e) {
            if (info.hevc) {
              wcMode[ch] = true;
              await startDecoder(
                ch,
                mySession,
                info,
                buf.subarray(0, moovEnd),
                buf.subarray(moovEnd),
                reader,
              );
              return;
            }
            setStatus("Unsupported codec: " + info.mime);
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

  // WebCodecs path for HEVC where MSE will not take it. Demuxes the same
  // custom fMP4 the MSE path appends, feeds VideoDecoder and paints frames to
  // the canvas sink.
  async function startDecoder(ch, mySession, info, init, leftover, reader) {
    if (typeof VideoDecoder === "undefined") {
      setStatus(
        "H.265 preview needs MSE HEVC or WebCodecs. WebCodecs is https-only, so on plain http use the H.264 substream or a HEVC-capable browser.",
      );
      return;
    }
    const track = parseVideoTrack(init);
    if (!track) {
      setStatus("H.265: no hvcC in the init segment.");
      return;
    }
    if (mediaSource) {
      try {
        if (mediaSource.readyState === "open") mediaSource.endOfStream();
      } catch (e) {
        /* ignore */
      }
      mediaSource = null;
    }
    if (video.getAttribute("src")) {
      const objUrl = video.getAttribute("src");
      video.removeAttribute("src");
      try {
        URL.revokeObjectURL(objUrl);
      } catch (e) {
        /* ignore */
      }
      try {
        video.load();
      } catch (e) {
        /* ignore */
      }
    }
    video.style.display = "none";
    const canvas = ensureCanvas();
    canvas.style.display = "";
    const ctx = canvas.getContext("2d");

    let gotFrame = false;
    const decoder = new VideoDecoder({
      output: (frame) => {
        if (mySession !== sessionId) {
          frame.close();
          return;
        }
        if (
          canvas.width !== frame.displayWidth ||
          canvas.height !== frame.displayHeight
        ) {
          canvas.width = frame.displayWidth;
          canvas.height = frame.displayHeight;
        }
        ctx.drawImage(frame, 0, 0);
        frame.close();
        if (!gotFrame) {
          gotFrame = true;
          setStatus("Live: /ch" + ch + ".mp4 (WebCodecs)");
        }
      },
      error: (e) => {
        setStatus("H.265 decoder error: " + (e && e.message ? e.message : e));
        scheduleReconnect(mySession, "Decoder reset.");
      },
    });
    wcDecoder = decoder;
    try {
      decoder.configure({
        codec: info.codec,
        description: track.config,
        codedWidth: track.width || undefined,
        codedHeight: track.height || undefined,
        hardwareAcceleration: "prefer-hardware",
        optimizeForLatency: true,
      });
    } catch (e) {
      setStatus("H.265 decoder rejected the config: " + e.message);
      return;
    }
    setStatus("H.265 over WebCodecs...");

    const MAX_DECODE_QUEUE = 6;
    let dropping = false;
    const feed = (sample, tsUs, durUs, key) => {
      // Live view: when the decoder falls behind, drop deltas until the next
      // key frame instead of growing an unbounded backlog.
      if (dropping && !key) return;
      if (!key && decoder.decodeQueueSize > MAX_DECODE_QUEUE) {
        dropping = true;
        return;
      }
      dropping = false;
      try {
        decoder.decode(
          new EncodedVideoChunk({
            type: key ? "key" : "delta",
            timestamp: Math.round(tsUs),
            duration: Math.round(durUs),
            data: sample,
          }),
        );
      } catch (e) {
        /* a rejected chunk is not fatal for a live stream */
      }
    };

    let buf = leftover;
    try {
      while (mySession === sessionId) {
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
            const samples = parseMoof(
              buf.subarray(off + 8, off + box.size),
              track.timescale,
              track.id,
            );
            for (let i = 0; i < samples.length; i++) {
              const s = samples[i];
              feed(
                buf.subarray(off + s.dataOffset, off + s.dataOffset + s.size),
                s.timestampUs,
                s.durationUs,
                s.key,
              );
            }
            off += box.size + mdat.size;
          } else {
            off += box.size;
          }
        }
        buf = buf.slice(off);
      }
      await decoder.flush().catch(() => {});
      scheduleReconnect(mySession, "Stream ended.");
    } catch (e) {
      if (mySession === sessionId)
        scheduleReconnect(mySession, "Stream stopped.");
    } finally {
      if (wcDecoder === decoder) wcDecoder = null;
      try {
        decoder.close();
      } catch (e) {
        /* ignore */
      }
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
    // A channel already known to need the decoder has no MSE sink to open.
    if (wcMode[ch]) {
      runPromise = run(ch, mySession);
      return;
    }
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
