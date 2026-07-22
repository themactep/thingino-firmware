/* preview-motion.js - live motion-grid overlay for the timps preview page.
 *
 * Draws the timps IMP_IVS detection grid over the video and highlights the
 * cells that currently report motion. The page fetches the per-boot timps
 * token once from /x/timps-token.cgi (authenticated WebUI session required)
 * and then SUBSCRIBES to the timps push stream:
 *   EventSource http://<host>:<port>/events?stream=motion&token=<tok>
 * timps pushes an "event: motion" frame whenever the grid state changes
 * (same JSON object as GET /control's "motion":
 * {available,enabled,cols,rows,active:[0/1,...],...}; active is row-major,
 * index = row*cols+col). EventSource cannot send custom headers, so the
 * token goes as ?token= - it may show up in access logs, which is accepted
 * on the LAN (the token unlocks /control + /events + viewing the HTTP media
 * endpoints, never RTSP). CORS + the OPTIONS preflight are handled by timps.
 * preview-timps.html primes window.timpsTokenInfo with a single shared
 * token fetch (its /stream.mp4 fetch reuses the token); this script uses
 * that when present and keeps its own fetch as a standalone fallback.
 *
 * FALLBACK: if EventSource is unavailable or keeps failing while /control
 * still answers (e.g. an old timpsd without /events, or events.enabled=0),
 * the overlay falls back to the previous behavior - polling GET /control at
 * ~4 Hz with the X-Timps-Token header - so nothing regresses. EventSource
 * reconnects by itself (the server sends "retry: 3000"); the stream is
 * closed while the tab is hidden and reopened when it becomes visible.
 *
 * The canvas is aligned to the video's DISPLAYED content rectangle
 * (object-fit: contain letterboxing is computed from videoWidth/videoHeight
 * vs the element box), so the grid matches the picture, not the element.
 * Fails soft: if the token/endpoint is unreachable or the build has no
 * IMP_IVS move API, the toggle button stays hidden and nothing is drawn.
 * The overlay auto-hides while motion detection is disabled and can be
 * toggled with the grid button (state kept in sessionStorage). The motor
 * joystick overlay is untouched (the canvas is pointer-events: none). */
