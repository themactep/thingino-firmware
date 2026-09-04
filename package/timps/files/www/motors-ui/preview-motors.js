/* PTZ joystick for the preview page.
 *
 * Two transports: CGI (/x/json-motor.cgi, always available) and WS
 * (motors-daemon, only when built with BR2_PACKAGE_THINGINO_MOTORS_WS -
 * window.thinginoUIConfig.device.motorsWs). The build flag alone doesn't
 * guarantee a usable socket (daemon config, https mixed-content), so
 * everything here checks "is the socket open right now" and falls back
 * to CGI per call.
 */

function runMotorCmd(args) {
  return fetch(`/x/json-motor.cgi?${args}`)
    .then((res) => res.json())
    .then(({ message }) => {
      const { xpos, ypos } = message || {};
      updatePositionDisplay(xpos, ypos);
      return message;
    });
}

function sleep(ms) {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

// WebSocket transport. Token via query string, not a header: the WebSocket
// constructor can't set request headers on the handshake (same as timps's
// EventSource); motors-daemon accepts ?token= for that reason.
const MOTOR_WS_TOKEN_URL = "/x/json-motor-token.cgi";
const MOTOR_WS_CONNECT_TIMEOUT_MS = 4000;
// After this many failed attempts, stay on CGI for the rest of the page's life.
const MOTOR_WS_MAX_ATTEMPTS = 3;

const motorWs = (function () {
  let socket = null;
  let connecting = null;
  let attempts = 0;
  let seq = 1;
  let frameListener = null;
  let pushIntervalMs = 0;
  const limits = { x: 0, y: 0 };

  function buildFlagSet() {
    const cfg = window.thinginoUIConfig || {};
    return !!(cfg.device && cfg.device.motorsWs === true);
  }

  function usable() {
    if (!buildFlagSet()) return false;
    if (attempts >= MOTOR_WS_MAX_ATTEMPTS) return false;
    return true; // https:// vs wss:// is decided later, in openSocket()
  }

  // https:// page must use wss:// (mixed content) or not connect at all -
  // never ws:// even if the daemon offers it, since an untrusted self-signed
  // wss:// cert has no browser prompt to fall back on.
  function socketScheme(info) {
    if (location.protocol !== "https:") return "ws";
    return info && info.tls === true ? "wss" : null;
  }

  function onMessage(ev) {
    let frame;
    try {
      frame = JSON.parse(ev.data);
    } catch (err) {
      return;
    }
    if (frame.type === "hello" || frame.type === "status") {
      // Daemon's own travel limits; 0 means unknown, fall back to fixed steps.
      if (typeof frame.x_max === "number") limits.x = frame.x_max;
      if (typeof frame.y_max === "number") limits.y = frame.y_max;
    }
    // Keep window.motorPosition current from every WS push too, not just
    // the CGI one-shot path - see updatePositionDisplay()'s own comment.
    if (typeof frame.x === "number" && typeof frame.y === "number") {
      updatePositionDisplay(frame.x, frame.y);
    }
    // Errors included - "unknown_cmd" is how a daemon older than the
    // vector command is detected.
    if (frameListener) frameListener(frame);
  }

  function openSocket(info) {
    const port = parseInt(info.port, 10) || 8089;
    const scheme = socketScheme(info);
    if (!scheme) {
      // https:// page, daemon has no cert: fall back to the CGI path
      return Promise.reject(new Error("no wss:// on an https:// page"));
    }
    // Bracket a raw IPv6 literal, the same way preview.html does when it
    // builds timps's base URL - location.hostname hands it back unbracketed.
    let host = location.hostname;
    if (host.indexOf(":") >= 0 && host[0] !== "[") host = "[" + host + "]";
    const url =
      scheme +
      "://" +
      host +
      ":" +
      port +
      "/ws?token=" +
      encodeURIComponent(info.token);

    return new Promise((resolve, reject) => {
      const ws = new WebSocket(url);
      const timer = setTimeout(() => {
        try {
          ws.close();
        } catch (err) {
          /* already gone */
        }
        reject(new Error("connect timeout"));
      }, MOTOR_WS_CONNECT_TIMEOUT_MS);

      ws.onopen = () => {
        clearTimeout(timer);
        socket = ws;
        attempts = 0;
        console.info("motors: PTZ control over " + scheme + "://");
        // Position pushes only subscribed when something draws them (see
        // subscribe()) - travel limits arrive unprompted in "hello" either way.
        if (pushIntervalMs) {
          try {
            ws.send(
              JSON.stringify({
                cmd: "subscribe",
                interval_ms: pushIntervalMs,
              }),
            );
          } catch (err) {
            /* the send below will report it */
          }
        }
        resolve(ws);
      };
      ws.onerror = () => {
        clearTimeout(timer);
        reject(new Error("socket error"));
      };
      ws.onclose = () => {
        if (socket === ws) socket = null;
      };
      ws.onmessage = onMessage;
    });
  }

  function connect() {
    if (!usable()) return Promise.resolve(null);
    if (socket && socket.readyState === WebSocket.OPEN) {
      return Promise.resolve(socket);
    }
    if (connecting) return connecting;

    attempts += 1;
    connecting = fetch(MOTOR_WS_TOKEN_URL, { cache: "no-store" })
      .then((res) => (res.ok ? res.json() : null))
      .then((info) => {
        if (!info || info.enabled === false || !info.token) {
          throw new Error("listener not available");
        }
        return openSocket(info);
      })
      .catch((err) => {
        console.warn(
          "motors: WebSocket control unavailable, using the CGI path",
          err,
        );
        socket = null;
        return null;
      })
      .then((ws) => {
        connecting = null;
        return ws;
      });

    return connecting;
  }

  // Synchronous: returns 0 (falsy) on failure so a half-open socket can't
  // swallow a stop; returns the stamped id on success (seq starts at 1, so
  // callers can treat it as a boolean too) for matching error frames back.
  function trySend(obj) {
    if (!socket || socket.readyState !== WebSocket.OPEN) return 0;
    try {
      obj.id = seq++;
      socket.send(JSON.stringify(obj));
      return obj.id;
    } catch (err) {
      console.warn("motors: WebSocket send failed", err);
      return 0;
    }
  }

  return {
    connect,
    trySend,
    isOpen: () => !!socket && socket.readyState === WebSocket.OPEN,
    limits,
    enabledAtBuild: buildFlagSet,
    setFrameListener: (fn) => {
      frameListener = fn;
    },
    // Safe before or after the socket opens; whichever is second sends it.
    subscribe: (intervalMs) => {
      pushIntervalMs = intervalMs;
      trySend({ cmd: "subscribe", interval_ms: intervalMs });
    },
  };
})();

function normalizePreviewControlMode(value) {
  return value === "continuous" || value === "joystick" ? value : "step";
}

function getPreviewControlMode() {
  const motorParams = window.motorParams || {};
  return normalizePreviewControlMode(motorParams.preview_control_mode);
}

async function ensureMotorParams() {
  if (window.motorParams) {
    return window.motorParams;
  }
  try {
    const response = await fetch("/x/json-motor-params.cgi", {
      cache: "no-store",
    });
    const motorParams = await response.json();
    window.motorParams = motorParams;
    return motorParams;
  } catch (error) {
    console.error("Failed to load motor parameters:", error);
    window.motorParams = {
      steps_pan: 0,
      steps_tilt: 0,
      pos_0_x: 0,
      pos_0_y: 0,
      preview_control_mode: "step",
    };
    return window.motorParams;
  }
}

// Axis sign from data-dir ("ul", "cr", "dc", ...); shared by step and hold mode.
function motorDirSigns(dir) {
  return {
    x: dir.includes("l") ? -1 : dir.includes("r") ? 1 : 0,
    y: dir.includes("d") ? -1 : dir.includes("u") ? 1 : 0,
  };
}

async function moveMotor(dir, steps = 100, d = "g") {
  // Use motor parameters loaded from backend
  const motorParams = window.motorParams || {
    steps_pan: 0,
    steps_tilt: 0,
    pos_0_x: 0,
    pos_0_y: 0,
  };
  const x_max = motorParams.steps_pan;
  const y_max = motorParams.steps_tilt;
  const x0 = Number(motorParams.pos_0_x);
  const y0 = Number(motorParams.pos_0_y);
  const step = x_max / steps;
  if (dir === "homing") {
    // Stays on CGI regardless of transport: one-shot, not a gesture.
    await runMotorCmd("d=r");
    if (Number.isFinite(x0) && Number.isFinite(y0)) {
      await sleep(800);
      await runMotorCmd("d=x&x=" + x0 + "&y=" + y0);
    }
  } else if (dir === "cc") {
    const cx = x_max / 2;
    const cy = y_max / 2;
    if (!motorWs.trySend({ cmd: "move", mode: "abs", x: cx, y: cy })) {
      runMotorCmd("d=x&x=" + cx + "&y=" + cy);
    }
  } else {
    const sign = motorDirSigns(dir);
    const x = sign.x * step;
    const y = sign.y * step;
    if (!motorWs.trySend({ cmd: "move", mode: "rel", x: x, y: y })) {
      runMotorCmd("d=g&x=" + x + "&y=" + y);
    }
  }
}

function updatePositionDisplay(xpos, ypos) {
  if (xpos === undefined) return;
  // Expose for other plugins/view models (e.g. the settings modal's
  // "capture current position" button) - kept in sync from BOTH transports
  // below (the CGI one-shot response and every WS position push), so a
  // reader always gets the latest value without polling json-motor.cgi d=j
  // itself. bindPositionReadout()'s own DOM bars are separate and unaffected.
  window.motorPosition = { xpos, ypos };
}

// upstream's keyboard-jog (Shift+arrow) feature is deliberately not ported
// here, same decision as this morning's merge: it depends on a
// `currentStepName` module-level variable (and the step-size UI that sets
// it) that this fork's own preview-motors.js never adopted, so pulling in
// just this commit's refinement of it would reference an undeclared
// variable. Revisit as one deliberate piece of work if this fork ever wants
// keyboard PTZ, not as a side effect of a routine upstream sync.

// --- initialization ----------------------------------------------------
document.addEventListener("DOMContentLoaded", async function () {
  const uiConfig = window.thinginoUIConfig || {};
  const hasMotors = uiConfig.device && uiConfig.device.motors === true;

  if (!hasMotors) {
    return;
  }
  await ensureMotorParams();

  const motorOverlay = $("#motor-overlay");
  if (motorOverlay) {
    motorOverlay.style.display = "";
  }

  // Not awaited: a slow/absent listener must not delay binding the controls.
  motorWs.connect();

  // A bfcache restore (browser back/forward) revives this exact DOM/JS state
  // without re-running DOMContentLoaded, so the socket connect() above never
  // fires again - the WebSocket that was open before navigating away is
  // already closed by the browser, and nothing would otherwise reconnect it.
  // connect() itself is a no-op if a socket is already open, so this is safe
  // to call on every non-bfcache pageshow too.
  window.addEventListener("pageshow", (ev) => {
    if (ev.persisted) motorWs.connect();
  });

  // Belt and braces: some browsers evict a long-backgrounded tab into the
  // same bfcache path (observed: Edge's tab-freeze after ~20 min hidden)
  // without reliably firing pageshow's persisted flag on the way back.
  // visibilitychange fires whenever the tab regains focus regardless of
  // *why* the socket died - idle discard, a network blip, the daemon
  // restarting - so this is the actual catch-all; the pageshow listener
  // above just covers the common case a little earlier.
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) motorWs.connect();
  });

  let timer;

  let renderPosition = null; // joystick mode's live pan/tilt readout, or null
  let activeControlMode = null;
  let modeAbort = null; // owns every listener the active mode registered

  function bindStepControls() {
    $$(".jst a.s").forEach((el) => {
      el.onclick = (ev) => {
        if (ev.detail === 1) {
          timer = setTimeout(() => {
            moveMotor(ev.target.dataset.dir, 100);
          }, 200);
        }
      };
      el.ondblclick = (ev) => {
        if (ev.detail === 2) {
          clearTimeout(timer);
          moveMotor(ev.target.dataset.dir, 10);
        }
      };
    });
  }

  function bindContinuousControls(signal) {
    let holdInterval = null;
    let wsHolding = false;
    const intervalMs = 90;

    // Hold-to-move over the socket: one command down, one stop up. The delta
    // is the full axis travel - motor_ctl_relative() clamps to the limit and
    // recomputes, so this means "go until the far end"; no limit (x_max 0)
    // falls back to nudges below.
    const startWsHold = (dir) => {
      const sign = motorDirSigns(dir);
      const params = window.motorParams || {};
      const xTravel = motorWs.limits.x || Number(params.steps_pan) || 0;
      const yTravel = motorWs.limits.y || Number(params.steps_tilt) || 0;
      if ((sign.x && !xTravel) || (sign.y && !yTravel)) return false;

      if (
        !motorWs.trySend({
          cmd: "move",
          mode: "rel",
          x: sign.x * xTravel,
          y: sign.y * yTravel,
        })
      ) {
        return false;
      }
      wsHolding = true;
      return true;
    };

    // Re-issue a small nudge every 90ms; ceasing to send them IS the stop.
    const stopCgiMove = () => {
      if (holdInterval) {
        clearInterval(holdInterval);
        holdInterval = null;
      }
    };

    const startCgiMove = (dir) => {
      stopCgiMove();
      moveMotor(dir, 100);
      holdInterval = setInterval(() => {
        moveMotor(dir, 100);
      }, intervalMs);
    };

    const startContinuousMove = (dir) => {
      if (!dir) return;
      stopContinuousMove();
      if (motorWs.isOpen() && startWsHold(dir)) return;
      startCgiMove(dir);
    };

    // Bound to every way a press can end - a missed release leaves the
    // camera panning to its limit. Idempotent.
    function stopContinuousMove() {
      stopCgiMove();
      if (wsHolding) {
        wsHolding = false;
        if (!motorWs.trySend({ cmd: "stop" })) {
          runMotorCmd("d=s"); // socket died mid-gesture, still moving
        }
      }
    }

    $$(".jst a.s").forEach((el) => {
      const stopHandler = () => stopContinuousMove();
      el.addEventListener("pointerdown", (ev) => {
        ev.preventDefault();
        if (el.setPointerCapture && ev.pointerId !== undefined) {
          el.setPointerCapture(ev.pointerId);
        }
        startContinuousMove(el.dataset.dir);
      }, { signal });
      el.addEventListener("pointerup", stopHandler, { signal });
      el.addEventListener("pointerleave", stopHandler, { signal });
      el.addEventListener("pointercancel", stopHandler, { signal });
      el.addEventListener("lostpointercapture", stopHandler, { signal });
      el.addEventListener("contextmenu", (ev) => ev.preventDefault(), { signal });
    });

    // A backgrounded tab gets no pointer event; catch it here too.
    window.addEventListener("blur", stopContinuousMove, { signal });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stopContinuousMove();
    }, { signal });

    // Switching mode mid-press must not leave the camera panning to its limit.
    if (signal) signal.addEventListener("abort", stopContinuousMove);
  }

  // Live pan/tilt readout, joystick mode only - a held stick runs toward a
  // limit the video gives no warning of. 200ms cadence (matches the
  // socket's own); the CSS transition smooths it further for free.
  function bindPositionReadout() {
    const wrap = $("#motor-pos");
    const barX = $("#motor-pos-x");
    const barY = $("#motor-pos-y");
    const text = $("#motor-pos-text");
    if (!wrap) return null;

    motorWs.subscribe(200);

    return function render(frame) {
      if (typeof frame.x !== "number" || typeof frame.y !== "number") return;
      const xMax = frame.x_max || motorWs.limits.x;
      const yMax = frame.y_max || motorWs.limits.y;
      if (barX) barX.style.width = xMax ? (frame.x / xMax) * 100 + "%" : "0";
      // tilt's bar is vertical (preview-motors.css), filled by height
      if (barY) barY.style.height = yMax ? (frame.y / yMax) * 100 + "%" : "0";
      if (text) text.textContent = frame.x + " / " + frame.y;
    };
  }

  // Virtual analog stick. The drag deflection goes over the wire as a
  // per-mille value, not a distance/speed - only the daemon knows travel
  // limits, speed cap, and (motor_ctl_vector) per-axis speed support.
  function bindJoystickControls(signal) {
    const stick = $("#motor-stick");
    const handle = $("#motor-stick-handle");
    if (!stick || !handle) {
      // stale manifest asset; degrade rather than nothing
      bindContinuousControls(signal);
      return;
    }

    $("#motor").classList.add("stick-mode");

    // Ring size: measured from the real preview box (timps's
    // ".ms-video-wrap" or the stock "#frame"), not a vw/vh guess, since
    // neither can know the stream's aspect ratio. --motor-stick-size lives
    // on #motor (not the ring): the readout rows are the ring's siblings
    // and custom properties only inherit downward.
    const GAP = 8; // matches the +8px offsets in preview-motors.css
    const MIN_RING = 110; // below this the ring stops being drag-able
    const motorEl = $("#motor");
    const panEl = $(".motor-pos-pan");
    const tiltEl = $(".motor-pos-tilt");
    function sizeStick() {
      const frame = $(".ms-video-wrap") || $("#frame");
      if (!frame) return;
      const box = frame.getBoundingClientRect();
      if (!box.width || !box.height) return;

      // Un-hide before measuring, or a row hidden on a previous run reports
      // a zero box and stays hidden forever.
      if (panEl) panEl.style.display = "";
      if (tiltEl) tiltEl.style.display = "";
      const panReach = panEl
        ? GAP + panEl.getBoundingClientRect().height
        : 0;
      const tiltReach = tiltEl ? GAP + tiltEl.getBoundingClientRect().width : 0;

      // Reserve the readout, then size the ring in what's left (92% for
      // a small margin) - has room for the readout by construction.
      const reserved = Math.min(
        box.width - 2 * tiltReach,
        box.height - 2 * panReach,
      );
      let size = Math.min(450, reserved * 0.92);
      let panFits = true;
      let tiltFits = true;

      if (size < MIN_RING) {
        // Too small for both: ring gets the frame, readout rows that don't
        // fit are dropped rather than left to overflow:hidden-clip.
        size = Math.max(
          MIN_RING,
          Math.min(450, Math.min(box.width, box.height) * 0.92),
        );
        panFits = size / 2 + panReach <= box.height / 2;
        tiltFits = size / 2 + tiltReach <= box.width / 2;
      }

      motorEl.style.setProperty("--motor-stick-size", size.toFixed(0) + "px");
      if (panEl) panEl.style.display = panFits ? "" : "none";
      if (tiltEl) tiltEl.style.display = tiltFits ? "" : "none";
    }
    sizeStick();
    window.addEventListener("resize", sizeStick, { signal });
    // img-fluid markup only reaches its real aspect ratio once the first
    // frame loads; timps's markup has no #preview, so this is a no-op there.
    const previewImg = $("#preview");
    if (previewImg) previewImg.addEventListener("load", sizeStick, { signal });

    const SEND_INTERVAL_MS = 90; // matches the CGI hold loop's cadence
    const DEAD_ZONE = 0.12; // felt dead zone; daemon's own is a smaller backstop

    let dragging = false;
    let radius = 1;
    let centre = { x: 0, y: 0 };
    let vector = { x: 0, y: 0 };
    let overSocket = false;
    let vectorRejected = false;
    let lastVectorId = 0;
    let lastSentAt = 0;
    let flushTimer = null;
    let cgiInterval = null;

    motorWs.setFrameListener((frame) => {
      if (renderPosition && (frame.type === "status" || frame.type === "hello"))
        renderPosition(frame);
      // Daemon predates the vector command: give up on the socket
      // permanently (not per-press) and finish the gesture on the CGI.
      if (
        frame.type === "error" &&
        frame.id === lastVectorId &&
        (frame.code === "unknown_cmd" || frame.code === "no_limits")
      ) {
        console.warn("motors: daemon rejected the vector command", frame.code);
        vectorRejected = true;
        if (dragging && overSocket) {
          motorWs.trySend({ cmd: "stop" });
          overSocket = false;
          startCgiNudges();
        }
      }
    });

    // CGI fallback: no speed field, so proportionality comes from nudge size
    // scaled by deflection, on the classic 90ms tick.
    function startCgiNudges() {
      stopCgiNudges();
      const params = window.motorParams || {};
      const stepX = Number(params.steps_pan) / 100 || 0;
      const stepY = Number(params.steps_tilt) / 100 || 0;
      cgiInterval = setInterval(() => {
        const x = Math.round((stepX * vector.x) / 1000);
        const y = Math.round((stepY * vector.y) / 1000);
        if (x || y) runMotorCmd("d=g&x=" + x + "&y=" + y);
      }, SEND_INTERVAL_MS);
    }

    function stopCgiNudges() {
      if (cgiInterval) {
        clearInterval(cgiInterval);
        cgiInterval = null;
      }
    }

    function sendVector() {
      lastSentAt = performance.now();
      lastVectorId = motorWs.trySend({
        cmd: "vector",
        x: vector.x,
        y: vector.y,
      });
      if (!lastVectorId) {
        // Socket died mid-drag, still moving: switch transports.
        overSocket = false;
        runMotorCmd("d=s");
        startCgiNudges();
      }
    }

    // Trailing-edge throttle: a leading-only one would drop the last sample
    // of a gesture, which is the one that says how fast to keep going.
    function queueVector() {
      const wait = SEND_INTERVAL_MS - (performance.now() - lastSentAt);
      if (wait <= 0) {
        if (flushTimer) {
          clearTimeout(flushTimer);
          flushTimer = null;
        }
        sendVector();
        return;
      }
      if (!flushTimer) {
        flushTimer = setTimeout(() => {
          flushTimer = null;
          // overSocket too: transport may have switched to CGI since queued
          if (dragging && overSocket) sendVector();
        }, wait);
      }
    }

    function updateFromPointer(ev) {
      let dx = ev.clientX - centre.x;
      let dy = ev.clientY - centre.y;
      const dist = Math.hypot(dx, dy);

      // Clamp to the ring, or the deflection has no upper bound.
      if (dist > radius) {
        dx = (dx / dist) * radius;
        dy = (dy / dist) * radius;
      }

      handle.style.transform = "translate(" + dx + "px," + dy + "px)";

      const norm = Math.min(dist, radius) / radius;
      if (norm < DEAD_ZONE) {
        vector = { x: 0, y: 0 };
        return;
      }
      // Rescale so the throw starts at the dead-zone edge, not 12% deflection.
      const scale = ((norm - DEAD_ZONE) / (1 - DEAD_ZONE)) * 1000;
      vector = {
        x: Math.round((dx / (dist || 1)) * scale),
        y: Math.round((-dy / (dist || 1)) * scale), // screen y is inverted vs logical y
      };
    }

    function endDrag() {
      if (!dragging) return;
      dragging = false;
      stick.classList.remove("dragging");
      handle.style.transform = "";
      if (flushTimer) {
        clearTimeout(flushTimer);
        flushTimer = null;
      }
      vector = { x: 0, y: 0 };
      stopCgiNudges();
      if (overSocket) {
        overSocket = false;
        if (!motorWs.trySend({ cmd: "stop" })) runMotorCmd("d=s");
      }
    }

    stick.addEventListener("pointerdown", (ev) => {
      ev.preventDefault();
      const box = stick.getBoundingClientRect();
      radius = box.width / 2;
      centre = { x: box.left + radius, y: box.top + box.height / 2 };
      dragging = true;
      stick.classList.add("dragging");
      // Guarded: setPointerCapture can throw NotFoundError, which would
      // otherwise skip binding the rest of the gesture entirely.
      try {
        if (stick.setPointerCapture && ev.pointerId !== undefined) {
          stick.setPointerCapture(ev.pointerId);
        }
      } catch (err) {
        // no capture; blur/visibilitychange below still catch a runaway drag
      }
      overSocket = motorWs.isOpen() && !vectorRejected;
      updateFromPointer(ev);
      if (overSocket) sendVector();
      else startCgiNudges();
    }, { signal });

    stick.addEventListener("pointermove", (ev) => {
      if (!dragging) return;
      ev.preventDefault();
      updateFromPointer(ev);
      if (overSocket) queueVector();
    }, { signal });

    // Every way a drag can end has to land here, same reasoning as the arrows.
    ["pointerup", "pointercancel", "lostpointercapture"].forEach((name) =>
      stick.addEventListener(name, endDrag, { signal }),
    );
    stick.addEventListener("contextmenu", (ev) => ev.preventDefault(), { signal });

    window.addEventListener("blur", endDrag, { signal });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) endDrag();
    }, { signal });

    // leaving mid-drag must stop the motor and the position-readout listener
    if (signal)
      signal.addEventListener("abort", () => {
        endDrag();
        motorWs.setFrameListener(null);
      });
  }

  // (Re-)bind the widget to one control mode; safe to call repeatedly since
  // aborting modeAbort tears down the previous mode's listeners first.
  function applyControlMode(mode) {
    mode = normalizePreviewControlMode(mode);
    if (mode === activeControlMode) return;

    if (modeAbort) modeAbort.abort();
    modeAbort = new AbortController();
    const signal = modeAbort.signal;

    // step mode's onclick/ondblclick aren't covered by the signal
    $$(".jst a.s").forEach((el) => {
      el.onclick = null;
      el.ondblclick = null;
    });
    const motorEl = $("#motor");
    if (motorEl) motorEl.classList.remove("stick-mode");

    activeControlMode = mode;
    renderPosition = mode === "joystick" ? bindPositionReadout() : null;

    if (mode === "joystick") {
      bindJoystickControls(signal);
    } else if (mode === "continuous") {
      bindContinuousControls(signal);
    } else {
      bindStepControls();
    }
  }

  applyControlMode(getPreviewControlMode());

  // re-render hook: preview-motors-settings.js fires this after a save
  window.previewMotors = window.previewMotors || {};
  window.previewMotors.applyControlMode = applyControlMode;
  document.addEventListener("preview-motors:control-mode", (ev) => {
    applyControlMode(
      (ev.detail && ev.detail.mode) || getPreviewControlMode(),
    );
  });

  $(".jst a.b").onclick = (ev) => {
    if (ev.detail === 1) {
      timer = setTimeout(() => {
        moveMotor("cc");
      }, 200);
    }
  };

  $(".jst a.b").ondblclick = (ev) => {
    clearTimeout(timer);
    moveMotor("homing");
  };

  // Over the socket this arrives unprompted in "hello"; only CGI needs to ask.
  if (!motorWs.enabledAtBuild()) {
    runMotorCmd("d=j");
  }
});
