/* preview-talk.js - push-to-talk (browser microphone -> camera speaker) for the
 * timps preview page.
 *
 * Captures the visitor's microphone, encodes it as G.711 mu-law and streams
 * 20 ms binary frames over a WebSocket to timps' /talk endpoint, which decodes
 * them straight into the same IMP_AO speaker path the ONVIF/RTSP backchannel
 * uses. A browser cannot speak RTSP/RTP, which is the whole reason this
 * transport exists.
 *
 * Fails soft throughout, exactly like preview-motion.js: no token, no HTTPS, or
 * a build without the endpoint just leaves the button hidden. The button is
 * HIDDEN rather than disabled - a greyed control invites "why doesn't this
 * work", a missing one asks nothing.
 *
 * Requires all four of:
 *   - caps.backchannel.talk_ws == 1 from GET /control (feature compiled AND
 *     audio.talk_ws set AND the backchannel pipeline up at boot)
 *   - a TLS timps listener: getUserMedia() is refused outside a secure
 *     context, and a wss:// URL is the only thing an https:// page may open
 *   - navigator.mediaDevices.getUserMedia
 *   - AudioContext with createScriptProcessor
 *
 * ScriptProcessorNode is deprecated in favour of AudioWorklet and runs on the
 * main thread, so it can glitch under heavy page load. That is a deliberate
 * first-cut choice: a worklet processor's exceptions are swallowed on the
 * audio render thread with no console trace, which is a poor place to be while
 * the C side of this protocol is also new. Revisit once /talk has real miles.
 */
