(function () {
  "use strict";

  const POLL_MS = 250;
  const POLL_MAX_BACKOFF_MS = 8000;
  const PROBE_MAX_BACKOFF_MS = 30000;
  const ES_MAX_ERRORS = 4;
  const video = document.getElementById("ms-video");
  const canvas = document.getElementById("motion-overlay");
  const btn = document.getElementById("ms-motion");
  if (!video || !canvas || !btn) return;

  function timpsScheme(info) {
    if (!info) return "http";
    if (info.scheme === "both") {
      return window.location.protocol === "https:" ? "https" : "http";
    }
    if (info.scheme === "https" || info.scheme === "http") return info.scheme;
    return info.tls ? "https" : "http";
  }

  let base = null;
  let token = null;
  let es = null;
  let esErrors = 0;
  let fellBack = false;
  let timer = null;
  let busy = false;
  let last = null;
  let on = sessionStorage.getItem("ms.motionOverlay") !== "0";
  let pollFails = 0;
  let nextPollAt = 0;
  let btnShown = null;
  let stopped = false;

  function setBtn() {
    btn.classList.toggle("active", on);
    btn.title = on ? "Hide motion grid overlay" : "Show motion grid overlay";
  }

  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

  function applyAvailability(st) {
    const usable = !!(st && st.available && st.enabled);
    if (usable === btnShown) return;
    btnShown = usable;
    btn.style.display = usable ? "" : "none";
    if (usable) setBtn();
    else clear();
  }

  function contentRect() {
    const bw = video.clientWidth || canvas.clientWidth;
    const bh = video.clientHeight || canvas.clientHeight;
    const rt = window.msPreviewSize;
    const vw = video.videoWidth || (rt ? rt.w : 0);
    const vh = video.videoHeight || (rt ? rt.h : 0);
    if (!bw || !bh) return null;
    if (!vw || !vh) return { x: 0, y: 0, w: bw, h: bh };
    const scale = Math.min(bw / vw, bh / vh);
    const w = vw * scale, h = vh * scale;
    return { x: (bw - w) / 2, y: (bh - h) / 2, w, h };
  }

  function clear() {
    canvas.style.display = "none";
    if (rafId != null) { cancelAnimationFrame(rafId); rafId = null; }
  }

  const HOLD_MS = 1200;
  let holds = null;
  let holdN = 0;
  let rafId = null;

  function noteActive(st) {
    if (!st || !Array.isArray(st.active) || !(st.cols > 0) || !(st.rows > 0))
      return;
    const n = st.cols * st.rows;
    if (!holds || holdN !== n) { holds = new Float64Array(n); holdN = n; }
    const now = performance.now();
    for (let i = 0; i < n && i < st.active.length; i++)
      if (st.active[i]) holds[i] = now;
  }

  function anyLit(now) {
    if (!holds) return false;
    for (let i = 0; i < holdN; i++) if (now - holds[i] < HOLD_MS) return true;
    return false;
  }

  function ensureAnim() {
    if (rafId != null) return;
    const step = () => {
      rafId = null;
      draw(last);
      if (on && anyLit(performance.now())) rafId = requestAnimationFrame(step);
    };
    rafId = requestAnimationFrame(step);
  }

  function draw(st) {
    if (!on || !st || !st.available || !st.enabled ||
        !(st.cols > 0) || !(st.rows > 0)) {
      clear();
      return;
    }
    canvas.style.display = "";
    const rect = contentRect();
    if (!rect || rect.w < 8 || rect.h < 8) { clear(); return; }
    const dpr = window.devicePixelRatio || 1;
    const cw = Math.round(canvas.clientWidth * dpr);
    const chh = Math.round(canvas.clientHeight * dpr);
    if (canvas.width !== cw || canvas.height !== chh) {
      canvas.width = cw;
      canvas.height = chh;
    }
    const ctx = canvas.getContext("2d");
    ctx.setTransform(dpr, 0, 0, dpr, 0, 0);
    ctx.clearRect(0, 0, canvas.clientWidth, canvas.clientHeight);

    const { cols, rows } = st;
    const now = performance.now();
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const idx = r * cols + c;
        const age = holds && idx < holdN ? now - holds[idx] : Infinity;
        if (age >= HOLD_MS) continue;
        const k = 1 - age / HOLD_MS;
        const x0 = rect.x + (c * rect.w) / cols;
        const y0 = rect.y + (r * rect.h) / rows;
        const w = rect.w / cols, h = rect.h / rows;
        ctx.fillStyle = "rgba(255, 40, 40, " + (0.38 * k).toFixed(3) + ")";
        ctx.fillRect(x0, y0, w, h);
        ctx.strokeStyle = "rgba(255, 70, 70, " + (0.9 * k).toFixed(3) + ")";
        ctx.lineWidth = 1.5;
        ctx.strokeRect(x0 + 0.75, y0 + 0.75, w - 1.5, h - 1.5);
      }
    }
    ctx.strokeStyle = "rgba(255, 255, 255, 0.25)";
    ctx.lineWidth = 1;
    ctx.beginPath();
    for (let c = 0; c <= cols; c++) {
      const x = rect.x + (c * rect.w) / cols;
      ctx.moveTo(x, rect.y);
      ctx.lineTo(x, rect.y + rect.h);
    }
    for (let r = 0; r <= rows; r++) {
      const y = rect.y + (r * rect.h) / rows;
      ctx.moveTo(rect.x, y);
      ctx.lineTo(rect.x + rect.w, y);
    }
    ctx.stroke();
  }

  async function poll() {
    const res = await fetch(base + "/control", {
      headers: { "X-Timps-Token": token },
      cache: "no-store",
    });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    return data && data.motion ? data.motion : null;
  }

  async function tick() {
    if (document.hidden) return;
    if (!on) { clear(); return; }
    if (busy) return;
    if (performance.now() < nextPollAt) return;
    busy = true;
    try {
      last = await poll();
      pollFails = 0;
      nextPollAt = 0;
    } catch (e) {
      pollFails++;
      nextPollAt = performance.now() +
        Math.min(POLL_MAX_BACKOFF_MS, POLL_MS * Math.pow(2, pollFails));
      last = null;
    }
    busy = false;
    applyAvailability(last);
    noteActive(last);
    ensureAnim();
  }

  function startPoll() {
    if (timer) return;
    timer = setInterval(tick, POLL_MS);
  }

  function stopPoll() {
    if (timer) { clearInterval(timer); timer = null; }
  }

  function stopPush() {
    if (es) { es.close(); es = null; }
  }

  function startPush() {
    if (es || fellBack || !window.timpsApi) return;
    es = window.timpsApi.events("motion", (t, d) => {
      esErrors = 0;
      last = d;
      applyAvailability(last);
      noteActive(last);
      ensureAnim();
    }, (err, fatal) => {
      if (++esErrors >= ES_MAX_ERRORS || fatal) {
        fellBack = true;
        stopPush();
        startPoll();
      }
    });
  }

  function pause() {
    stopPush();
  }

  function resume() {
    if (fellBack) { tick(); return; }
    startPush();
    draw(last);
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
    base = timpsScheme(info) + "://" + host + ":" + (info.port || 8880);

    window.addEventListener("pagehide", () => {
      stopped = true;
      stopPush();
      stopPoll();
    });

    let st = null;
    for (let delay = 1000; !stopped; delay = Math.min(PROBE_MAX_BACKOFF_MS, delay * 2)) {
      try {
        st = await poll();
        break;
      } catch (e) {
        await sleep(delay);
      }
    }
    if (stopped || !st) return;
    if (!st.available) return;
    last = st;

    applyAvailability(last);
    draw(last);
    btn.addEventListener("click", () => {
      on = !on;
      sessionStorage.setItem("ms.motionOverlay", on ? "1" : "0");
      setBtn();
      draw(last);
    });
    window.addEventListener("resize", () => draw(last));
    video.addEventListener("loadedmetadata", () => draw(last));

    if (window.EventSource && window.timpsApi) startPush();
    else { fellBack = true; startPoll(); }

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) pause();
      else resume();
    });
  }

  init();
})();
