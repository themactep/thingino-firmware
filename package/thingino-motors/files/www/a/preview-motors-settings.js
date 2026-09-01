/**
 * Preview-page PTZ settings modal (thingino-motors).
 *
 * A floating PTZ button over the live view opens a modal with quick
 * settings (preview control mode, pan/tilt speed) and PTZ presets.
 *
 * Settings read/write through /x/json-motor-params.cgi (control mode and
 * speeds; the CGI reloads the motors-daemon config on save so speed
 * changes apply without a reboot). Presets read/write through
 * /x/json-motor.cgi (d=pg / d=ps / d=pr / d=pd / d=pu / d=po).
 *
 * Plugin-owned file: registered via motors.webui.json `preview.scripts`,
 * injected into the preview page at build time.
 */
(function () {
  "use strict";

  const PARAMS_ENDPOINT = "/x/json-motor-params.cgi";
  const MOTOR_ENDPOINT = "/x/json-motor.cgi";

  function normalizeControlMode(value) {
    return value === "continuous" ? "continuous" : "step";
  }

  async function loadParams() {
    const res = await fetch(PARAMS_ENDPOINT, { cache: "no-store" });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  async function saveParams(fields) {
    const res = await fetch(PARAMS_ENDPOINT, {
      method: "POST",
      headers: { "Content-Type": "application/x-www-form-urlencoded" },
      body: new URLSearchParams(fields).toString(),
      cache: "no-store",
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    return res.json();
  }

  async function loadPresets() {
    const res = await fetch(
      `${MOTOR_ENDPOINT}?${new URLSearchParams({ d: "pg" }).toString()}`,
      { cache: "no-store" },
    );
    const payload = await res.json().catch(() => null);
    if (!res.ok || !payload || payload.result !== "success") {
      const message = payload && payload.error && payload.error.message;
      throw new Error(message || `HTTP ${res.status}`);
    }
    return payload.message && Array.isArray(payload.message.presets)
      ? payload.message.presets
      : [];
  }

  async function presetAction(action, extra) {
    const params = new URLSearchParams({ d: action });
    Object.entries(extra || {}).forEach(([k, v]) => params.set(k, v));
    const res = await fetch(`${MOTOR_ENDPOINT}?${params.toString()}`);
    const payload = await res.json().catch(() => null);
    if (!res.ok || !payload || payload.result !== "success") {
      const message = payload && payload.error && payload.error.message;
      throw new Error(message || `HTTP ${res.status}`);
    }
    return (payload.message && payload.message.status) || "OK";
  }

  // -- modal markup ----------------------------------------------------
  const MODAL_HTML =
    '<div class="modal fade" id="ptzModal" tabindex="-1" aria-labelledby="ptzModalLabel" aria-hidden="true">' +
    '  <div class="modal-dialog modal-lg">' +
    '    <div class="modal-content">' +
    '      <div class="modal-header">' +
    '        <h5 class="modal-title" id="ptzModalLabel">PTZ Settings</h5>' +
    '        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>' +
    "      </div>" +
    '      <div class="modal-body">' +
    '        <ul class="nav nav-tabs" role="tablist">' +
    '          <li class="nav-item" role="presentation">' +
    '            <button class="nav-link active" id="ptz-settings-tab" data-bs-toggle="tab" data-bs-target="#ptz-settings-pane" type="button" role="tab" aria-controls="ptz-settings-pane" aria-selected="true">Movement</button>' +
    "          </li>" +
    '          <li class="nav-item" role="presentation">' +
    '            <button class="nav-link" id="ptz-presets-tab" data-bs-toggle="tab" data-bs-target="#ptz-presets-pane" type="button" role="tab" aria-controls="ptz-presets-pane" aria-selected="false">Presets</button>' +
    "          </li>" +
    "        </ul>" +
    '        <div class="tab-content pt-3">' +
    '          <div class="tab-pane fade show active" id="ptz-settings-pane" role="tabpanel" aria-labelledby="ptz-settings-tab">' +
    '            <p class="row">' +
    '              <label class="form-label col-4" for="ptz-preview-control-mode">Preview controls</label>' +
    '              <select class="form-select col" id="ptz-preview-control-mode">' +
    '                <option value="step">Step move (click / double-click)</option>' +
    '                <option value="continuous">Continuous move (press and hold)</option>' +
    "              </select>" +
    "            </p>" +
    '            <p class="row">' +
    '              <label class="form-label col-4" for="ptz-speed-pan">Pan speed</label>' +
    '              <input class="form-control col" type="number" id="ptz-speed-pan" min="0" placeholder="900">' +
    "            </p>" +
    '            <p class="row">' +
    '              <label class="form-label col-4" for="ptz-speed-tilt">Tilt speed</label>' +
    '              <input class="form-control col" type="number" id="ptz-speed-tilt" min="0" placeholder="900">' +
    "            </p>" +
    "          </div>" +
    '          <div class="tab-pane fade" id="ptz-presets-pane" role="tabpanel" aria-labelledby="ptz-presets-tab">' +
    '            <div class="d-flex gap-2 mb-3">' +
    '              <input type="text" class="form-control" id="ptz-preset-name" placeholder="Preset description, e.g. Front door" maxlength="64">' +
    '              <button type="button" class="btn btn-outline-primary text-nowrap" id="ptz-preset-save" title="Save current position as a preset">' +
    '                <i class="bi bi-plus-circle me-1"></i>Save' +
    "              </button>" +
    "            </div>" +
    '            <ul id="ptz-presets-list" class="list-group"></ul>' +
    '            <small id="ptz-presets-empty" class="text-secondary d-block mt-2">No presets yet. Move the camera (preview overlay) and save a position above.</small>' +
    "          </div>" +
    "        </div>" +
    "      </div>" +
    '      <div class="modal-footer">' +
    '        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Cancel</button>' +
    '        <button type="button" class="btn btn-primary" id="ptz-save">Save settings</button>' +
    "      </div>" +
    "    </div>" +
    "  </div>" +
    "</div>";

  // -- presets -----------------------------------------------------------
  let currentPresets = [];

  function renderPresets(presets) {
    currentPresets = presets || [];
    const list = $("#ptz-presets-list");
    if (!list) return;
    list.innerHTML = "";
    const empty = $("#ptz-presets-empty");
    if (empty) empty.classList.toggle("d-none", currentPresets.length > 0);
    currentPresets.forEach((p) => list.appendChild(createPresetRow(p)));
  }

  function createPresetRow(p) {
    const li = document.createElement("li");
    li.className = "list-group-item d-flex align-items-center gap-2";
    li.dataset.id = String(p.id);

    const handle = document.createElement("span");
    handle.className = "bi bi-grip-vertical drag-handle text-secondary";
    handle.title = "Drag to reorder";
    handle.draggable = true;
    handle.addEventListener("dragstart", (e) => {
      e.dataTransfer.effectAllowed = "move";
      e.dataTransfer.setData("text/plain", String(p.id));
      li.classList.add("dragging");
    });
    handle.addEventListener("dragend", () => li.classList.remove("dragging"));

    const nameInput = document.createElement("input");
    nameInput.type = "text";
    nameInput.className = "form-control form-control-sm flex-grow-1 preset-name";
    nameInput.value = p.description || "";
    nameInput.maxLength = 64;
    nameInput.placeholder = `Preset ${p.id}`;

    const xInput = document.createElement("input");
    xInput.type = "number";
    xInput.className = "form-control form-control-sm preset-x";
    xInput.style.width = "4.5rem";
    xInput.value = p.x;
    xInput.min = "0";

    const yInput = document.createElement("input");
    yInput.type = "number";
    yInput.className = "form-control form-control-sm preset-y";
    yInput.style.width = "4.5rem";
    yInput.value = p.y;
    yInput.min = "0";

    const saveBtn = document.createElement("button");
    saveBtn.type = "button";
    saveBtn.className = "btn btn-sm btn-outline-success";
    saveBtn.title = "Save description and coordinates";
    saveBtn.innerHTML = '<i class="bi bi-check-lg"></i>';

    const moveBtn = document.createElement("button");
    moveBtn.type = "button";
    moveBtn.className = "btn btn-sm btn-outline-primary";
    moveBtn.title = "Move to this preset";
    moveBtn.innerHTML = '<i class="bi bi-play-fill"></i>';

    const delBtn = document.createElement("button");
    delBtn.type = "button";
    delBtn.className = "btn btn-sm btn-outline-danger";
    delBtn.title = "Delete preset";
    delBtn.innerHTML = '<i class="bi bi-trash"></i>';

    saveBtn.addEventListener("click", () => {
      const description = nameInput.value.trim();
      if (!description) {
        if (typeof showAlert === "function")
          showAlert("warning", "Enter a description for the preset.", 3000);
        return;
      }
      const x = xInput.value.trim();
      const y = yInput.value.trim();
      if (!/^\d+$/.test(x) || !/^\d+$/.test(y)) {
        if (typeof showAlert === "function")
          showAlert("warning", "Coordinates must be whole numbers.", 3000);
        return;
      }
      runPresetAction("pu", { n: p.id, description, x, y });
    });

    moveBtn.addEventListener("click", () =>
      runPresetAction("pr", { n: p.id }),
    );
    delBtn.addEventListener("click", () =>
      runPresetAction("pd", { n: p.id }),
    );

    li.addEventListener("dragover", (e) => {
      if (e.dataTransfer && e.dataTransfer.types.includes("text/plain")) {
        e.preventDefault();
        e.dataTransfer.dropEffect = "move";
        li.classList.add("drop-target");
      }
    });
    li.addEventListener("dragleave", () => li.classList.remove("drop-target"));
    li.addEventListener("drop", (e) => {
      e.preventDefault();
      li.classList.remove("drop-target");
      const dragged = e.dataTransfer.getData("text/plain");
      if (dragged && dragged !== String(p.id)) {
        reorderPreset(dragged, String(p.id));
      }
    });

    li.append(handle, nameInput, xInput, yInput, saveBtn, moveBtn, delBtn);
    return li;
  }

  async function reorderPreset(draggedNumber, targetNumber) {
    const from = currentPresets.findIndex(
      (p) => String(p.id) === draggedNumber,
    );
    const to = currentPresets.findIndex(
      (p) => String(p.id) === targetNumber,
    );
    if (from === -1 || to === -1 || from === to) return;

    const moved = currentPresets.splice(from, 1)[0];
    currentPresets.splice(to, 0, moved);

    const order = currentPresets.map((p) => p.id).join(",");
    renderPresets(currentPresets);

    try {
      await presetAction("po", { order });
    } catch (err) {
      console.error("Failed to reorder presets", err);
      if (typeof showAlert === "function")
        showAlert("danger", `Reorder failed: ${err.message}`, 5000);
    }
    await refreshPresets();
  }

  async function refreshPresets() {
    try {
      renderPresets(await loadPresets());
    } catch (err) {
      console.error("Failed to load PTZ presets", err);
    }
  }

  async function runPresetAction(action, extra) {
    try {
      const status = await presetAction(action, extra);
      if (typeof showAlert === "function") showAlert("success", status, 3000);
      await refreshPresets();
    } catch (err) {
      console.error(`Preset action ${action} failed`, err);
      if (typeof showAlert === "function")
        showAlert("danger", `Preset action failed: ${err.message}`, 5000);
    }
  }

  // -- settings -----------------------------------------------------------
  function populateSettings(data) {
    const mode = $("#ptz-preview-control-mode");
    if (mode) mode.value = normalizeControlMode(data.preview_control_mode);
    const pan = $("#ptz-speed-pan");
    if (pan) pan.value = data.speed_pan ?? "";
    const tilt = $("#ptz-speed-tilt");
    if (tilt) tilt.value = data.speed_tilt ?? "";
  }

  async function saveSettings() {
    const btn = $("#ptz-save");
    if (!btn) return;

    const mode = normalizeControlMode($("#ptz-preview-control-mode").value);
    const pan = $("#ptz-speed-pan").value.trim();
    const tilt = $("#ptz-speed-tilt").value.trim();

    if (pan !== "" && !/^\d+$/.test(pan)) {
      if (typeof showAlert === "function")
        showAlert("warning", "Pan speed must be a whole number.", 4000);
      return;
    }
    if (tilt !== "" && !/^\d+$/.test(tilt)) {
      if (typeof showAlert === "function")
        showAlert("warning", "Tilt speed must be a whole number.", 4000);
      return;
    }

    const fields = { preview_control_mode: mode };
    if (pan !== "") fields.speed_pan = pan;
    if (tilt !== "") fields.speed_tilt = tilt;

    btn.disabled = true;
    try {
      const data = await saveParams(fields);
      if (window.motorParams) {
        if (data.preview_control_mode !== undefined)
          window.motorParams.preview_control_mode = data.preview_control_mode;
        if (data.speed_pan !== undefined)
          window.motorParams.speed_pan = data.speed_pan;
        if (data.speed_tilt !== undefined)
          window.motorParams.speed_tilt = data.speed_tilt;
      }
      if (typeof showAlert === "function")
        showAlert("success", "PTZ settings saved.", 4000);
      const modal = bootstrap.Modal.getInstance($("#ptzModal"));
      if (modal) modal.hide();
    } catch (err) {
      console.error("Failed to save PTZ settings", err);
      if (typeof showAlert === "function")
        showAlert("danger", `Failed: ${err.message}`, 6000);
    } finally {
      btn.disabled = false;
    }
  }

  // -- bootstrap ----------------------------------------------------------
  function init() {
    const style = document.createElement("style");
    style.textContent =
      "#ptz-presets-list .drag-handle{cursor:grab;user-select:none}" +
      "#ptz-presets-list .drag-handle:active{cursor:grabbing}" +
      "#ptz-presets-list li.dragging{opacity:.5}" +
      "#ptz-presets-list li.drop-target{outline:2px dashed var(--bs-primary)}";
    document.head.appendChild(style);

    document.body.insertAdjacentHTML("beforeend", MODAL_HTML);

    // PTZ button in the Live View card header, next to Reload.
    const frame = $("#frame");
    const img = $("#preview");
    const host =
      document.querySelector(".preview-header-actions") ||
      frame ||
      (img && img.parentNode) ||
      document.body;
    const btn = document.createElement("button");
    btn.type = "button";
    btn.className = "btn btn-outline-secondary";
    btn.id = "preview-ptz";
    btn.title = "PTZ settings";
    btn.innerHTML = '<i class="bi bi-arrows-move"></i> PTZ';
    host.appendChild(btn);

    btn.addEventListener("click", async () => {
      try {
        populateSettings(await loadParams());
      } catch (err) {
        console.error("Failed to load PTZ settings", err);
      }
      await refreshPresets();
      new bootstrap.Modal($("#ptzModal")).show();
    });

    $("#ptz-save").addEventListener("click", saveSettings);

    const presetSave = $("#ptz-preset-save");
    if (presetSave) {
      presetSave.addEventListener("click", async () => {
        const description = $("#ptz-preset-name").value.trim();
        if (!description) {
          if (typeof showAlert === "function")
            showAlert("warning", "Enter a description for the preset first.", 3000);
          return;
        }
        await runPresetAction("ps", { description });
        $("#ptz-preset-name").value = "";
      });
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
