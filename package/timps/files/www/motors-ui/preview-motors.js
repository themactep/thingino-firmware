/* PTZ joystick for the preview page.
 *
 * ONE control transport: the motors-daemon WebSocket. There used to be a CGI
 * fallback (/x/json-motor.cgi on a 90ms setInterval) and it was the source of
 * the jerky hold-to-move this page was reported for - one round trip through
 * uhttpd fork -> CGI -> auth scripts -> `motors` -> AF_UNIX costs 82-275ms,
 * i.e. more than the 90ms the loop allowed it, so presses backed up in
 * uhttpd's connection queue and the camera kept panning ~2s past release.
 * The socket does the same gesture in one "move" down and one "stop" up.
 *
 * Every timps build that has motors also has the socket: WS is
 * `default y if BR2_PACKAGE_THINGINO_STREAMER_TIMPS` and WS_TLS is
 * `default y if BR2_PACKAGE_THINGINO_UHTTPD_TLS_MBEDTLS`, so http:// pages
 * get ws:// and https:// pages get wss:// without either being configured
 * per camera. A build that has motors but no socket (WS switched off by hand,
 * or DW9714_ONLY) therefore has no control path at all now, and says so -
 * see setControlAvailability(); it does NOT silently resurrect the flood.
 *
 * Two POSITION transports, unchanged and deliberately still two: the socket's
 * own "status" pushes while it is open, and otherwise the
 * /x/json-motor-stream.cgi SSE stream that every build ships.
 * motorPositionStream below keeps exactly one of them live.
 */

// Position only - no control command goes through here any more. Kept because
// the SSE stream and the socket both need a one-shot seed on a build where
// the other one isn't running.
function runMotorCmd(args) {
  return fetch(`/x/json-motor.cgi?${args}`)
    .then((res) => res.json())
    .then(({ message }) => {
      const { xpos, ypos } = message || {};
      updatePositionDisplay(xpos, ypos);
      return message;
    });
}

// WebSocket transport. Token via query string, not a header: the WebSocket
// constructor can't set request headers on the handshake (same as timps's
// EventSource); motors-daemon accepts ?token= for that reason.
const MOTOR_WS_TOKEN_URL = "/x/json-motor-token.cgi";
const MOTOR_WS_CONNECT_TIMEOUT_MS = 4000;
// After this many failed attempts, give up on the socket for the rest of the
// page's life - and with it on PTZ control, which now has nowhere else to go.
const MOTOR_WS_MAX_ATTEMPTS = 3;

// Assigned by motorPositionStream below, once it exists. Called from every
// place the socket's state can change so exactly one position transport is
// ever running; a no-op until then, which covers the module-load window.
let syncPositionTransport = function () {};

// Same contract, for the control side: assigned once the widget exists, and
// called from the same two places the socket's state actually changes, so
// "PTZ unavailable" can never disagree with whether a socket is open.
let syncControlAvailability = function () {};

const motorWs = (function () {
  let socket = null;
  let connecting = null;
  let attempts = 0;
  let seq = 1;
  // A set, not one slot: the active control mode holds one for as long as it
  // is bound, and homing needs its own for the length of one sweep without
  // evicting it.
  const frameListeners = new Set();
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
    frameListeners.forEach((fn) => {
      try {
        fn(frame);
      } catch (err) {
        console.error("motors: frame listener threw", err);
      }
    });
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
        // Socket owns position from here; drop the SSE stream if it was
        // covering for it.
        syncPositionTransport();
        syncControlAvailability();
        resolve(ws);
      };
      ws.onerror = () => {
        clearTimeout(timer);
        reject(new Error("socket error"));
      };
      ws.onclose = () => {
        if (socket === ws) socket = null;
        // Nothing is pushing position any more - hand it back to the SSE
        // stream immediately rather than waiting for the 15s reconnect
        // backstop to give up.
        syncPositionTransport();
        syncControlAvailability();
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
    // Returns its own unsubscribe, so a caller can never detach someone
    // else's listener the way the old single-slot setter could.
    addFrameListener: (fn) => {
      frameListeners.add(fn);
      return () => frameListeners.delete(fn);
    },
    // Exhausted the attempt cap: no socket now and none later, so the caller
    // can stop offering controls rather than wait for a reconnect.
    givenUp: () => attempts >= MOTOR_WS_MAX_ATTEMPTS,
    // Safe before or after the socket opens; whichever is second sends it.
    subscribe: (intervalMs) => {
      pushIntervalMs = intervalMs;
      trySend({ cmd: "subscribe", interval_ms: intervalMs });
    },
    // So a caller that needs pushes temporarily can put back whatever the
    // active control mode had asked for (0 = none).
    subscribedInterval: () => pushIntervalMs,
  };
})();

