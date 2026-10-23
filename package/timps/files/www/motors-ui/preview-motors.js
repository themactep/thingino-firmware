function runMotorCmd(args) {
  return fetch(`/x/json-motor.cgi?${args}`)
    .then((res) => res.json())
    .then(({ message }) => {
      const { xpos, ypos } = message || {};
      updatePositionDisplay(xpos, ypos);
      return message;
    });
}

const MOTOR_WS_TOKEN_URL = "/x/json-motor-token.cgi";
const MOTOR_WS_CONNECT_TIMEOUT_MS = 4000;
const MOTOR_WS_MAX_ATTEMPTS = 3;

let syncPositionTransport = function () {};

let syncControlAvailability = function () {};

const motorWs = (function () {
  let socket = null;
  let connecting = null;
  let attempts = 0;
  let seq = 1;
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
    return true;
  }

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
      if (typeof frame.x_max === "number") limits.x = frame.x_max;
      if (typeof frame.y_max === "number") limits.y = frame.y_max;
    }
    if (typeof frame.x === "number" && typeof frame.y === "number") {
      updatePositionDisplay(frame.x, frame.y);
    }
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
      return Promise.reject(new Error("no wss:// on an https:// page"));
    }
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
        }
        reject(new Error("connect timeout"));
      }, MOTOR_WS_CONNECT_TIMEOUT_MS);

      ws.onopen = () => {
        clearTimeout(timer);
        socket = ws;
        attempts = 0;
        console.info("motors: PTZ control over " + scheme + "://");
        if (pushIntervalMs) {
          try {
            ws.send(
              JSON.stringify({
                cmd: "subscribe",
                interval_ms: pushIntervalMs,
              }),
            );
          } catch (err) {
          }
        }
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
    addFrameListener: (fn) => {
      frameListeners.add(fn);
      return () => frameListeners.delete(fn);
    },
    givenUp: () => attempts >= MOTOR_WS_MAX_ATTEMPTS,
    subscribe: (intervalMs) => {
      pushIntervalMs = intervalMs;
      trySend({ cmd: "subscribe", interval_ms: intervalMs });
    },
    subscribedInterval: () => pushIntervalMs,
  };
})();

function normalizePreviewControlMode(value) {
  return value === "continuous" || value === "joystick" || value === "drag"
    ? value
    : "step";
}

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

function motorDirSigns(dir) {
  return {
    x: dir.includes("l") ? -1 : dir.includes("r") ? 1 : 0,
    y: dir.includes("d") ? -1 : dir.includes("u") ? 1 : 0,
  };
}

const MOTOR_HOME_SETTLE_MS = 2000;
const MOTOR_HOME_TIMEOUT_MS = 120000;

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

let motorPositionRenderer = null;

function updatePositionDisplay(xpos, ypos) {
  if (xpos === undefined || ypos === undefined) return;
  const x = Number(xpos);
  const y = Number(ypos);
  if (!Number.isFinite(x) || !Number.isFinite(y)) return;
  window.motorPosition = { xpos: x, ypos: y };
  if (motorPositionRenderer) motorPositionRenderer(x, y);
}

const motorPositionStream = (function () {
  let es = null;
  let warned = false;

  function stop() {
    if (!es) return;
    try {
      es.close();
    } catch (err) {
    }
    es = null;
  }

  function start() {
    if (es || !("EventSource" in window)) return;
    try {
      es = new EventSource("/x/json-motor-stream.cgi");
    } catch (err) {
      es = null;
      return;
    }
    es.addEventListener("message", (ev) => {
      let data;
      try {
        data = JSON.parse(ev.data);
      } catch (err) {
        return;
      }
      if (!data || data.xpos === undefined) return;
      updatePositionDisplay(data.xpos, data.ypos);
    });
    es.onerror = () => {
      if (!warned) {
        warned = true;
        console.warn("motors: position stream interrupted, retrying");
      }
    };
  }

  function sync() {
    if (motorWs.isOpen()) stop();
    else start();
  }

  return { sync, stop };
})();