(function () {
  "use strict";

  const POLL_MS = 250; // fallback poll rate, ~4 Hz
  const ES_MAX_ERRORS = 4; // consecutive EventSource errors before fallback
  const video = document.getElementById("ms-video");
  const canvas = document.getElementById("motion-overlay");
  const btn = document.getElementById("ms-motion");
  if (!video || !canvas || !btn) return;

  let base = null;   // http://<host>:<port>
  let token = null;
  let es = null;     // EventSource (push mode)
  let esErrors = 0;  // consecutive errors since the last successful open
  let fellBack = false; // once true, stay in polling mode
  let timer = null;  // polling fallback interval
  let busy = false;
  let last = null;   // last motion status object (or null)
  let on = sessionStorage.getItem("ms.motionOverlay") !== "0";

  function setBtn() {
    btn.classList.toggle("active", on);
    btn.title = on ? "Hide motion grid overlay" : "Show motion grid overlay";
  }

  /* displayed content rect of the object-fit:contain video inside its box */
  function contentRect() {
    // measure the display box from the (always-visible) video, falling back to
    // the canvas; never rely on the canvas alone (it may still be display:none)
    const bw = video.clientWidth || canvas.clientWidth;
    const bh = video.clientHeight || canvas.clientHeight;
    const vw = video.videoWidth, vh = video.videoHeight;
    if (!bw || !bh) return null;
    if (!vw || !vh) return { x: 0, y: 0, w: bw, h: bh }; // no metadata yet
    const scale = Math.min(bw / vw, bh / vh);
    const w = vw * scale, h = vh * scale;
    return { x: (bw - w) / 2, y: (bh - h) / 2, w, h };
  }

  function clear() {
    canvas.style.display = "none";
    if (rafId != null) { cancelAnimationFrame(rafId); rafId = null; }
  }

  /* motion "afterglow": timps reports a cell active only on the frame it moved,
   * then clears it, so raw highlights just flicker. Remember when each cell was
   * last active and keep drawing it - fading out over HOLD_MS - so movement is
   * actually visible. A rAF loop animates the fade between motion events. */
  const HOLD_MS = 1200;
  let holds = null;   // Float64Array: last-active timestamp per cell
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

  // draw once and keep animating (via rAF) while any cell is still fading
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
    // show the canvas BEFORE measuring it: a display:none element reports
    // clientWidth/Height 0, which made contentRect() bail so the overlay could
    // never become visible (chicken-and-egg deadlock).
    canvas.style.display = "";
    const rect = contentRect();
    if (!rect || rect.w < 8 || rect.h < 8) { clear(); return; }
    // match the canvas backing store to its CSS size (device pixels)
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
    // active cells with afterglow: full-strength when just triggered, fading to
    // 0 over HOLD_MS (driven by holds[], not the momentary st.active)
    const now = performance.now();
    for (let r = 0; r < rows; r++) {
      for (let c = 0; c < cols; c++) {
        const idx = r * cols + c;
        const age = holds && idx < holdN ? now - holds[idx] : Infinity;
        if (age >= HOLD_MS) continue;
        const k = 1 - age / HOLD_MS;            // 1 -> 0 fade factor
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
    // faint raster lines so the grid is visible even without motion
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

  /* ---- fallback path: 4 Hz GET /control polling (the pre-SSE behavior) */

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
    busy = true;
    try {
      last = await poll();
    } catch (e) {
      last = null; // endpoint gone (streamer restart?): hide, keep trying
    }
    busy = false;
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

  /* ---- push path: EventSource on /events?stream=motion ---- */

  function stopPush() {
    if (es) { es.close(); es = null; }
  }

  function startPush() {
    if (es || fellBack || !window.EventSource) return;
    es = new EventSource(base + "/events?stream=motion&token=" +
                         encodeURIComponent(token));
    es.addEventListener("motion", (e) => {
      esErrors = 0;
      try {
        last = JSON.parse(e.data);
      } catch (err) {
        last = null;
      }
      noteActive(last);
      ensureAnim();
    });
    es.onopen = () => { esErrors = 0; };
    es.onerror = () => {
      // EventSource reconnects on its own (server retry: 3000); only give
      // up for good - old timpsd without /events, events.enabled=0 - after
      // several consecutive failures without a single event in between
      esErrors++;
      if (esErrors >= ES_MAX_ERRORS || (es && es.readyState === EventSource.CLOSED)) {
        fellBack = true;
        stopPush();
        startPoll(); // nothing regresses: back to the 4 Hz poller
      }
    };
  }

  function pause() {
    stopPush();
    // the poll timer keeps running but tick() no-ops while hidden (cheap)
  }

  function resume() {
    if (fellBack) { tick(); return; }
    startPush();
    draw(last);
  }

  async function init() {
    let info;
    if (window.timpsTokenInfo) {
      // shared single fetch (primed by preview-timps.html for the player)
      info = await window.timpsTokenInfo;
    } else {
      try {
        const res = await fetch("/x/timps-token.cgi", { cache: "no-store" });
        if (!res.ok) return; // no bridge -> feature silently off
        info = await res.json();
      } catch (e) {
        return;
      }
    }
    if (!info || !info.token) return;
    token = info.token;
    let host = location.hostname || "127.0.0.1";
    if (host.indexOf(":") >= 0 && host[0] !== "[") host = "[" + host + "]"; // raw IPv6
    base = (info.tls ? "https" : "http") + "://" + host + ":" + (info.port || 8880);

    // probe once: only offer the overlay when this build HAS motion support
    let st;
    try {
      st = await poll();
    } catch (e) {
      return; // :8880 unreachable (HTTPS mixed content?) -> stay hidden
    }
    if (!st || !st.available) return;
    last = st;

    btn.style.display = "";
    setBtn();
    draw(last);
    btn.addEventListener("click", () => {
      on = !on;
      sessionStorage.setItem("ms.motionOverlay", on ? "1" : "0");
      setBtn();
      draw(last);
    });
    window.addEventListener("resize", () => draw(last));
    video.addEventListener("loadedmetadata", () => draw(last));

    // prefer the push stream; fall back to polling when it cannot work
    if (window.EventSource) startPush();
    else { fellBack = true; startPoll(); }

    document.addEventListener("visibilitychange", () => {
      if (document.hidden) pause();
      else resume();
    });
    window.addEventListener("pagehide", () => {
      stopPush();
      stopPoll();
    });
  }

  init();
})();