function normalizePreviewControlMode(value) {
  return value === "continuous" || value === "joystick" || value === "drag"
    ? value
    : "step";
}

// Motor steps travelled when a drag crosses the full width of the video
// image, when motors.drag_steps_per_frame says nothing. steps_pan defaults to
// 4000 over the full ~355deg sweep, and a typical lens sees ~90deg of that.
const DRAG_STEPS_PER_FRAME = 1000;

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

// Home, then travel to the configured start point. Two steps, and the
// socket's `home` acks immediately and runs the sweep on a detached thread -
// so the second step has to wait for the sweep to actually end. Sending it
// early doesn't just arrive too soon: motor_steps() opens with
// wait_until_idle(5000), so it would time out mid-sweep and then fight it.
//
// No "home finished" frame in the protocol, so watch `moving` in the status
// pushes instead: up, then down.
const MOTOR_HOME_SETTLE_MS = 2000; // sweep hasn't started moving yet
const MOTOR_HOME_TIMEOUT_MS = 120000; // hard cap, a full sweep is tens of s

function waitForHomeSweep() {
  return new Promise((resolve) => {
    let sawMoving = false;
    let settle = null;
    let cap = null;
    let unsubscribe = null;
    let done = false;

    const finish = (ok) => {
      if (done) return;
      done = true;
      clearTimeout(settle);
      clearTimeout(cap);
      if (unsubscribe) unsubscribe();
      resolve(ok);
    };

    cap = setTimeout(() => finish(false), MOTOR_HOME_TIMEOUT_MS);
    // The sweep may not have spun up by the first push, so "never started" is
    // only given up on until the first moving:true arrives.
    settle = setTimeout(() => finish(false), MOTOR_HOME_SETTLE_MS);

    unsubscribe = motorWs.addFrameListener((frame) => {
      if (frame.type !== "status" && frame.type !== "hello") return;
      if (frame.moving === true) {
        sawMoving = true;
        clearTimeout(settle);
        return;
      }
      if (frame.moving === false && sawMoving) finish(true);
    });

    motorWs.trySend({ cmd: "status" });
  });
}

async function moveMotor(dir, steps = 100) {
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
    // Needs a subscription for the length of the sweep: step and continuous
    // mode draw no position and so subscribe to nothing.
    const resubscribe = motorWs.subscribedInterval();
    motorWs.subscribe(250);
    if (motorWs.trySend({ cmd: "home" })) {
      const swept = await waitForHomeSweep();
      if (swept && Number.isFinite(x0) && Number.isFinite(y0)) {
        motorWs.trySend({ cmd: "move", mode: "abs", x: x0, y: y0 });
      }
    }
    motorWs.subscribe(resubscribe);
  } else if (dir === "cc") {
    motorWs.trySend({
      cmd: "move",
      mode: "abs",
      x: x_max / 2,
      y: y_max / 2,
    });
  } else {
    const sign = motorDirSigns(dir);
    motorWs.trySend({
      cmd: "move",
      mode: "rel",
      x: sign.x * step,
      y: sign.y * step,
    });
  }
}

// --- live position -----------------------------------------------------

// Joystick mode's DOM readout (bindPositionReadout's closure), or null in the
// modes that draw no position. Module-level so every transport can reach it
// through the single funnel below instead of each wiring up its own.
let motorPositionRenderer = null;