syncPositionTransport = motorPositionStream.sync;


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
  if (!motorWs.enabledAtBuild()) setControlAvailability(false);

  motorWs.connect().then(syncPositionTransport);

  window.addEventListener("pageshow", (ev) => {
    if (ev.persisted) motorWs.connect().then(syncPositionTransport);
  });

  document.addEventListener("visibilitychange", () => {
    if (!document.hidden) motorWs.connect().then(syncPositionTransport);
  });

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
  let modeAbort = null;

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

    function stopContinuousMove() {
      if (!wsHolding) return;
      wsHolding = false;
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

    window.addEventListener("blur", stopContinuousMove, { signal });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) stopContinuousMove();
    }, { signal });

    if (signal) signal.addEventListener("abort", stopContinuousMove);
  }

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
      if (barY) barY.style.height = yMax ? (y / yMax) * 100 + "%" : "0";
      if (text) text.textContent = x + " / " + y;
    };
  }

  function bindJoystickControls(signal) {
    const stick = $("#motor-stick");
    const handle = $("#motor-stick-handle");
    if (!stick || !handle) {
      bindContinuousControls(signal);
      return;
    }

    $("#motor").classList.add("stick-mode");

    const GAP = 8;
    const MIN_RING = 110;
    const motorEl = $("#motor");
    const panEl = $(".motor-pos-pan");
    const tiltEl = $(".motor-pos-tilt");
    function sizeStick() {
      const frame = $(".ms-video-wrap") || $("#frame");
      if (!frame) return;
      const box = frame.getBoundingClientRect();
      if (!box.width || !box.height) return;

      // un-hide before measuring, or a hidden row reports a zero box and stays hidden
      if (panEl) panEl.style.display = "";
      if (tiltEl) tiltEl.style.display = "";
      const panReach = panEl
        ? GAP + panEl.getBoundingClientRect().height
        : 0;
      const tiltReach = tiltEl ? GAP + tiltEl.getBoundingClientRect().width : 0;

      const reserved = Math.min(
        box.width - 2 * tiltReach,
        box.height - 2 * panReach,
      );
      let size = Math.min(450, reserved * 0.92);
      let panFits = true;
      let tiltFits = true;

      if (size < MIN_RING) {
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
    const previewImg = $("#preview");
    if (previewImg) previewImg.addEventListener("load", sizeStick, { signal });

    const SEND_INTERVAL_MS = 90;
    const DEAD_ZONE = 0.12;

    const MINOR_AXIS_ON = 0.25;
    const MINOR_AXIS_OFF = 0.15;

    let dragging = false;
    let radius = 1;
    let centre = { x: 0, y: 0 };
    let vector = { x: 0, y: 0 };
    let minorActive = { x: false, y: false };
    let lastVectorId = 0;
    let lastSentAt = 0;
    let flushTimer = null;

    const dropFrameListener = motorWs.addFrameListener((frame) => {
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
        dragging = false;
        setControlAvailability(false, "connection lost mid-move");
      }
    }

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

    function gateMinorAxis(vx, vy) {
      const ax = Math.abs(vx);
      const ay = Math.abs(vy);
      if (!ax && !ay) {
        minorActive = { x: false, y: false };
        return { x: 0, y: 0 };
      }
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
      const scale = ((norm - DEAD_ZONE) / (1 - DEAD_ZONE)) * 1000;
      vector = gateMinorAxis(
        Math.round((dx / (dist || 1)) * scale),
        Math.round((-dy / (dist || 1)) * scale),
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
      // guarded: setPointerCapture can throw NotFoundError
      try {
        if (stick.setPointerCapture && ev.pointerId !== undefined) {
          stick.setPointerCapture(ev.pointerId);
        }
      } catch (err) {
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

    ["pointerup", "pointercancel", "lostpointercapture"].forEach((name) =>
      stick.addEventListener(name, endDrag, { signal }),
    );
    stick.addEventListener("contextmenu", (ev) => ev.preventDefault(), { signal });

    window.addEventListener("blur", endDrag, { signal });
    document.addEventListener("visibilitychange", () => {
      if (document.hidden) endDrag();
    }, { signal });

    if (signal)
      signal.addEventListener("abort", () => {
        endDrag();
        dropFrameListener();
      });
  }

  function bindDragControls(signal) {
    const surface = $("#motor-drag");
    if (!surface) {
      bindJoystickControls(signal);
      return;
    }

    const motorEl = $("#motor");
    if (motorEl) motorEl.classList.add("drag-mode");
    surface.hidden = false;
    surface.setAttribute("aria-hidden", "false");

    const SEND_INTERVAL_MS = 90;
    const MIN_DELTA_STEPS = 8;
    const TAP_PX = 6;
    const FALLBACK_MS = 1500;

    let dragging = false;
    let armed = false;
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
      if (vectorMode) sendVector();
      else sendAbs();
    }

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
      // guarded: setPointerCapture can throw NotFoundError
      try {
        if (surface.setPointerCapture && ev.pointerId !== undefined) {
          surface.setPointerCapture(ev.pointerId);
        }
      } catch (err) {
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

  function applyControlMode(mode) {
    mode = normalizePreviewControlMode(mode);
    if (mode === activeControlMode) return;

    if (modeAbort) modeAbort.abort();
    modeAbort = new AbortController();
    const signal = modeAbort.signal;

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

  if (!motorWs.enabledAtBuild()) {
    runMotorCmd("d=j");
  }
});
