(function () {
  "use strict";

  const btn = document.getElementById("ms-talk");
  const statusEl = document.getElementById("ms-talk-status");
  if (!btn) return;

  const FRAME_MS = 20;
  // Must not exceed WS_MAX_PAYLOAD in timps' src/ws.h.
  const WS_MAX_PAYLOAD = 1024;
  // Sample rates timps' talk_ws.c accepts via ?rate= (TALK_RATES there).
  const RATES_OK = [8000, 16000, 24000, 32000, 44100, 48000];
  const MAX_BUFFERED = 10 * WS_MAX_PAYLOAD;
  const PROBE_MAX_BACKOFF_MS = 30000;

  let base = null;
  let wsBase = null;
  let token = null;
  let tls = false;

  function timpsScheme(info) {
    if (!info) return "http";
    if (info.scheme === "both") {
      return window.location.protocol === "https:" ? "https" : "http";
    }
    if (info.scheme === "https" || info.scheme === "http") return info.scheme;
    return info.tls ? "https" : "http";
  }
  let stopped = false;

  let ws = null, ctx = null, spn = null, src = null, sink = null, mic = null;
  let state = "idle";
  let pending = null, pendN = 0, frameSamples = 0;
  let errTimer = null;

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function say(msg, isErr) {
    if (!statusEl) { if (isErr) console.warn("[talk] " + msg); return; }
    if (errTimer) { clearTimeout(errTimer); errTimer = null; }
    statusEl.textContent = msg || "";
    statusEl.style.display = msg ? "" : "none";
    statusEl.classList.toggle("text-danger", !!isErr);
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

  function showBtn() {
    btn.style.display = "";
    setBtn();
  }

  function ulawEncode(f) {
    let s = (f < -1 ? -1 : f > 1 ? 1 : f) * 32767 | 0;
    const sign = (s >> 8) & 0x80;
    if (sign) s = -s;
    if (s > 32635) s = 32635;
    s += 132;
    let exp = 7;
    for (let m = 0x4000; (s & m) === 0 && exp > 0; m >>= 1) exp--;
    const mant = (s >> (exp + 3)) & 0x0F;
    return ~(sign | (exp << 4) | mant) & 0xFF;
  }

  function bufSizeFor(rate) {
    let n = 256;
    while (n < 16384 && n * 2 <= rate * 0.03) n *= 2;
    return n;
  }

  function teardown() {
    if (spn) { try { spn.disconnect(); } catch (e) {} spn.onaudioprocess = null; spn = null; }
    if (src) { try { src.disconnect(); } catch (e) {} src = null; }
    if (sink) { try { sink.disconnect(); } catch (e) {} sink = null; }
    if (mic) { try { mic.getTracks().forEach((t) => t.stop()); } catch (e) {} mic = null; }
    if (ctx) { try { ctx.close(); } catch (e) {} ctx = null; }
    pending = null; pendN = 0; frameSamples = 0;
  }

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
    state = "idle";
    setBtn();
    say(msg || "", isErr);
  }

  function flushFrames() {
    if (!ws || ws.readyState !== WebSocket.OPEN) return;
    while (pendN >= frameSamples) {
      if (ws.bufferedAmount > MAX_BUFFERED) {
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

    const AC = window.AudioContext || window.webkitAudioContext;
    try {
      ctx = new AC({ sampleRate: 8000 });
    } catch (e) {
      try { ctx = new AC(); } catch (e2) { stop("No Web Audio support.", true); return; }
    }
    if (!ctx.createScriptProcessor) { stop("No Web Audio support.", true); return; }
    // iOS starts contexts suspended; only a click handler may resume them
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
      if (typeof ev.data !== "string") return;
      try {
        const j = JSON.parse(ev.data);
        if (j && j.rate && j.rate !== rate)
          console.warn("[talk] server negotiated " + j.rate + " Hz, we sent " + rate);
      } catch (e) {}
    };

    ws.onerror = () => { if (ws) stop("Talk channel failed.", true); };

    ws.onclose = (ev) => {
      if (!ws) return;
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
    const mode = (data && data.caps && data.caps.backchannel &&
                  data.caps.backchannel.talk_ws) | 0;
    if (!mode) return false;
    return mode >= 2 || tls;
  }

  async function init() {
    let info;
    if (window.timpsTokenInfo) {
      info = await window.timpsTokenInfo;
    } else {
      try {
        const res = await fetch("/x/timps-token.cgi", { cache: "no-store" });
        if (!res.ok) return;
        info = await res.json();
      } catch (e) {
        return;
      }
    }
    if (!info || !info.token) return;
    token = info.token;
    let host = location.hostname || "127.0.0.1";
    if (host.indexOf(":") >= 0 && host[0] !== "[") host = "[" + host + "]";
    const port = info.port || 8880;
    const sch = timpsScheme(info);
    tls = sch === "https";
    base = sch + "://" + host + ":" + port;
    wsBase = (tls ? "wss" : "ws") + "://" + host + ":" + port;

    window.addEventListener("pagehide", () => { stopped = true; stop(""); });

    if (!window.WebSocket) return;
    if (!navigator.mediaDevices || !navigator.mediaDevices.getUserMedia) return;
    if (!(window.AudioContext || window.webkitAudioContext)) return;

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