// THE funnel. Every source of a position - the WS status/hello pushes, the
// SSE stream, and json-motor.cgi's d=j one-shot - lands here, so the DOM
// readout and window.motorPosition can never disagree about which transport
// is live.
function updatePositionDisplay(xpos, ypos) {
  if (xpos === undefined || ypos === undefined) return;
  // `motors -j` (and therefore the CGI and the SSE stream) reports these as
  // JSON strings; the WS frames report numbers. Normalize, or the readout
  // arithmetic below silently concatenates instead of adding.
  const x = Number(xpos);
  const y = Number(ypos);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return;
  // Expose for other plugins/view models (e.g. the settings modal's
  // "capture current position" button), so a reader always gets the latest
  // value without polling json-motor.cgi d=j itself.
  window.motorPosition = { xpos: x, ypos: y };
  if (motorPositionRenderer) motorPositionRenderer(x, y);
}

// SSE position stream - the transport every build has, and the only one a
// non-timps streamer gets (BR2_PACKAGE_THINGINO_MOTORS_WS defaults on only
// when timps is the streamer). Runs whenever the socket isn't up, which
// covers all four cases uniformly: no WS in this build at all, WS built but
// the connect attempts are spent, WS never reachable on this page (https://
// with no daemon cert), and a socket that opened and later died.
const motorPositionStream = (function () {
  let es = null;
  let warned = false;

  function stop() {
    if (!es) return;
    try {
      es.close();
    } catch (err) {
      /* already gone */
    }
    es = null;
  }

  function start() {
    if (es || !("EventSource" in window)) return;
    try {
      es = new EventSource("/x/json-motor-stream.cgi");
    } catch (err) {
      es = null; // blocked (CSP) or unsupported; nothing else to try
      return;
    }
    es.addEventListener("message", (ev) => {
      let data;
      try {
        data = JSON.parse(ev.data);
      } catch (err) {
        return; // malformed frame
      }
      // The CGI emits {"error":"..."} frames when `motors` is missing or
      // unreadable; those carry no position and must not clear the readout.
      if (!data || data.xpos === undefined) return;
      updatePositionDisplay(data.xpos, data.ypos);
    });
    es.onerror = () => {
      // EventSource reconnects on its own (the CGI even sends a retry:
      // hint), so there is nothing to do but say so once.
      if (!warned) {
        warned = true;
        console.warn("motors: position stream interrupted, retrying");
      }
    };
  }

  // Exactly one live-position source at a time.
  function sync() {
    if (motorWs.isOpen()) stop();
    else start();
  }

  return { sync, stop };
})();