(function () {
  "use strict";

  const btn = document.getElementById("ms-talk");
  const statusEl = document.getElementById("ms-talk-status");
  if (!btn) return;

  const FRAME_MS = 20;
  /* Must not exceed WS_MAX_PAYLOAD in timps' src/ws.h. One mu-law byte per
   * sample, so 20 ms at 48 kHz = 960 bytes is the largest frame we can emit
   * and still fit. Every rate in RATES_OK stays under this. */
  const WS_MAX_PAYLOAD = 1024;
  /* Sample rates timps' talk_ws.c accepts via ?rate= (TALK_RATES there). Kept
   * in sync by hand; an unlisted rate is refused with 400 by the server, so
   * checking here just turns a mystery failure into a readable message. */
  const RATES_OK = [8000, 16000, 24000, 32000, 44100, 48000];
  /* Client-side backpressure. The server has its own drop-if-behind guard, but
   * there is no point handing the socket audio it cannot drain: past this much
   * queued, drop frames here instead. ~10 frames = 200 ms. */
  const MAX_BUFFERED = 10 * WS_MAX_PAYLOAD;
  const PROBE_MAX_BACKOFF_MS = 30000;

  let base = null;    // https://<host>:<port>
  let wsBase = null;  // wss://<host>:<port>
  let token = null;
  let stopped = false; // set on pagehide; stops the probe retry loop

  // live session state, all null/idle between presses
  let ws = null, ctx = null, spn = null, src = null, sink = null, mic = null;
  let state = "idle"; // idle | connecting | talking | error
  let pending = null, pendN = 0, frameSamples = 0;
  let errTimer = null;

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function say(msg, isErr) {
    if (!statusEl) { if (isErr) console.warn("[talk] " + msg); return; }
    if (errTimer) { clearTimeout(errTimer); errTimer = null; }
    statusEl.textContent = msg || "";
    statusEl.style.display = msg ? "" : "none";
    statusEl.classList.toggle("text-danger", !!isErr);
    // errors are transient notices, not a permanent banner
    if (msg && isErr) errTimer = setTimeout(() => say(""), 6000);
  }

  function setBtn() {
    const on = state === "talking" || state === "connecting";
    btn.classList.toggle("active", on);
    btn.classList.toggle("btn-danger", state === "talking");
    btn.classList.toggle("btn-outline-secondary", state !== "talking");
    btn.disabled = state === "connecting";
    btn.title = state === "talking" ? "Stop talking"
              : state === "connecting" ? "Connecting the talk channel..."
              : "Talk to the camera (microphone -> camera speaker)";
  }

  /* Reveal the control. Unlike preview-motion.js this is one-way: motion can be
   * switched on and off live, so that module re-hides its button off the event
   * stream, but audio.talk_ws is restart-only - once /control says the endpoint
   * is being served, it is served for the life of this page. */
  function showBtn() {
    btn.style.display = "";
    setBtn();
  }

  /* float [-1,1] -> G.711 mu-law byte. The exact inverse of g711_ulaw_decode()
   * in timps' src/codec/g711.c (Sun/CCITT), so what the camera reconstructs is
   * what we sampled. No table: ~10 integer ops per sample is cheaper than the
   * cache miss, and this runs on the main thread. */
  function ulawEncode(f) {
    let s = (f < -1 ? -1 : f > 1 ? 1 : f) * 32767 | 0;
    const sign = (s >> 8) & 0x80;
    if (sign) s = -s;
    if (s > 32635) s = 32635;      // CLIP
    s += 132;                      // BIAS 0x84
    let exp = 7;
    for (let m = 0x4000; (s & m) === 0 && exp > 0; m >>= 1) exp--;
    const mant = (s >> (exp + 3)) & 0x0F;
    return ~(sign | (exp << 4) | mant) & 0xFF;
  }

  /* ScriptProcessorNode wants a power-of-two buffer (256..16384). Target ~30 ms
   * so latency stays low without making main-thread glitches likely: 256 at
   * 8 kHz (32 ms), 1024 at 48 kHz (21 ms). */
  function bufSizeFor(rate) {
    let n = 256;
    while (n < 16384 && n * 2 <= rate * 0.03) n *= 2;
    return n;
  }

  function teardown() {
    // stop producing before closing the socket, so no frame races the close
    if (spn) { try { spn.disconnect(); } catch (e) {} spn.onaudioprocess = null; spn = null; }
    if (src) { try { src.disconnect(); } catch (e) {} src = null; }
    if (sink) { try { sink.disconnect(); } catch (e) {} sink = null; }
    if (mic) { try { mic.getTracks().forEach((t) => t.stop()); } catch (e) {} mic = null; }
    if (ctx) { try { ctx.close(); } catch (e) {} ctx = null; }
    pending = null; pendN = 0; frameSamples = 0;
  }

  /* Always the client-initiated path: a real close frame (1000) makes timps'
   * ws_read_message() return WS_CLOSED immediately, so talk_ws.c runs
   * bc_release() and drops the speaker now instead of after its 10 s
   * stale-owner timeout. Abandoning the socket would "work" but leave the
   * camera's speaker owned by a session that is already gone. */
  function stop(msg, isErr) {
    teardown();
    if (ws) {
      const w = ws;
      ws = null;
      w.onopen = w.onmessage = w.onerror = w.onclose = null;
      try {
        if (w.readyState === WebSocket.OPEN || w.readyState === WebSocket.CONNECTING)
          w.close(1000, "bye");
      } catch (e) {}
    }
    // Errors are surfaced by say() as transient red text, not by a stuck
    // button: the control goes straight back to idle so it can be retried.
    state = "idle";
    setBtn();
    say(msg || "", isErr);
  }

  function flushFrames() {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    while (pendN >= frameSamples) {
      if (ws.bufferedAmount > MAX_BUFFERED) {
        // socket is not draining: drop everything queued rather than grow a
        // backlog the listener would hear as ever-increasing delay
        pendN = 0;
        return;
      }
      ws.send(pending.subarray(0, frameSamples));
      pending.copyWithin(0, frameSamples, pendN);
      pendN -= frameSamples;
    }
  }

  async function start() {
    state = "connecting";
    setBtn();
    say("Requesting microphone...");

    try {
      mic = await navigator.mediaDevices.getUserMedia({
        audio: {
          // The camera has its own AEC (audio.aec / IMP_AI_EnableAec) for the
          // far end; this is the near-end half - it stops the camera's own
          // audio, playing out of these speakers, from being sent back.
          echoCancellation: true,
          noiseSuppression: true,
          autoGainControl: true,
          channelCount: 1,
        },
      });
    } catch (e) {
      stop("Microphone denied or unavailable.", true);
      return;
    }
    if (stopped) { stop(""); return; }

    // Ask for 8 kHz (mu-law's native rate, 64 kbit/s on the wire). Browsers may
    // decline and impose the hardware rate - iOS Safari commonly forces 48 kHz
    // - so the requested value is never assumed: read it back and tell the
    // server what we actually got. timps resamples whatever it is handed.
    const AC = window.AudioContext || window.webkitAudioContext;
    try {
      ctx = new AC({ sampleRate: 8000 });
    } catch (e) {
      try { ctx = new AC(); } catch (e2) { stop("No Web Audio support.", true); return; }
    }
    if (!ctx.createScriptProcessor) { stop("No Web Audio support.", true); return; }
    // iOS starts contexts suspended; we are inside a click handler, so this is
    // the one moment resuming is allowed.
    try { await ctx.resume(); } catch (e) {}

    const rate = Math.round(ctx.sampleRate);
    if (RATES_OK.indexOf(rate) < 0) {
      stop("Browser audio rate " + rate + " Hz is not supported by the camera.", true);
      return;
    }
    frameSamples = Math.round((rate * FRAME_MS) / 1000);
    if (frameSamples > WS_MAX_PAYLOAD) frameSamples = WS_MAX_PAYLOAD;
    pending = new Uint8Array(frameSamples * 4);
    pendN = 0;

    const url = wsBase + "/talk?token=" + encodeURIComponent(token) + "&rate=" + rate;
    try {
      ws = new WebSocket(url);
    } catch (e) {
      stop("Cannot open the talk channel.", true);
      return;
    }
    ws.binaryType = "arraybuffer";

    ws.onopen = () => {
      if (!ws) return;
      state = "talking";
      setBtn();
      say("Talking - " + rate + " Hz");

      const n = bufSizeFor(rate);
      spn = ctx.createScriptProcessor(n, 1, 1);
      src = ctx.createMediaStreamSource(mic);
      // A ScriptProcessorNode only runs while it is connected to a
      // destination, but routing the microphone to these speakers would be an
      // instant feedback loop - so terminate it in a muted gain node.
      sink = ctx.createGain();
      sink.gain.value = 0;

      spn.onaudioprocess = (ev) => {
        if (!ws || ws.readyState !== WebSocket.OPEN) return;
        const inBuf = ev.inputBuffer.getChannelData(0);
        if (pendN + inBuf.length > pending.length) {
          const grown = new Uint8Array((pendN + inBuf.length) * 2);
          grown.set(pending.subarray(0, pendN));
          pending = grown;
        }
        for (let i = 0; i < inBuf.length; i++) pending[pendN++] = ulawEncode(inBuf[i]);
        flushFrames();
      };

      src.connect(spn);
      spn.connect(sink);
      sink.connect(ctx.destination);
    };

    ws.onmessage = (ev) => {
      // talk_ws.c sends one hello: {"ok":1,"codec":"pcmu","rate":N}. Purely
      // informational - it turns "no audio" into something diagnosable.
      if (typeof ev.data !== "string") return;
      try {
        const j = JSON.parse(ev.data);
        if (j && j.rate && j.rate !== rate)
          console.warn("[talk] server negotiated " + j.rate + " Hz, we sent " + rate);
      } catch (e) {}
    };

    ws.onerror = () => { if (ws) stop("Talk channel failed.", true); };

    ws.onclose = (ev) => {
      if (!ws) return; // our own stop() already cleaned up
      // 1000 from the server side still means it ended this, not us
      const why = ev.code === 1008 ? "Another talker holds the camera speaker."
                : ev.code === 1001 ? "Talk channel timed out."
                : "Talk channel closed (" + ev.code + ").";
      stop(why, ev.code !== 1000);
    };
  }

  function toggle() {
    if (state === "connecting") return;
    if (state === "talking") stop("");
    else start();
  }

  async function probe() {
    const res = await fetch(base + "/control", {
      headers: { "X-Timps-Token": token },
      cache: "no-store",
    });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    return !!(data && data.caps && data.caps.backchannel &&
              data.caps.backchannel.talk_ws);
  }

  async function init() {
    let info;
    if (window.timpsTokenInfo) {
      info = await window.timpsTokenInfo;   // shared single fetch (preview.html)
    } else {
      try {
        const res = await fetch("/x/timps-token.cgi", { cache: "no-store" });
        if (!res.ok) return;                // no bridge -> feature silently off
        info = await res.json();
      } catch (e) {
        return;
      }
    }
    if (!info || !info.token) return;
    token = info.token;
    let host = location.hostname || "127.0.0.1";
    if (host.indexOf(":") >= 0 && host[0] !== "[") host = "[" + host + "]"; // raw IPv6
    const port = info.port || 8880;
    base = (info.tls ? "https" : "http") + "://" + host + ":" + port;
    wsBase = "wss://" + host + ":" + port;

    window.addEventListener("pagehide", () => { stopped = true; stop(""); });

    // Hard gates, all permanent for this page load - no point probing without
    // them. /talk answers 426 on a plaintext listener, and getUserMedia is
    // undefined outside a secure context, so either one means "never".
    if (!info.tls) return;
    if (!window.WebSocket) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return;
    if (!(window.AudioContext || window.webkitAudioContext)) return;

    // Retry the capability probe with backoff rather than giving up forever on
    // one transient failure (client pool full, cert not yet trusted).
    let usable = false;
    for (let delay = 1000; !stopped; delay = Math.min(PROBE_MAX_BACKOFF_MS, delay * 2)) {
      try {
        usable = await probe();
        break;
      } catch (e) {
        await sleep(delay);
      }
    }
    if (stopped || !usable) return;

    showBtn();
    btn.addEventListener("click", toggle);
  }

  init();
})();
