// OctoPrint-style jog controls for Thingino motors.
//
// Moves are fire-and-forget (json-motor.cgi returns immediately; the daemon
// dispatches each move on a detached thread). Live position arrives over an
// SSE stream instead of being echoed back per-request, so the control path is
// never blocked on a status round-trip.
//
// Two axes of control feel:
//   - "distance" (OctoPrint's step-size) selects how far one tap moves.
//   - Shift = single short step; plain press = continuous move while held.

function runMotorCmd(args) {
  // Fire-and-forget: don't block on a JSON body; the SSE stream owns position.
  return fetch(`/x/json-motor.cgi?${args}`, { cache: "no-store" }).catch(
    () => null,
  );
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

// Single per-tap jog distance in raw motor steps, uniform across both axes.
// Taps/diagonals send this same count to whichever axis is jogged, so the
// feel is identical panning or tilting regardless of each axis' travel range.
const STEP_SIZES = {
  small: 25, // fine nudge (default single tap)
  medium: 75, // medium jog
  large: 200, // coarse jump
};
let currentStepName = "small";

// Hold-to-repeat cadence (milliseconds between jogs while a button is held).
const HOLD_INTERVAL_MS = 60;

// Direction sectors from the .jst joystick: u/d/l/r + c center + diagonal
// remainder. Returns {x, y} logical direction signs (+1/0/-1 per axis).
function dirToDelta(dir) {
  let y = dir.includes("d") ? -1 : dir.includes("u") ? 1 : 0;
  let x = dir.includes("l") ? -1 : dir.includes("r") ? 1 : 0;
  // Diagonals keep full magnitude on each axis; straight moves already do.
  return { x, y };
}

// Send one relative jog. `scale` is a step-size key (OctoPrint distance),
// resolving to a uniform step count applied to whichever axis is jogged
// (a diagonal jog sends the same count to both axes).
async function moveMotor(dir, scaleName = currentStepName) {
  const steps = STEP_SIZES[scaleName] ?? STEP_SIZES.medium;
  const { x: dx, y: dy } = dirToDelta(dir);
  runMotorCmd(`d=g&x=${steps * dx}&y=${steps * dy}`);
}

function moveCenter() {
  const motorParams = window.motorParams || {};
  const x = Math.round((Number(motorParams.steps_pan) || 0) / 2);
  const y = Math.round((Number(motorParams.steps_tilt) || 0) / 2);
  runMotorCmd(`d=x&x=${x}&y=${y}`);
}

function moveHome() {
  runMotorCmd("d=r");
}

// Stop any in-flight continuous move. `d=s` triggers the daemon's
// motion_cancel_all(true) + MOTOR_STOP, halting the motor immediately.
function stopMotor() {
  runMotorCmd("d=s");
}

// --- live position via SSE -------------------------------------------
function startPositionStream() {
  if (!("EventSource" in window)) return;
  try {
    const es = new EventSource("/x/json-motor-stream.cgi");
    es.addEventListener("message", (ev) => {
      try {
        const data = JSON.parse(ev.data);
        if (data && data.xpos !== undefined) {
          updatePositionDisplay(data.xpos, data.ypos);
        }
      } catch (_) {
        /* ignore malformed frame */
      }
    });
    es.onerror = () => {
      // EventSource auto-reconnects; nothing to do here.
    };
  } catch (_) {
    /* EventSource unsupported or blocked */
  }
}

function updatePositionDisplay(xpos, ypos) {
  if (xpos === undefined) return;
  // Expose for other plugins/view models; no DOM position readout in the
  // minimal joystick overlay, but keep a cached value consistent with the
  // daemon so nothing else has to poll json-motor.cgi d=j.
  window.motorPosition = { xpos, ypos };
}

// --- keyboard jog (arrows + distance keys) ---
// Arrows only jog while Shift is held; plain arrows are left to the
// browser (scrolling) and other modifiers (Ctrl/Alt/Meta) to the OS.
// Each Shift+arrow press sends a single step; the browser's own key
// auto-repeat is ignored so one press stays one step.
function bindKeyboardControls() {
  const keyToDir = {
    ArrowUp: "u",
    ArrowDown: "d",
    ArrowLeft: "l",
    ArrowRight: "r",
  };
  const keyToStep = {
    "1": "small",
    "2": "medium",
    "3": "large",
  };

  document.addEventListener("keydown", (ev) => {
    // Don't hijack buttons/inputs.
    const tag = (ev.target && ev.target.tagName) || "";
    if (tag === "INPUT" || tag === "TEXTAREA" || tag === "SELECT") return;
    if (keyToStep[ev.key]) {
      currentStepName = keyToStep[ev.key];
      return;
    }
    const dir = keyToDir[ev.key];
    if (!dir) return;
    // Only intercept arrows when Shift is held.
    if (!ev.shiftKey) return;
    ev.preventDefault();
    // One step per press; ignore browser auto-repeat keydowns.
    if (ev.repeat) return;
    moveMotor(dir, currentStepName);
  });
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

  // Modifier model: Shift = single short step (fine nudge); plain press =
  // continuous move while held, stop on release. This mirrors OctoPrint's
  // modifier-based jog while using the daemon's fire-and-forget relative
  // moves plus an explicit stop on release.
  $$(".jst a.s").forEach((el) => {
    const dir = el.dataset.dir;
    let holdInterval = null;

    const stopHold = () => {
      if (holdInterval) {
        clearInterval(holdInterval);
        holdInterval = null;
      }
    };

    const release = () => {
      stopHold();
      stopMotor();
    };

    const onDown = (ev) => {
      ev.preventDefault();
      if (el.setPointerCapture && ev.pointerId !== undefined) {
        el.setPointerCapture(ev.pointerId);
      }
      if (ev.shiftKey) {
        // Shift: one short step, no hold-repeat.
        moveMotor(dir, "small");
      } else {
        // Plain: continuous while held.
        moveMotor(dir, currentStepName);
        stopHold();
        holdInterval = setInterval(() => moveMotor(dir, currentStepName), HOLD_INTERVAL_MS);
      }
    };

    el.addEventListener("pointerdown", onDown);
    el.addEventListener("pointerup", release);
    el.addEventListener("pointerleave", release);
    el.addEventListener("pointercancel", release);
    el.addEventListener("lostpointercapture", release);
    el.addEventListener("contextmenu", (ev) => ev.preventDefault());
  });

  // Center button: single tap centers; context menu homes.
  const centerBtn = $(".jst a.b");
  if (centerBtn) {
    centerBtn.addEventListener("pointerdown", (ev) => {
      ev.preventDefault();
      moveCenter();
    });
    centerBtn.addEventListener("contextmenu", (ev) => {
      ev.preventDefault();
      moveHome();
    });
  }

  bindKeyboardControls();
  startPositionStream();
});