syncPositionTransport = motorPositionStream.sync;

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

  // PTZ control is socket-only now, so "no socket" is a visible state rather
  // than a silent downgrade to the 90ms CGI flood this page used to do. Two
  // shapes of unavailable: permanent (no WS in this build, or the connect
  // attempt cap is spent - the camera needs a rebuild with
  // BR2_PACKAGE_THINGINO_MOTORS_WS, or an https:// page needs WS_TLS) and
  // transient (socket dropped; the 15s backstop below is already trying).
  const motorEl = $("#motor");
  let availabilityNote = null;

  function setControlAvailability(available, why) {
    if (!motorEl) return;
    motorEl.classList.toggle("ptz-unavailable", !available);
    if (available) {
      if (availabilityNote) availabilityNote.remove();
      availabilityNote = null;
      return;
    }
    if (!availabilityNote) {
      availabilityNote = document.createElement("div");
      availabilityNote.className = "ptz-unavailable-note";
      availabilityNote.setAttribute("role", "status");
      motorEl.appendChild(availabilityNote);
    }
    const permanent = !motorWs.enabledAtBuild() || motorWs.givenUp();
    availabilityNote.textContent = permanent
      ? "PTZ unavailable - camera needs a rebuild with the WebSocket control path"
      : "PTZ reconnecting" + (why ? " (" + why + ")" : "") + "...";
  }

  syncControlAvailability = function () {
    setControlAvailability(motorWs.isOpen());
  };
  // Before the first connect() resolves: a build with no WS path at all gets
  // the permanent notice straight away instead of a widget that looks live.
  if (!motorWs.enabledAtBuild()) setControlAvailability(false);

  // Not awaited: a slow/absent listener must not delay binding the controls.
  // The position transport IS decided on the result though - starting the SSE
  // stream first and cancelling it a moment later would spawn a CGI process
  // per page load on every WS build for nothing. connect() resolves
  // immediately (with null) when the build has no WS path at all, so the
  // CGI-only case pays no delay for this.
  motorWs.connect().then(syncPositionTransport);

  // A bfcache restore (browser back/forward) revives this exact DOM/JS state
  // without re-running DOMContentLoaded, so the socket connect() above never
  // fires again - the WebSocket that was open before navigating away is
  // already closed by the browser, and nothing would otherwise reconnect it.
  // connect() itself is a no-op if a socket is already open, so this is safe
  // to call on every non-bfcache pageshow too.
  // A bfcache restore also closed the EventSource, so sync afterwards either
  // way: it reopens the stream if the socket didn't come back.
  window.addEventListener("pageshow", (ev) => {
    if (ev.persisted) motorWs.connect().then(syncPositionTransport);
  });

  // Belt and braces: some browsers evict a long-backgrounded tab into the
  // same bfcache path (observed: Edge's tab-freeze after ~20 min hidden)
  // without reliably firing pageshow's persisted flag on the way back.
  // visibilitychange fires whenever the tab regains focus regardless of
  // *why* the socket died - idle discard, a network blip, the daemon
  // restarting - so this is the actual catch-all; the pageshow listener
  // above just covers the common case a little earlier.
  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) motorWs.connect().then(syncPositionTransport);
  });

  // ...and a periodic backstop, for the same reason preview.html grew one: a
  // long-backgrounded tab may come back without either of the two handlers
  // above firing at all (the socket's onclose can land while hidden, after
  // the last visibilitychange), leaving PTZ with no control path at all until
  // the user switches tabs again. Only while visible; connect() is a no-op
  // when a socket is already open, so this costs one readyState read every
  // 15s. Not armed at all on a build without the WS control path, where
  // connect() is a permanent no-op; and it only logs on an actual recovery,
  // so a camera whose listener is simply absent (the attempts cap in
  // connect() ends that quickly) stays quiet.
  if (motorWs.enabledAtBuild()) {
    setInterval(() => {
      if (document.hidden || motorWs.isOpen()) return;
      motorWs.connect().then((ws) => {
        syncPositionTransport();
        syncControlAvailability();
        if (ws) console.info("motors: PTZ socket was down while visible - reconnected");
      });
    }, 15000);
  }

  let timer;

  let activeControlMode = null;
  let modeAbort = null; // owns every listener the active mode registered

  // A step click is one "move rel" over the socket, same as it always was -
  // it just has no CGI fallback behind it now, so a click with no socket has
  // to say so rather than do nothing.
  function stepMove(dir, steps) {
    if (!motorWs.isOpen()) {
      setControlAvailability(false);
      return;
    }
    moveMotor(dir, steps);
  }

  function bindStepControls() {
    $$(".jst a.s").forEach((el) => {
      el.onclick = (ev) => {
        if (ev.detail === 1) {
          timer = setTimeout(() => {
            stepMove(ev.target.dataset.dir, 100);
          }, 200);
        }
      };
      el.ondblclick = (ev) => {
        if (ev.detail === 2) {
          clearTimeout(timer);
          stepMove(ev.target.dataset.dir, 10);
        }
      };
    });
  }

  function bindContinuousControls(signal) {
    let wsHolding = false;

    // Hold-to-move: one command down, one stop up, no repeat in between. The
    // delta is the full axis travel - motor_ctl_relative() clamps to the
    // limit and recomputes, so this means "go until the far end". An unknown
    // limit (x_max 0 and no configured steps_pan) is the one case that can't
    // be expressed this way, and there is no repeat-nudge path left to fall
    // back to, so it reports itself as unavailable instead.
    const startContinuousMove = (dir) => {
      if (!dir) return;
      stopContinuousMove();
      const sign = motorDirSigns(dir);
      const params = window.motorParams || {};
      const xTravel = motorWs.limits.x || Number(params.steps_pan) || 0;
      const yTravel = motorWs.limits.y || Number(params.steps_tilt) || 0;
      if ((sign.x && !xTravel) || (sign.y && !yTravel)) {
        setControlAvailability(false, "travel limits unknown");
        return;
      }
      if (
        !motorWs.trySend({
          cmd: "move",
          mode: "rel",
          x: sign.x * xTravel,
          y: sign.y * yTravel,
        })
      ) {
        setControlAvailability(false);
        return;
      }
      wsHolding = true;
    };

    // Bound to every way a press can end - a missed release leaves the
    // camera panning to its limit. Idempotent.
    function stopContinuousMove() {
      if (!wsHolding) return;
      wsHolding = false;
      // A failed stop means the socket went while the camera was moving. It
      // will keep going to the limit; say so rather than pretend otherwise.
      if (!motorWs.trySend({ cmd: "stop" })) {
        setControlAvailability(false, "connection lost mid-move");
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
  // limit the video gives no warning of. 200ms cadence over the socket
  // (matches its own); ~1s over the SSE stream, which is what the CGI-only
  // build has always offered. The CSS transition smooths either for free.
  //
  // Takes plain x/y rather than a WS frame: the SSE stream has no frame
  // shape to speak of, and the travel limits are better sourced here anyway
  // - the daemon's reported limits when there is a daemon, and the
  // configured steps_pan/steps_tilt otherwise (a frame's own x_max is 0 when
  // unknown, which used to collapse the bar to zero width).
  function bindPositionReadout() {
    const wrap = $("#motor-pos");
    const barX = $("#motor-pos-x");
    const barY = $("#motor-pos-y");
    const text = $("#motor-pos-text");
    if (!wrap) return null;

    motorWs.subscribe(200);

    return function render(x, y) {
      const params = window.motorParams || {};
      const xMax = motorWs.limits.x || Number(params.steps_pan) || 0;
      const yMax = motorWs.limits.y || Number(params.steps_tilt) || 0;
      if (barX) barX.style.width = xMax ? (x / xMax) * 100 + "%" : "0";
      // tilt's bar is vertical (preview-motors.css), filled by height
      if (barY) barY.style.height = yMax ? (y / yMax) * 100 + "%" : "0";
      if (text) text.textContent = x + " / " + y;
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

    const SEND_INTERVAL_MS = 90;
    const DEAD_ZONE = 0.12; // radial; felt dead zone, daemon's is a backstop

    // Minor-axis gate, as a fraction of the major axis, with hysteresis.
    //
    // The radial dead zone above says nothing about a pointer held NEAR an
    // axis: at full throw, 2-4deg off "right" still puts the minor axis at
    // 35-70 per-mille, right where the daemon's own per-axis dead zone sits.
    // A hand wobbling across that threshold flipped dir_y 0<->1 every update,
    // and the daemon reads any dir change as a reversal - full stop, decel
    // tail, restart. Measured: ~533 steps/s wobbling vs ~863 held steady.
    //
    // Two thresholds so a value parked on one edge can't chatter across it -
    // same reason the daemon now has two. The daemon-side fix alone would do
    // for correctness; this one is also what makes a near-axis hold behave
    // like the pure axis move the user was aiming for.
    const MINOR_AXIS_ON = 0.25; // engage the minor axis above this ratio
    const MINOR_AXIS_OFF = 0.15; // drop it again below this one

    let dragging = false;
    let radius = 1;
    let centre = { x: 0, y: 0 };
    let vector = { x: 0, y: 0 };
    let minorActive = { x: false, y: false };
    let lastVectorId = 0;
    let lastSentAt = 0;
    let flushTimer = null;

    // Position is NOT handled here any more: onMessage() already funnels
    // every frame's x/y through updatePositionDisplay(), which is what draws
    // the readout now. This listener is only for the error frames below.
    const dropFrameListener = motorWs.addFrameListener((frame) => {
      // Daemon has no vector command (older than the WS control path, or
      // limits it can't read). Nothing left to fall back to, so stop the
      // gesture and say the controls are out of action.
      if (
        frame.type === "error" &&
        frame.id === lastVectorId &&
        (frame.code === "unknown_cmd" || frame.code === "no_limits")
      ) {
        console.warn("motors: daemon rejected the vector command", frame.code);
        motorWs.trySend({ cmd: "stop" });
        dragging = false;
        setControlAvailability(false, "daemon rejected " + frame.code);
      }
    });

    function sendVector() {
      lastSentAt = performance.now();
      lastVectorId = motorWs.trySend({
        cmd: "vector",
        x: vector.x,
        y: vector.y,
      });
      if (!lastVectorId) {
        // Socket died mid-drag and the camera is still moving; nothing can be
        // sent to stop it, so surface that instead of failing quietly.
        dragging = false;
        setControlAvailability(false, "connection lost mid-move");
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
          if (dragging) sendVector();
        }, wait);
      }
    }

    // Zero whichever axis is only along for the ride, so a near-axis hold
    // sends a clean single-axis vector rather than one hovering on the
    // daemon's per-axis dead zone. Sticky: once engaged it stays engaged
    // until it falls under the lower ratio.
    function gateMinorAxis(vx, vy) {
      const ax = Math.abs(vx);
      const ay = Math.abs(vy);
      if (!ax && !ay) {
        // Centred: next deflection has to clear the upper threshold again.
        minorActive = { x: false, y: false };
        return { x: 0, y: 0 };
      }
      // Only the smaller axis is gated; the dominant one always passes.
      const minor = ax < ay ? "x" : "y";
      const major = minor === "x" ? "y" : "x";
      const ratio = minor === "x" ? ax / ay : ay / ax;
      const gate = minorActive[minor] ? MINOR_AXIS_OFF : MINOR_AXIS_ON;

      minorActive[major] = true;
      minorActive[minor] = ratio >= gate;

      return { x: minorActive.x ? vx : 0, y: minorActive.y ? vy : 0 };
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
        vector = gateMinorAxis(0, 0);
        return;
      }
      // Rescale so the throw starts at the dead-zone edge, not 12% deflection.
      const scale = ((norm - DEAD_ZONE) / (1 - DEAD_ZONE)) * 1000;
      vector = gateMinorAxis(
        Math.round((dx / (dist || 1)) * scale),
        Math.round((-dy / (dist || 1)) * scale), // screen y is inverted vs logical y
      );
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
      minorActive = { x: false, y: false };
      if (!motorWs.trySend({ cmd: "stop" })) {
        setControlAvailability(false, "connection lost mid-move");
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
      if (!motorWs.isOpen()) {
        dragging = false;
        stick.classList.remove("dragging");
        setControlAvailability(false);
        return;
      }
      updateFromPointer(ev);
      sendVector();
    }, { signal });

    stick.addEventListener("pointermove", (ev) => {
      if (!dragging) return;
      ev.preventDefault();
      updateFromPointer(ev);
      queueVector();
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

    // leaving mid-drag must stop the motor and drop this mode's listener
    if (signal)
      signal.addEventListener("abort", () => {
        endDrag();
        dropFrameListener();
      });
  }

  // Drag-to-pan. The joystick is a rate control; this one maps the drag
  // straight onto an absolute motor target, so the image content tracks
  // the finger like panning a photo, landing where it is released.
  // Streaming absolute targets is safe by construction: motor_ctl_absolute()
  // re-reads the live position and recomputes its own delta per command,
  // so a superseded target costs nothing.
  function bindDragControls(signal) {
    const surface = $("#motor-drag");
    if (!surface) {
      // stale manifest asset; degrade rather than nothing
      bindJoystickControls(signal);
      return;
    }

    const motorEl = $("#motor");
    if (motorEl) motorEl.classList.add("drag-mode");
    surface.hidden = false;
    surface.setAttribute("aria-hidden", "false");

    const SEND_INTERVAL_MS = 90; // matches the joystick's own cadence
    const MIN_DELTA_STEPS = 8; // below this the motor is already heading there
    const TAP_PX = 6;
    // no absolute-target data by now: fall back to rate control
    const FALLBACK_MS = 1500;

    let dragging = false;
    let armed = false; // absolute targets are computable
    let vectorMode = false;
    let fallbackTimer = null;
    let anchor = { x: 0, y: 0 };
    let anchorPos = { x: 0, y: 0 };
    let pointer = { x: 0, y: 0 };
    let stepsPerPx = 0;
    let target = { x: 0, y: 0 };
    let sent = null;
    let moved = 0;
    let lastSentAt = 0;
    let flushTimer = null;

    function limits() {
      const params = window.motorParams || {};
      return {
        x: motorWs.limits.x || Number(params.steps_pan) || 0,
        y: motorWs.limits.y || Number(params.steps_tilt) || 0,
      };
    }

    // The video's content box, not the element box: object-fit:contain
    // letterboxes the stream, and a steps-per-pixel scale that counted the
    // black bars would be wrong on every sensor that isn't 16:9.
    function contentBox() {
      const frame = $(".ms-video-wrap") || $("#frame");
      if (!frame) return null;
      const box = frame.getBoundingClientRect();
      if (!box.width || !box.height) return null;
      const video = $("#ms-video");
      const rt = window.msPreviewSize;
      const vw = (video && video.videoWidth) || (rt && rt.w) || 0;
      const vh = (video && video.videoHeight) || (rt && rt.h) || 0;
      const scale = vw && vh ? Math.min(box.width / vw, box.height / vh) : 0;
      return {
        cx: box.left + box.width / 2,
        cy: box.top + box.height / 2,
        w: scale ? vw * scale : box.width,
      };
    }

    function stepsPerFrame() {
      const v = Number((window.motorParams || {}).drag_steps_per_frame);
      return Number.isFinite(v) && v > 0 ? v : DRAG_STEPS_PER_FRAME;
    }

    function latch() {
      const pos = window.motorPosition;
      const lim = limits();
      const box = contentBox();
      if (!pos || (!lim.x && !lim.y) || !box || !box.w) return false;
      anchorPos = { x: pos.xpos, y: pos.ypos };
      stepsPerPx = stepsPerFrame() / box.w;
      return true;
    }

    function clamp(v, max) {
      return Math.round(Math.min(Math.max(v, 0), max));
    }

    function recompute() {
      if (!armed) return;
      const dx = pointer.x - anchor.x;
      const dy = pointer.y - anchor.y;
      const lim = limits();
      // both axes move opposite the drag (confirmed on hardware)
      const rawX = anchorPos.x - dx * stepsPerPx;
      const rawY = anchorPos.y + dy * stepsPerPx;
      target = { x: clamp(rawX, lim.x), y: clamp(rawY, lim.y) };
    }

    function sendAbs() {
      if (
        motorWs.trySend({ cmd: "move", mode: "abs", x: target.x, y: target.y })
      ) {
        sent = { x: target.x, y: target.y };
        return;
      }
      dragging = false;
      setControlAvailability(false, "connection lost mid-move");
    }

    function sendVector() {
      const box = contentBox();
      const span = (box ? box.w : 0) / 2 || 1;
      const deflect = (d) =>
        Math.max(-1000, Math.min(1000, Math.round((d / span) * 1000)));
      const vx = deflect(anchor.x - pointer.x);
      const vy = deflect(pointer.y - anchor.y);
      if (motorWs.trySend({ cmd: "vector", x: vx, y: vy })) return;
      dragging = false;
      setControlAvailability(false, "connection lost mid-move");
    }

    function sendNow() {
      lastSentAt = performance.now();
      // The socket's vector latches until the next one, so a pointer held
      // still needs no re-send to keep moving.
      if (vectorMode) sendVector();
      else sendAbs();
    }

    // trailing-edge throttle, like the joystick's
    function queueSend() {
      const wait = SEND_INTERVAL_MS - (performance.now() - lastSentAt);
      if (wait <= 0) {
        if (flushTimer) {
          clearTimeout(flushTimer);
          flushTimer = null;
        }
        sendNow();
        return;
      }
      if (!flushTimer) {
        flushTimer = setTimeout(() => {
          flushTimer = null;
          if (dragging) sendNow();
        }, wait);
      }
    }

    function aimAtTap() {
      const box = contentBox();
      if (!box) return;
      const lim = limits();
      target = {
        x: clamp(anchorPos.x + (pointer.x - box.cx) * stepsPerPx, lim.x),
        y: clamp(anchorPos.y - (pointer.y - box.cy) * stepsPerPx, lim.y),
      };
    }

    // Idempotent: blur, pointerup and lostpointercapture all race for one
    // gesture. commit=false means the gesture was aborted, not released.
    function endDrag(commit) {
      if (!dragging) return;
      dragging = false;
      surface.classList.remove("dragging");
      if (fallbackTimer) {
        clearTimeout(fallbackTimer);
        fallbackTimer = null;
      }
      if (flushTimer) {
        clearTimeout(flushTimer);
        flushTimer = null;
      }

      // A released absolute drag keeps travelling to its last target - that
      // landing point is the whole gesture. An aborted one, and every
      // rate-control session (which only moves while deflected), must stop.
      if (commit && armed && !vectorMode) {
        if (moved < TAP_PX) aimAtTap();
        if (!sent || target.x !== sent.x || target.y !== sent.y) sendNow();
      } else if (vectorMode || sent) {
        if (!motorWs.trySend({ cmd: "stop" })) {
          setControlAvailability(false, "connection lost mid-move");
        }
      }

      armed = false;
      vectorMode = false;
      sent = null;
    }

    surface.addEventListener("pointerdown", (ev) => {
      if (!ev.isPrimary) return;
      if (ev.pointerType === "mouse" && ev.button !== 0) return;
      ev.preventDefault();
      if (!motorWs.isOpen()) {
        setControlAvailability(false);
        return;
      }
      // Guarded: setPointerCapture can throw NotFoundError, which would
      // otherwise skip binding the rest of the gesture entirely.
      try {
        if (surface.setPointerCapture && ev.pointerId !== undefined) {
          surface.setPointerCapture(ev.pointerId);
        }
      } catch (err) {
        // no capture; blur/visibilitychange below still catch a runaway drag
      }
      dragging = true;
      moved = 0;
      sent = null;
      vectorMode = false;
      surface.classList.add("dragging");
      anchor = { x: ev.clientX, y: ev.clientY };
      pointer = anchor;
      armed = latch();
      if (!armed) {
        fallbackTimer = setTimeout(() => {
          fallbackTimer = null;
          if (!dragging) return;
          armed = latch();
          vectorMode = !armed;
          recompute();
          sendNow();
        }, FALLBACK_MS);
      }
      recompute();
    }, { signal });

    surface.addEventListener("pointermove", (ev) => {
      if (!dragging || !ev.isPrimary) return;
      ev.preventDefault();
      pointer = { x: ev.clientX, y: ev.clientY };
      moved = Math.max(moved, Math.hypot(pointer.x - anchor.x, pointer.y - anchor.y));
      recompute();
      if (!armed && !vectorMode) return;
      if (
        sent &&
        Math.abs(target.x - sent.x) < MIN_DELTA_STEPS &&
        Math.abs(target.y - sent.y) < MIN_DELTA_STEPS
      ) {
        return;
      }
      queueSend();
    }, { signal });

    surface.addEventListener("pointerup", () => endDrag(true), { signal });
    ["pointercancel", "lostpointercapture"].forEach((name) =>
      surface.addEventListener(name, () => endDrag(false), { signal }),
    );
    surface.addEventListener("contextmenu", (ev) => ev.preventDefault(), { signal });
    surface.addEventListener("dragstart", (ev) => ev.preventDefault(), { signal });

    window.addEventListener("blur", () => endDrag(false), { signal });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) endDrag(false);
    }, { signal });

    if (signal)
      signal.addEventListener("abort", () => {
        endDrag(false);
        surface.hidden = true;
        surface.setAttribute("aria-hidden", "true");
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
    if (motorEl) motorEl.classList.remove("stick-mode", "drag-mode");

    activeControlMode = mode;
    motorPositionRenderer =
      mode === "joystick" || mode === "drag" ? bindPositionReadout() : null;

    if (mode === "joystick") {
      bindJoystickControls(signal);
    } else if (mode === "drag") {
      bindDragControls(signal);
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
        stepMove("cc");
      }, 200);
    }
  };

  $(".jst a.b").ondblclick = (ev) => {
    clearTimeout(timer);
    stepMove("homing");
  };

  // Over the socket this arrives unprompted in "hello"; only CGI needs to ask.
  if (!motorWs.enabledAtBuild()) {
    runMotorCmd("d=j");
  }
});
