/* PTZ joystick for the preview page. CGI transport only
 * (/x/json-motor.cgi) - always available, no daemon build flag needed.
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
    await runMotorCmd("d=r");
    if (Number.isFinite(x0) && Number.isFinite(y0)) {
      await sleep(800);
      await runMotorCmd("d=x&x=" + x0 + "&y=" + y0);
    }
  } else if (dir === "cc") {
    const cx = x_max / 2;
    const cy = y_max / 2;
    runMotorCmd("d=x&x=" + cx + "&y=" + cy);
  } else {
    const sign = motorDirSigns(dir);
    const x = sign.x * step;
    const y = sign.y * step;
    runMotorCmd("d=g&x=" + x + "&y=" + y);
  }
}

function updatePositionDisplay(xpos, ypos) {
  if (xpos === undefined) return;
  // Expose for other plugins/view models (e.g. the settings modal's
  // "capture current position" button), kept in sync from every CGI move
  // response so a reader always gets the latest value without polling
  // json-motor.cgi d=j itself. bindPositionReadout()'s own DOM bars are
  // separate and unaffected.
  window.motorPosition = { xpos, ypos };
}

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

  let timer;

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
    const intervalMs = 90;

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
      startCgiMove(dir);
    };

    // Bound to every way a press can end - a missed release leaves the
    // camera panning to its limit. Idempotent.
    function stopContinuousMove() {
      stopCgiMove();
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

  // Virtual analog stick. The drag deflection maps to a proportional nudge
  // size on the classic 90ms CGI tick - no live position push in this
  // transport, so the numeric pan/tilt readout stays at its placeholder.
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
    const DEAD_ZONE = 0.12; // felt dead zone

    let dragging = false;
    let radius = 1;
    let centre = { x: 0, y: 0 };
    let vector = { x: 0, y: 0 };
    let cgiInterval = null;

    // No speed field over CGI, so proportionality comes from nudge size
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
      vector = { x: 0, y: 0 };
      stopCgiNudges();
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
      updateFromPointer(ev);
      startCgiNudges();
    }, { signal });

    stick.addEventListener("pointermove", (ev) => {
      if (!dragging) return;
      ev.preventDefault();
      updateFromPointer(ev);
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

    // leaving mid-drag must stop the motor
    if (signal) signal.addEventListener("abort", endDrag);
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

  runMotorCmd("d=j");
});
