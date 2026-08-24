// OctoPrint-style jog controls for Thingino motors.
//
// Moves are fire-and-forget (json-motor.cgi returns immediately; the daemon
// dispatches each move on a detached thread). Live position arrives over an
// SSE stream instead of being echoed back per-request, so the control path is
// never blocked on a status round-trip.
//
// Two axes of control feel:
//   - "distance" (OctoPrint's step-size) selects how far one tap moves.
//   - "step" vs "continuous" chooses tap-to-move vs press-and-hold.

function runMotorCmd(args) {
  // Fire-and-forget: don't block on a JSON body; the SSE stream owns position.
  return fetch(`/x/json-motor.cgi?${args}`, { cache: "no-store" }).catch(
    () => null,
  );
}

function normalizePreviewControlMode(value) {
  return value === "continuous" ? "continuous" : "step";
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

// OctoPrint's distances array, scaled to this hardware. `steps` here is the
// Fixed per-tap jog distances in raw motor steps, independent per axis.
// Pan travels ~3700 steps, tilt ~1000, so tilt needs far fewer steps for the
// same apparent motion. Set small/medium/large to taste per axis; a single
// tap sends exactly the chosen axis' count (diagonals jog both axes at once).
const STEP_SIZES = {
  small: { pan: 25, tilt: 10 }, // fine nudge (default single tap)
  medium: { pan: 75, tilt: 25 }, // medium jog
  large: { pan: 200, tilt: 60 }, // coarse jump
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
// resolving to per-axis step counts. A move on only one axis ignores the
// other axis' count (straight tap); a diagonal jog sends both axes' counts.
async function moveMotor(dir, scaleName = currentStepName) {
  const step = STEP_SIZES[scaleName] ?? STEP_SIZES.medium;
  const { x: dx, y: dy } = dirToDelta(dir);
  runMotorCmd(`d=g&x=${step.pan * dx}&y=${step.tilt * dy}`);
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

// --- keyboard jog (arrows + distance keys, like OctoPrint's onKeyDown) ---
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
    ev.preventDefault();
    moveMotor(dir);
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

  const stepMode = normalizePreviewControlMode(
    window.motorParams.preview_control_mode,
  ) === "step";

  // One binding path for both modes: pointerdown fires immediately, matching
  // OctoPrint's click -> sendJog with no disambiguation watermark. Continuous
  // mode additionally starts a hold-repeat loop.
  $$(".jst a.s").forEach((el) => {
    const dir = el.dataset.dir;
    let holdInterval = null;

    const stopHold = () => {
      if (holdInterval) {
        clearInterval(holdInterval);
        holdInterval = null;
      }
    };

    const onDown = (ev) => {
      ev.preventDefault();
      if (el.setPointerCapture && ev.pointerId !== undefined) {
        el.setPointerCapture(ev.pointerId);
      }
      if (stepMode) {
        moveMotor(dir);
      } else {
        moveMotor(dir);
        stopHold();
        holdInterval = setInterval(() => moveMotor(dir), HOLD_INTERVAL_MS);
      }
    };

    el.addEventListener("pointerdown", onDown);
    el.addEventListener("pointerup", stopHold);
    el.addEventListener("pointerleave", stopHold);
    el.addEventListener("pointercancel", stopHold);
    el.addEventListener("lostpointercapture", stopHold);
    el.addEventListener("contextmenu", (ev) => ev.preventDefault());
  });

  // Center button: single tap centers, long/short is no longer needed since
  // we removed the dblclick watermark. Keep center + homing explicit.
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
