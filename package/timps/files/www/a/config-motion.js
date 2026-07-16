/* config-motion.js - NATIVE timps IMP_IVS grid motion detection settings.
 *
 * Talks DIRECTLY to the timps streamer over window.timpsApi (GET/POST /control,
 * per-boot token) - no /x/json-prudynt.cgi bridge.
 *   load: timpsApi.get() -> json.motion {available,enabled,cols,rows,
 *         max_cells,sensitivity,monitor_stream} (caps.motion carries the same
 *         available/max_cells). All settings apply LIVE (timps stops and
 *         recreates its IVS grid) and persist.
 *   save: timpsApi.set({motion:{key:val}}); timps clamps cols*rows to the
 *         SDK cell budget, so we re-read once and re-apply the (possibly
 *         clamped) echo. When motion is unavailable (no IMP_IVS move API) or
 *         timps is unreachable the whole page is greyed with a notice.
 *
 * Kept lean (embedded target): no libraries, no polling, changes fire on
 * 'change' only. */
(function () {
  "use strict";

  const MAX_AXIS = 16; // sane UI cap per axis even on 52-cell SDKs

  const els = {
    enabled: $("#motion_enabled"),
    cols: $("#motion_cols"),
    rows: $("#motion_rows"),
    stream: $("#motion_monitor_stream"),
    sens: $("#motion_sensitivity"),
    sensValue: $("#motion_sensitivity_value"),
    unavailable: $("#motion-unavailable"),
    capsNote: $("#motion-caps-note"),
    gridPreview: $("#motion-grid-preview"),
  };
  const controls = [els.enabled, els.cols, els.rows, els.stream, els.sens];

  let maxCells = 0; // unknown until the first echo
  let loading = true; // suppress change handlers while populating

  function showAlert(variant, message, timeout = 6000) {
    if (window.showAlert && typeof window.showAlert === "function") {
      window.showAlert(variant, message, timeout);
    } else {
      console.log(`[${variant}] ${message}`);
    }
  }

  function setDisabled(disabled) {
    controls.forEach((el) => {
      if (el) el.disabled = disabled;
    });
  }

  function markUnavailable(message) {
    setDisabled(true);
    if (els.unavailable) {
      els.unavailable.classList.remove("d-none");
      if (message) els.unavailable.textContent = message;
    }
  }

  /* rebuild one axis selector: 1..limit, keeping the current value */
  function fillAxis(select, limit, current) {
    if (!select) return;
    const cur = current || Number(select.value) || 1;
    select.innerHTML = "";
    for (let i = 1; i <= limit; i++) {
      const opt = document.createElement("option");
      opt.value = String(i);
      opt.textContent = String(i);
      select.appendChild(opt);
    }
    select.value = String(Math.min(cur, limit));
  }

  /* limit each axis so cols*rows <= max_cells (given the OTHER axis' value) */
  function rebuildAxisLimits(cols, rows) {
    if (!maxCells) return;
    const colLimit = Math.min(MAX_AXIS, Math.max(1, Math.floor(maxCells / rows)), maxCells);
    const rowLimit = Math.min(MAX_AXIS, Math.max(1, Math.floor(maxCells / cols)), maxCells);
    fillAxis(els.cols, colLimit, cols);
    fillAxis(els.rows, rowLimit, rows);
  }

  function drawGridPreview(cols, rows) {
    const grid = els.gridPreview;
    if (!grid) return;
    grid.style.gridTemplateColumns = `repeat(${cols}, 1fr)`;
    grid.style.gridTemplateRows = `repeat(${rows}, 1fr)`;
    grid.innerHTML = "";
    const n = cols * rows;
    for (let i = 0; i < n; i++) {
      const cell = document.createElement("div");
      cell.className = "cell";
      grid.appendChild(cell);
    }
  }

  /* apply a motion query/echo result to the form */
  function applyMotion(mo) {
    if (!mo) return;
    if (mo.available === false || mo.available === 0) {
      markUnavailable();
      return;
    }
    if (typeof mo.max_cells === "number" && mo.max_cells > 0) {
      maxCells = mo.max_cells;
      if (els.capsNote) {
        els.capsNote.textContent =
          `This SoC supports up to ${maxCells} detection cells ` +
          `(columns × rows ≤ ${maxCells}).`;
      }
    }
    loading = true;
    const cols = typeof mo.cols === "number" && mo.cols > 0 ? mo.cols : 1;
    const rows = typeof mo.rows === "number" && mo.rows > 0 ? mo.rows : 1;
    rebuildAxisLimits(cols, rows);
    // timps reports enabled as 0/1; the old bridge used true/false - accept both
    if (els.enabled && mo.enabled !== undefined) els.enabled.checked = !!Number(mo.enabled);
    if (els.stream && typeof mo.monitor_stream === "number")
      els.stream.value = String(mo.monitor_stream);
    if (els.sens && typeof mo.sensitivity === "number") {
      els.sens.value = String(mo.sensitivity);
      if (els.sensValue) els.sensValue.textContent = String(mo.sensitivity);
    }
    drawGridPreview(cols, rows);
    setDisabled(false);
    loading = false;
  }

  async function loadMotion() {
    if (!window.timpsApi) {
      markUnavailable("timps-api.js not loaded.");
      return;
    }
    try {
      const json = await window.timpsApi.get();
      const mo = json && json.motion;
      // caps.motion carries available/max_cells too; merge as a fallback
      if (mo && json.caps && json.caps.motion) {
        if (mo.available === undefined) mo.available = json.caps.motion.available;
        if (!mo.max_cells) mo.max_cells = json.caps.motion.max_cells;
      }
      if (!mo) throw new Error("no motion data from streamer");
      applyMotion(mo);
    } catch (err) {
      console.error("Failed to load motion settings", err);
      markUnavailable(
        "Motion detection is not available (streamer unreachable or no " +
          `IMP_IVS move API): ${err.message || err}.`,
      );
    }
  }

  async function saveMotion(key, value) {
    if (loading) return;
    try {
      await window.timpsApi.set({ motion: { [key]: value } });
      // cols/rows may come back CLAMPED by timps: re-read the live state once
      const json = await window.timpsApi.get();
      if (json && json.motion) applyMotion(json.motion);
    } catch (err) {
      console.error(`Failed to update motion.${key}`, err);
      showAlert("danger", `Failed to update ${key.replace(/_/g, " ")}: ${err.message || err}`);
    }
  }

  function bind() {
    if (els.enabled)
      els.enabled.addEventListener("change", () => saveMotion("enabled", els.enabled.checked));
    if (els.cols)
      els.cols.addEventListener("change", () => saveMotion("cols", Number(els.cols.value)));
    if (els.rows)
      els.rows.addEventListener("change", () => saveMotion("rows", Number(els.rows.value)));
    if (els.stream)
      els.stream.addEventListener("change", () =>
        saveMotion("monitor_stream", Number(els.stream.value)),
      );
    if (els.sens) {
      els.sens.addEventListener("input", () => {
        if (els.sensValue) els.sensValue.textContent = els.sens.value;
      });
      els.sens.addEventListener("change", () =>
        saveMotion("sensitivity", Number(els.sens.value)),
      );
    }
  }

  // cols/rows/sensitivity all interact (axis limits are re-clamped against
  // max_cells), so a remote change just re-runs the normal full load instead
  // of patching one field - cheap (one GET) and always internally consistent.
  function onConfigEvent(type, data) {
    if (!data || loading) return;
    if (!data.resync && (typeof data.key !== "string" || data.key.indexOf("motion.") !== 0))
      return;
    const ae = document.activeElement;
    if (ae && controls.indexOf(ae) >= 0) return; // don't fight the user mid-edit
    loadMotion();
  }

  function init() {
    setDisabled(true); // greyed until the streamer confirms support
    drawGridPreview(5, 5);
    bind();
    loadMotion();
    if (window.timpsApi) window.timpsApi.events("config", onConfigEvent);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }
})();
