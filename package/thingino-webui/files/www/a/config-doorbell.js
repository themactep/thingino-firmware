(function () {
  const API = "/x/json-config-doorbell.cgi";
  let chimeData = {};
  let soundList = [];

  /* ── helpers ───────────────────────────────────────────────── */

  function $(sel) {
    return document.querySelector(sel);
  }
  function $$(sel) {
    return document.querySelectorAll(sel);
  }

  async function apiFetch(body) {
    const opts = { headers: { Accept: "application/json" } };
    if (body) {
      opts.method = "POST";
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    const res = await fetch(API, opts);
    const data = await res.json();
    if (data.error) throw new Error(data.error.message);
    return data;
  }

  function showMsg(text, type, timeout) {
    const el = $("#doorbell-msg");
    if (!el) return;
    el.className = "alert alert-" + type + " mt-2";
    el.textContent = text;
    el.hidden = false;
    if (timeout) setTimeout(() => (el.hidden = true), timeout);
  }

  /* ── load config ──────────────────────────────────────────── */

  async function loadConfig() {
    try {
      const data = await apiFetch();
      chimeData = data.chime || { units: {}, groups: {}, events: {} };
      soundList = data.sounds || [];
      renderAll();
    } catch (err) {
      showMsg("Failed to load config: " + err.message, "danger");
    }
  }

  /* ── render ───────────────────────────────────────────────── */

  function renderAll() {
    renderUnits();
    renderGroups();
    renderEvents();
  }

  function renderUnits() {
    const tbody = $("#units-tbody");
    if (!tbody) return;
    const units = chimeData.units || {};
    const ids = Object.keys(units);
    if (ids.length === 0) {
      tbody.innerHTML =
        '<tr><td colspan="4" class="text-muted">No chimes paired.</td></tr>';
      return;
    }
    tbody.innerHTML = ids
      .map((id) => {
        const u = units[id] || {};
        const name = u.name || "(unnamed)";
        const mac = id.replace(/(..)(..)(..)(..)/, "$1:$2:$3:$4");
        return `<tr>
          <td>${esc(name)}</td>
          <td><code>${esc(mac)}</code></td>
          <td><code class="text-muted">${esc(id)}</code></td>
          <td class="text-end">
            <button class="btn btn-sm btn-outline-primary play-btn" data-id="${esc(id)}">Test</button>
            <button class="btn btn-sm btn-outline-danger unpair-btn" data-id="${esc(id)}">Unpair</button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".play-btn").forEach((btn) => {
      btn.addEventListener("click", () => playChime(btn.dataset.id));
    });
    tbody.querySelectorAll(".unpair-btn").forEach((btn) => {
      btn.addEventListener("click", () => unpairChime(btn.dataset.id));
    });
  }

  function renderGroups() {
    const tbody = $("#groups-tbody");
    if (!tbody) return;
    const groups = chimeData.groups || {};
    const gnames = Object.keys(groups);
    if (gnames.length === 0) {
      tbody.innerHTML =
        '<tr><td colspan="3" class="text-muted">No groups defined.</td></tr>';
      return;
    }
    const ids = Object.keys(chimeData.units || {});
    tbody.innerHTML = gnames
      .map((g) => {
        const members = groups[g] || [];
        const memberNames = members
          .map((mid) => {
            const u = (chimeData.units || {})[mid];
            return u ? u.name || mid : mid;
          })
          .join(", ");
        return `<tr>
          <td><strong>${esc(g)}</strong></td>
          <td>${esc(memberNames) || "<span class='text-muted'>empty</span>"}</td>
          <td class="text-end">
            <button class="btn btn-sm btn-outline-secondary edit-group-btn" data-group="${esc(g)}" data-members="${esc(members.join(" "))}">Edit</button>
            <button class="btn btn-sm btn-outline-primary play-group-btn" data-group="${esc(g)}">Test</button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".play-group-btn").forEach((btn) => {
      btn.addEventListener("click", () => playGroup(btn.dataset.group));
    });
    tbody.querySelectorAll(".edit-group-btn").forEach((btn) => {
      btn.addEventListener("click", () =>
        editGroup(btn.dataset.group, btn.dataset.members),
      );
    });
  }

  function renderEvents() {
    const tbody = $("#events-tbody");
    if (!tbody) return;
    const events = chimeData.events || {};
    const enames = Object.keys(events);
    if (enames.length === 0) {
      tbody.innerHTML =
        '<tr><td colspan="5" class="text-muted">No events configured.</td></tr>';
      return;
    }
    tbody.innerHTML = enames
      .map((e) => {
        const ev = events[e] || {};
        return `<tr>
          <td><strong>${esc(e)}</strong></td>
          <td>${esc(ev.sound || "-")}</td>
          <td>${esc(ev.volume || "-")}</td>
          <td>${esc(ev.repeat || "-")}</td>
          <td class="text-end">
            <button class="btn btn-sm btn-outline-secondary edit-event-btn" data-event="${esc(e)}">Edit</button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".edit-event-btn").forEach((btn) => {
      btn.addEventListener("click", () => editEvent(btn.dataset.event));
    });
  }

  /* ── actions ──────────────────────────────────────────────── */

  async function playChime(id) {
    const sound = $("#test-sound")?.value || "DOORBELL_1";
    const vol = $("#test-volume")?.value || "5";
    const rep = $("#test-repeat")?.value || "1";
    try {
      const data = await apiFetch({
        action: "play",
        id,
        sound,
        volume: vol,
        repeat: rep,
      });
      showMsg(data.message || "Playing...", "info", 3000);
    } catch (err) {
      showMsg("Play failed: " + err.message, "danger");
    }
  }

  async function playGroup(group) {
    const sound = $("#test-sound")?.value || "DOORBELL_1";
    const vol = $("#test-volume")?.value || "5";
    const rep = $("#test-repeat")?.value || "1";
    try {
      const data = await apiFetch({
        action: "play-group",
        group,
        sound,
        volume: vol,
        repeat: rep,
      });
      showMsg(data.message || "Playing group...", "info", 3000);
    } catch (err) {
      showMsg("Play failed: " + err.message, "danger");
    }
  }

  async function unpairChime(id) {
    if (!confirm("Remove chime " + id + "?")) return;
    try {
      const data = await apiFetch({ action: "unpair", id });
      showMsg(data.message || "Removed.", "success", 3000);
      loadConfig();
    } catch (err) {
      showMsg("Unpair failed: " + err.message, "danger");
    }
  }

  function editGroup(group, membersStr) {
    const ids = Object.keys(chimeData.units || {});
    if (ids.length === 0) {
      showMsg("No chimes to add to group.", "warning", 3000);
      return;
    }
    const currentMembers = membersStr ? membersStr.split(" ") : [];
    let html = `<h6>Edit group: ${esc(group)}</h6>`;
    html += '<div class="mb-2">';
    ids.forEach((id) => {
      const u = chimeData.units[id] || {};
      const label = u.name ? u.name + " [" + id + "]" : id;
      const checked = currentMembers.includes(id) ? " checked" : "";
      html += `<div class="form-check">
        <input class="form-check-input group-cb" type="checkbox" value="${esc(id)}" id="gm_${esc(id)}"${checked}>
        <label class="form-check-label" for="gm_${esc(id)}">${esc(label)}</label>
      </div>`;
    });
    html += "</div>";
    html += `<button class="btn btn-primary btn-sm save-group-btn" data-group="${esc(group)}">Save</button>`;

    const el = $("#group-edit-area");
    if (!el) return;
    el.innerHTML = html;
    el.querySelector(".save-group-btn").addEventListener("click", async () => {
      const selected = [];
      el.querySelectorAll(".group-cb:checked").forEach((cb) =>
        selected.push(cb.value),
      );
      try {
        await apiFetch({
          action: "save-group",
          group,
          members: selected.join(" "),
        });
        showMsg("Group saved.", "success", 3000);
        el.innerHTML = "";
        loadConfig();
      } catch (err) {
        showMsg("Save failed: " + err.message, "danger");
      }
    });
  }

  function editEvent(ename) {
    const ev = (chimeData.events || {})[ename] || {};
    const groups = Object.keys(chimeData.groups || {});

    let html = `<h6>Edit event: ${esc(ename)}</h6>`;
    html += '<div class="row g-2 mb-2">';

    // Sound
    html +=
      '<div class="col-md-3"><label class="form-label">Sound</label><select class="form-select ev-sound">';
    soundList.forEach((s) => {
      const sel = ev.sound === s ? " selected" : "";
      html += `<option value="${esc(s)}"${sel}>${esc(s)}</option>`;
    });
    html += "</select></div>";

    // Volume
    html += `<div class="col-md-2"><label class="form-label">Volume</label><input class="form-control ev-volume" type="number" min="1" max="32" value="${esc(ev.volume || "5")}"></div>`;

    // Repeat
    html += `<div class="col-md-2"><label class="form-label">Repeat</label><input class="form-control ev-repeat" type="number" min="1" max="255" value="${esc(ev.repeat || "2")}"></div>`;

    // Day group
    html +=
      '<div class="col-md-2"><label class="form-label">Day group</label><select class="form-select ev-daygroup"><option value="">(none)</option>';
    groups.forEach((g) => {
      const dayg = (ev.day || {}).group || "";
      const sel = dayg === g ? " selected" : "";
      html += `<option value="${esc(g)}"${sel}>${esc(g)}</option>`;
    });
    html += "</select></div>";

    // Night group
    html +=
      '<div class="col-md-2"><label class="form-label">Night group</label><select class="form-select ev-nightgroup"><option value="">(none)</option>';
    groups.forEach((g) => {
      const nightg = (ev.night || {}).group || "";
      const sel = nightg === g ? " selected" : "";
      html += `<option value="${esc(g)}"${sel}>${esc(g)}</option>`;
    });
    html += "</select></div>";

    // Night volume
    html += `<div class="col-md-1"><label class="form-label">Night vol</label><input class="form-control ev-nightvol" type="number" min="1" max="32" value="${esc((ev.night || {}).volume || "")}"></div>`;

    html += "</div>";
    html += `<button class="btn btn-primary btn-sm save-event-btn" data-event="${esc(ename)}">Save</button>`;

    const el = $("#event-edit-area");
    if (!el) return;
    el.innerHTML = html;
    el.querySelector(".save-event-btn").addEventListener("click", async () => {
      const payload = {
        action: "save-event",
        event: ename,
        sound: el.querySelector(".ev-sound")?.value || "",
        volume: el.querySelector(".ev-volume")?.value || "",
        repeat: el.querySelector(".ev-repeat")?.value || "",
        day_group: el.querySelector(".ev-daygroup")?.value || "",
        night_group: el.querySelector(".ev-nightgroup")?.value || "",
        night_volume: el.querySelector(".ev-nightvol")?.value || "",
      };
      try {
        await apiFetch(payload);
        showMsg("Event saved.", "success", 3000);
        el.innerHTML = "";
        loadConfig();
      } catch (err) {
        showMsg("Save failed: " + err.message, "danger");
      }
    });
  }

  function esc(s) {
    if (!s) return "";
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  /* ── UI bindings ──────────────────────────────────────────── */

  function bindUI() {
    $("#pair-btn")?.addEventListener("click", async () => {
      const name = $("#pair-name")?.value.trim();
      if (!name) {
        showMsg("Enter a name for the chime.", "warning", 3000);
        return;
      }
      try {
        const data = await apiFetch({ action: "pair", name });
        showMsg(data.message || "Pairing complete.", "success", 6000);
        loadConfig();
      } catch (err) {
        showMsg("Pair failed: " + err.message, "danger");
      }
    });

    $("#play-all-btn")?.addEventListener("click", async () => {
      const sound = $("#test-sound")?.value || "DOORBELL_1";
      const vol = $("#test-volume")?.value || "5";
      const rep = $("#test-repeat")?.value || "1";
      try {
        const data = await apiFetch({
          action: "play-all",
          sound,
          volume: vol,
          repeat: rep,
        });
        showMsg(data.message || "Playing all...", "info", 3000);
      } catch (err) {
        showMsg("Play all failed: " + err.message, "danger");
      }
    });

    $("#reload-btn")?.addEventListener("click", () => {
      loadConfig();
      showMsg("Reloaded.", "info", 2000);
    });
  }

  /* ── init ─────────────────────────────────────────────────── */

  bindUI();
  loadConfig();
})();
