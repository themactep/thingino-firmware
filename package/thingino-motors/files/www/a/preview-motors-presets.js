// PTZ preset bar for the preview page (thingino-motors).
//
// Ten fixed slots map to motors.presets ids 0-9. A dim slot has no preset,
// a bright slot does, and the slot whose coordinates match the live motor
// position is highlighted. Click a set slot to move to it; long-press any
// slot to save the current position there (after confirmation).

(function () {
  "use strict";

  const MOTOR_ENDPOINT = "/x/json-motor.cgi";
  const PRESET_COUNT = 10;
  const LONG_PRESS_MS = 550;

  let presetsById = new Map();
  let position = window.motorPosition || null;
  let bar = null;
  const longPressMarks = new Map();

  function hasMotors() {
    const uiConfig = window.thinginoUIConfig || {};
    return !!(uiConfig.device && uiConfig.device.motors === true);
  }

  async function motorRequest(params) {
    const res = await fetch(
      `${MOTOR_ENDPOINT}?${new URLSearchParams(params).toString()}`,
      { cache: "no-store" },
    );
    const payload = await res.json().catch(() => null);
    if (!res.ok || !payload || payload.result !== "success") {
      const message = payload && payload.error && payload.error.message;
      throw new Error(message || `HTTP ${res.status}`);
    }
    return payload;
  }

  async function loadPresets() {
    const payload = await motorRequest({ d: "pg" });
    const list = payload.message && payload.message.presets;
    return Array.isArray(list) ? list : [];
  }

  async function loadPosition() {
    const payload = await motorRequest({ d: "j" });
    return payload.message || null;
  }

  function presetFor(id) {
    return presetsById.get(id) || null;
  }

  function isActive(id) {
    const preset = presetFor(id);
    if (!preset || !position || position.xpos === undefined) return false;
    return (
      Number(position.xpos) === Number(preset.x) &&
      Number(position.ypos) === Number(preset.y)
    );
  }

  function describeSlot(id) {
    const preset = presetFor(id);
    if (!preset) {
      return `Preset ${id} - empty. Long-press to save the current position.`;
    }
    const name = preset.description || `Preset ${id}`;
    return `Preset ${id} - ${name}. Click to move, long-press to overwrite.`;
  }

  function render() {
    if (!bar) return;
    for (const slot of bar.querySelectorAll(".ptz-preset-slot")) {
      const id = Number(slot.dataset.id);
      const set = Boolean(presetFor(id));
      slot.classList.toggle("is-set", set);
      slot.classList.toggle("is-active", isActive(id));
      const label = describeSlot(id);
      slot.title = label;
      slot.setAttribute("aria-label", label);
    }
  }

  async function refreshPresets() {
    try {
      const list = await loadPresets();
      presetsById = new Map();
      for (const preset of list) {
        const id = Number(preset.id);
        if (Number.isInteger(id)) presetsById.set(id, preset);
      }
      render();
    } catch (err) {
      console.error("Failed to load PTZ presets", err);
    }
  }

  async function getCurrentPosition() {
    try {
      const pos = await loadPosition();
      if (pos && pos.xpos !== undefined) {
        position = { xpos: String(pos.xpos), ypos: String(pos.ypos) };
        window.motorPosition = position;
        return position;
      }
    } catch (err) {
      // Fall back to the cached position below.
    }
    if (position && position.xpos !== undefined) return position;
    throw new Error("current position unavailable");
  }

  async function runMove(id) {
    const preset = presetFor(id);
    if (!preset) return;
    try {
      await motorRequest({ d: "pr", n: String(id) });
      // Optimistic highlight until the SSE stream reports the settled position.
      position = { xpos: String(preset.x), ypos: String(preset.y) };
      window.motorPosition = position;
      render();
    } catch (err) {
      console.error(`Move to preset ${id} failed`, err);
      if (typeof window.showAlert === "function") {
        window.showAlert(
          "danger",
          `Move to preset ${id} failed: ${err.message}`,
          5000,
        );
      }
    }
  }

  async function runSave(id) {
    const preset = presetFor(id);
    const overwrite = Boolean(preset);
    let confirmed = false;
    try {
      if (typeof window.confirm === "function") {
        confirmed = await window.confirm({
          title: overwrite ? `Overwrite preset ${id}` : `Save preset ${id}`,
          message: overwrite
            ? `Replace preset ${id} with the current camera position?`
            : `Save the current camera position as preset ${id}?`,
          confirmLabel: overwrite ? "Overwrite" : "Save",
          cancelLabel: "Cancel",
          intent: overwrite ? "warning" : "primary",
        });
      }
    } catch (err) {
      confirmed = false;
    }
    if (!confirmed) return;

    try {
      const pos = await getCurrentPosition();
      const description =
        preset && preset.description ? preset.description : `Preset ${id}`;
      await motorRequest({
        d: "pu",
        n: String(id),
        description,
        x: String(pos.xpos),
        y: String(pos.ypos),
      });
      await refreshPresets();
      if (typeof window.showAlert === "function") {
        window.showAlert("success", `Preset ${id} saved.`, 3000);
      }
    } catch (err) {
      console.error(`Save preset ${id} failed`, err);
      if (typeof window.showAlert === "function") {
        window.showAlert(
          "danger",
          `Save preset ${id} failed: ${err.message}`,
          5000,
        );
      }
    }
  }

  function onSlotClick(id) {
    const markedAt = longPressMarks.get(id);
    if (markedAt !== undefined) {
      longPressMarks.delete(id);
      if (Date.now() - markedAt < 1000) {
        // Click that ends a long press, not an intentional tap.
        return;
      }
    }
    if (!presetFor(id)) return;
    runMove(id);
  }

  function attachLongPress(slot, id) {
    let timer = null;

    const cancel = () => {
      if (timer) {
        clearTimeout(timer);
        timer = null;
      }
    };

    slot.addEventListener("pointerdown", (ev) => {
      if (ev.button !== undefined && ev.button !== 0) return;
      cancel();
      timer = window.setTimeout(() => {
        timer = null;
        longPressMarks.set(id, Date.now());
        runSave(id);
      }, LONG_PRESS_MS);
    });

    slot.addEventListener("pointerup", cancel);
    slot.addEventListener("pointercancel", cancel);
    slot.addEventListener("pointerleave", cancel);
    slot.addEventListener("lostpointercapture", cancel);
    slot.addEventListener("contextmenu", (ev) => ev.preventDefault());
  }

  function injectStyles() {
    if (document.getElementById("ptz-preset-styles")) return;
    const style = document.createElement("style");
    style.id = "ptz-preset-styles";
    style.textContent =
      ".ptz-preset-bar{display:flex;flex-wrap:wrap;gap:.4rem;margin-top:.75rem}" +
      ".ptz-preset-slot{width:2.5rem;height:2.5rem;border-radius:.5rem;" +
      "border:1px solid var(--bs-border-color);background:var(--bs-tertiary-bg);" +
      "color:var(--bs-secondary-color);font-weight:600;font-size:.8125rem;" +
      "line-height:1;display:inline-flex;align-items:center;justify-content:center;" +
      "cursor:pointer;user-select:none;touch-action:manipulation;" +
      "transition:background-color .15s,color .15s,box-shadow .15s}" +
      ".ptz-preset-slot.is-set{background:var(--bs-primary);" +
      "border-color:var(--bs-primary);color:#fff}" +
      ".ptz-preset-slot.is-active{box-shadow:0 0 0 2px var(--bs-body-bg)," +
      "0 0 0 4px var(--bs-warning)}" +
      ".ptz-preset-slot:focus-visible{outline:2px solid var(--bs-info);" +
      "outline-offset:2px}";
    document.head.appendChild(style);
  }

  function buildBar() {
    bar = document.createElement("div");
    bar.id = "ptz-preset-bar";
    bar.className = "ptz-preset-bar";
    bar.setAttribute("role", "group");
    bar.setAttribute("aria-label", "PTZ presets");
    for (let id = 0; id < PRESET_COUNT; id++) {
      const slot = document.createElement("button");
      slot.type = "button";
      slot.className = "ptz-preset-slot";
      slot.dataset.id = String(id);
      slot.textContent = String(id);
      slot.addEventListener("click", () => onSlotClick(id));
      attachLongPress(slot, id);
      bar.appendChild(slot);
    }
    const frame = document.getElementById("frame");
    const anchor = frame || document.getElementById("preview");
    if (anchor && anchor.parentNode) {
      anchor.insertAdjacentElement("afterend", bar);
      return;
    }
    // WebRTC preview pages (raptor/timps) have no #frame/#preview.
    const body = document.querySelector(".card-body");
    if (body) body.appendChild(bar);
  }

  function syncPosition() {
    const latest = window.motorPosition;
    if (!latest || latest.xpos === undefined) return;
    if (
      !position ||
      position.xpos === undefined ||
      Number(position.xpos) !== Number(latest.xpos) ||
      Number(position.ypos) !== Number(latest.ypos)
    ) {
      position = { xpos: String(latest.xpos), ypos: String(latest.ypos) };
      render();
    }
  }

  async function init() {
    if (!hasMotors()) return;
    injectStyles();
    buildBar();
    await refreshPresets();
    try {
      const pos = await loadPosition();
      if (pos && pos.xpos !== undefined) {
        position = { xpos: String(pos.xpos), ypos: String(pos.ypos) };
        window.motorPosition = position;
      }
    } catch (err) {
      // preview-motors.js seeds window.motorPosition from the SSE stream.
    }
    render();
    window.setInterval(syncPosition, 500);

    document.addEventListener("visibilitychange", () => {
      if (!document.hidden) refreshPresets();
    });
    window.addEventListener("focus", refreshPresets);
    document.addEventListener("hidden.bs.modal", (ev) => {
      if (ev.target && ev.target.id === "ptzModal") refreshPresets();
    });
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
