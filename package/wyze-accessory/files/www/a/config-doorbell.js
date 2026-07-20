(function () {
  const API = "/x/json-config-doorbell.cgi";
  let chimeData = {};
  let soundList = [];

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
    if (typeof showAlert === "function") {
      showAlert(type, text, timeout);
      return;
    }
    const el = $("#doorbell-msg");
    if (!el) return;
    el.className = "alert alert-" + type + " mt-2";
    el.textContent = text;
    el.hidden = false;
    if (timeout) setTimeout(() => (el.hidden = true), timeout);
  }

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
        '<tr><td colspan="3" class="text-muted">No chimes paired.</td></tr>';
      return;
    }
    tbody.innerHTML = ids
      .map((id) => {
        const u = units[id] || {};
        const name = u.name || "(unnamed)";
        const mac = id.replace(/(..)(..)(..)(..)/, "$1:$2:$3:$4");
        return `<tr>
          <td><code>${esc(mac)}</code></td>
          <td>${esc(name)}</td>
          <td class="text-end">
            <button class="btn btn-sm btn-outline-secondary rename-btn" data-id="${esc(id)}" data-name="${esc(name)}" title="Rename"><i class="bi bi-pencil"></i></button>
            <button class="btn btn-sm btn-outline-primary play-btn" data-id="${esc(id)}" title="Test chime"><span class="btn-icon"><i class="bi bi-bell"></i></span></button>
            <button class="btn btn-sm btn-outline-danger unpair-btn" data-id="${esc(id)}">Unpair</button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".play-btn").forEach((btn) => {
      btn.addEventListener("click", function () {
        playChime(this.dataset.id, this);
      });
    });
    tbody.querySelectorAll(".rename-btn").forEach((btn) => {
      btn.addEventListener("click", () =>
        openRenameModal(btn.dataset.id, btn.dataset.name),
      );
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
            <button class="btn btn-sm btn-outline-secondary edit-group-btn" data-group="${esc(g)}" data-members="${esc(members.join(" "))}" title="Edit group"><i class="bi bi-pencil"></i></button>
            <button class="btn btn-sm btn-outline-primary play-group-btn" data-group="${esc(g)}" title="Test group"><span class="btn-icon"><i class="bi bi-bell"></i></span></button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".play-group-btn").forEach((btn) => {
      btn.addEventListener("click", function () {
        playGroup(this.dataset.group, this);
      });
    });
    tbody.querySelectorAll(".edit-group-btn").forEach((btn) => {
      btn.addEventListener("click", () =>
        openGroupModal(btn.dataset.group, btn.dataset.members),
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
        '<tr><td colspan="10" class="text-muted">No events configured.</td></tr>';
      return;
    }
    tbody.innerHTML = enames
      .map((e) => {
        const ev = events[e] || {};
        const day = ev.day || {};
        const night = ev.night || {};
        return `<tr>
          <td><strong>${esc(e)}</strong></td>
          <td class="col-day">${esc(day.group || "-")}</td>
          <td class="col-day">${esc(day.sound || "-")}</td>
          <td class="col-day">${esc(day.volume || "-")}</td>
          <td class="col-day">${esc(day.repeat || "-")}</td>
          <td class="col-night">${esc(night.group || "-")}</td>
          <td class="col-night">${esc(night.sound || "-")}</td>
          <td class="col-night">${esc(night.volume || "-")}</td>
          <td class="col-night">${esc(night.repeat || "-")}</td>
          <td class="text-end">
            <button class="btn btn-sm btn-outline-secondary edit-event-btn" data-event="${esc(e)}" title="Edit event"><i class="bi bi-pencil"></i></button>
          </td></tr>`;
      })
      .join("");

    tbody.querySelectorAll(".edit-event-btn").forEach((btn) => {
      btn.addEventListener("click", () => editEvent(btn.dataset.event));
    });
  }

  function getVolume() {
    const slider = $("#sb-volume");
    return slider ? slider.value : "5";
  }

  async function playChime(id, btn) {
    const vol = getVolume();
    const icon = btn ? btn.querySelector(".btn-icon") : null;
    if (icon) {
      icon.innerHTML =
        '<span class="spinner-border spinner-border-sm" role="status"></span>';
      btn.disabled = true;
    }
    try {
      await apiFetch({
        action: "play",
        id,
        sound: "DOORBELL_1",
        volume: vol,
        repeat: "1",
      });
    } catch (err) {
      showMsg("Play failed: " + err.message, "danger");
    } finally {
      if (icon) {
        icon.innerHTML = '<i class="bi bi-bell"></i>';
        btn.disabled = false;
      }
    }
  }

  async function playGroup(group, btn) {
    const vol = getVolume();
    const icon = btn ? btn.querySelector(".btn-icon") : null;
    if (icon) {
      icon.innerHTML =
        '<span class="spinner-border spinner-border-sm" role="status"></span>';
      btn.disabled = true;
    }
    try {
      await apiFetch({
        action: "play-group",
        group,
        sound: "DOORBELL_1",
        volume: vol,
        repeat: "1",
      });
    } catch (err) {
      showMsg("Play failed: " + err.message, "danger");
    } finally {
      if (icon) {
        icon.innerHTML = '<i class="bi bi-bell"></i>';
        btn.disabled = false;
      }
    }
  }

  async function playSoundAll(sound, btn) {
    const vol = getVolume();
    if (btn) btn.classList.add("sb-playing");
    try {
      await apiFetch({
        action: "play-all",
        sound,
        volume: vol,
        repeat: "1",
      });
    } catch (err) {
      showMsg("Play failed: " + err.message, "danger");
    } finally {
      if (btn) {
        setTimeout(() => btn.classList.remove("sb-playing"), 600);
      }
    }
  }

  async function unpairChime(id) {
    const name = (chimeData.units || {})[id]?.name || id;
    const confirmed = await confirm(
      `Remove chime "${esc(name)}"? This cannot be undone.`,
    );
    if (!confirmed) return;
    try {
      const data = await apiFetch({ action: "unpair", id });
      showMsg(data.message || "Removed.", "success", 3000);
      loadConfig();
    } catch (err) {
      showMsg("Unpair failed: " + err.message, "danger");
    }
  }

  let editingGroupName = null;
  let editingGroupMembers = "";

  function openGroupModal(group, membersStr) {
    editingGroupName = group || null;
    editingGroupMembers = group ? membersStr || "" : "";

    populateGroupModal();

    const modalEl = $("#groupModal");
    if (modalEl && window.bootstrap) {
      const instance = bootstrap.Modal.getOrCreateInstance(modalEl);
      instance.show();
    }
  }

  function closeGroupModal() {
    const modalEl = $("#groupModal");
    if (modalEl && window.bootstrap) {
      const instance = bootstrap.Modal.getInstance(modalEl);
      if (instance) instance.hide();
    }
  }

  function populateGroupModal() {
    const ids = Object.keys(chimeData.units || {});
    const chimesDiv = $("#group-chimes");
    const nameField = $("#group-name-field");
    const nameInput = $("#group-name");
    const title = $("#groupModalLabel");
    const isEdit = !!editingGroupName;

    if (title)
      title.textContent = isEdit
        ? "Edit group: " + editingGroupName
        : "New group";
    if (nameField) nameField.hidden = isEdit;
    if (nameInput) {
      nameInput.value = "";
      nameInput.classList.remove("is-invalid");
      const fb = $("#group-name-feedback");
      if (fb) fb.textContent = "";
      if (!isEdit) nameInput.focus();
    }

    if (!chimesDiv) return;

    if (ids.length === 0) {
      chimesDiv.innerHTML = '<p class="text-muted">No chimes paired yet.</p>';
      return;
    }

    const currentMembers = isEdit ? editingGroupMembers.split(" ") : [];

    chimesDiv.innerHTML = ids
      .map((id) => {
        const u = chimeData.units[id] || {};
        const label = u.name
          ? id.replace(/(..)(..)(..)(..)/, "$1:$2:$3:$4") + " " + u.name
          : id.replace(/(..)(..)(..)(..)/, "$1:$2:$3:$4");
        const checked = currentMembers.includes(id) ? " checked" : "";
        return `<div class="form-check">
        <input class="form-check-input group-cb" type="checkbox" value="${esc(id)}" id="gm_${esc(id)}"${checked}>
        <label class="form-check-label" for="gm_${esc(id)}">${esc(label)}</label>
      </div>`;
      })
      .join("");
  }

  let editingEventName = null;

  function openEventModal(ename) {
    editingEventName = ename;
    populateEventModal();
    const modalEl = $("#eventModal");
    if (modalEl && window.bootstrap) {
      const instance = bootstrap.Modal.getOrCreateInstance(modalEl);
      instance.show();
    }
  }

  function populateEventModal() {
    const ev = editingEventName
      ? (chimeData.events || {})[editingEventName] || {}
      : {};
    const groups = Object.keys(chimeData.groups || {});
    const day = ev.day || {};
    const night = ev.night || {};

    const title = $("#eventModalLabel");
    if (title) title.textContent = "Edit event: " + editingEventName;

    /* Helper: fill sound dropdown */
    function fillSound(selId, value) {
      const sel = $(selId);
      if (!sel) return;
      sel.innerHTML = soundList
        .map((s) => {
          const selAttr = s === value ? " selected" : "";
          return `<option value="${esc(s)}"${selAttr}>${esc(s)}</option>`;
        })
        .join("");
    }

    /* Helper: fill group dropdown */
    function fillGroup(selId, value) {
      const sel = $(selId);
      if (!sel) return;
      let opts = '<option value="">(none)</option>';
      groups.forEach((g) => {
        const selAttr = g === value ? " selected" : "";
        opts += `<option value="${esc(g)}"${selAttr}>${esc(g)}</option>`;
      });
      sel.innerHTML = opts;
    }

    fillSound("#ev-day-sound", day.sound || "");
    fillSound("#ev-night-sound", night.sound || "");
    fillGroup("#ev-day-group", day.group || "");
    fillGroup("#ev-night-group", night.group || "");

    const dayVol = $("#ev-day-volume");
    if (dayVol) dayVol.value = day.volume || "5";
    const dayRep = $("#ev-day-repeat");
    if (dayRep) dayRep.value = day.repeat || "1";
    const nightVol = $("#ev-night-volume");
    if (nightVol) nightVol.value = night.volume || "5";
    const nightRep = $("#ev-night-repeat");
    if (nightRep) nightRep.value = night.repeat || "1";
  }

  function editEvent(ename) {
    openEventModal(ename);
  }

  function esc(s) {
    if (!s) return "";
    return String(s)
      .replace(/&/g, "&amp;")
      .replace(/</g, "&lt;")
      .replace(/>/g, "&gt;")
      .replace(/"/g, "&quot;");
  }

  let soundboardBuilt = false;

  function buildSoundboard() {
    if (soundboardBuilt) return;
    const grid = $("#soundboard-grid");
    if (!grid || !soundList.length) return;

    grid.innerHTML = soundList
      .map((s) => {
        const label = s.replace(/_/g, " ");
        return `<div class="col-6 col-md-4 col-lg-3">
          <button class="btn btn-outline-secondary w-100 text-start sb-sound-btn" data-sound="${esc(s)}">
            <i class="bi bi-play-fill me-1"></i>${esc(label)}
          </button>
        </div>`;
      })
      .join("");

    grid.querySelectorAll(".sb-sound-btn").forEach((btn) => {
      btn.addEventListener("click", function () {
        playSoundAll(this.dataset.sound, this);
      });
    });

    soundboardBuilt = true;
  }

  let renamingChimeId = null;

  function openRenameModal(id, name) {
    renamingChimeId = id;
    const input = $("#rename-name");
    const fb = $("#rename-name-feedback");
    if (input) {
      input.value = name || "";
      input.classList.remove("is-invalid");
    }
    if (fb) fb.textContent = "";
    const modalEl = $("#renameModal");
    if (modalEl && window.bootstrap) {
      const instance = bootstrap.Modal.getOrCreateInstance(modalEl);
      instance.show();
      setTimeout(() => input?.focus(), 100);
    }
  }

  function closePairModal() {
    const modalEl = $("#pairModal");
    if (modalEl && window.bootstrap) {
      const instance = bootstrap.Modal.getInstance(modalEl);
      if (instance) instance.hide();
    }
  }

  function bindUI() {
    /* Clear input and errors when pair modal opens */
    $("#pairModal")?.addEventListener("shown.bs.modal", () => {
      const input = $("#pair-name");
      if (input) {
        input.value = "";
        input.classList.remove("is-invalid");
        input.focus();
      }
      const fb = $("#pair-name-feedback");
      if (fb) fb.textContent = "";
    });

    /* Clear inline error when user starts typing */
    $("#pair-name")?.addEventListener("input", () => {
      $("#pair-name")?.classList.remove("is-invalid");
      const fb = $("#pair-name-feedback");
      if (fb) fb.textContent = "";
    });

    /* Enter key triggers pair */
    $("#pair-name")?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") $("#pair-btn")?.click();
    });

    $("#pair-btn")?.addEventListener("click", async function () {
      const btn = this;
      const input = $("#pair-name");
      const name = input?.value.trim();
      if (!name) {
        input?.classList.add("is-invalid");
        const fb = $("#pair-name-feedback");
        if (fb) fb.textContent = "Enter a name for the chime.";
        input?.focus();
        return;
      }

      /* Show spinner */
      const origHTML = btn.innerHTML;
      const cancelBtn = $("#pairModal .btn-secondary");
      const closeBtn = $("#pairModal .btn-close");
      btn.disabled = true;
      btn.innerHTML =
        '<span class="spinner-border spinner-border-sm me-1" role="status"></span>Pairing…';
      if (input) input.disabled = true;
      if (cancelBtn) cancelBtn.disabled = true;
      if (closeBtn) closeBtn.disabled = true;

      try {
        await apiFetch({ action: "pair", name });
        closePairModal();
        loadConfig();
      } catch (err) {
        showMsg("Pair failed: " + err.message, "danger");
        /* Restore on error */
        btn.disabled = false;
        btn.innerHTML = origHTML;
        if (input) input.disabled = false;
        if (cancelBtn) cancelBtn.disabled = false;
        if (closeBtn) closeBtn.disabled = false;
      }
    });

    /* Volume slider updates label */
    $("#sb-volume")?.addEventListener("input", function () {
      const val = $("#sb-volume-val");
      if (val) val.textContent = this.value;
    });

    /* Add Group button clears state then shows modal */
    $("#add-group-btn")?.addEventListener("click", () => {
      openGroupModal(null, "");
    });

    /* Pair modal button */
    $("#pair-modal-btn")?.addEventListener("click", () => {
      const modalEl = $("#pairModal");
      if (modalEl && window.bootstrap) {
        const instance = bootstrap.Modal.getOrCreateInstance(modalEl);
        instance.show();
      }
    });

    /* Clear group name error on input */
    $("#group-name")?.addEventListener("input", () => {
      $("#group-name")?.classList.remove("is-invalid");
      const fb = $("#group-name-feedback");
      if (fb) fb.textContent = "";
    });

    /* Enter key triggers save in group modal */
    $("#group-name")?.addEventListener("keydown", (e) => {
      if (e.key === "Enter") $("#save-group-btn")?.click();
    });

    $("#save-event-btn")?.addEventListener("click", async () => {
      const payload = {
        action: "save-event",
        event: editingEventName,
        day_sound: $("#ev-day-sound")?.value || "",
        day_volume: $("#ev-day-volume")?.value || "",
        day_repeat: $("#ev-day-repeat")?.value || "",
        day_group: $("#ev-day-group")?.value || "",
        night_sound: $("#ev-night-sound")?.value || "",
        night_volume: $("#ev-night-volume")?.value || "",
        night_repeat: $("#ev-night-repeat")?.value || "",
        night_group: $("#ev-night-group")?.value || "",
      };
      try {
        await apiFetch(payload);
        showMsg("Event saved.", "success", 3000);
        const modalEl = $("#eventModal");
        if (modalEl && window.bootstrap) {
          const instance = bootstrap.Modal.getInstance(modalEl);
          if (instance) instance.hide();
        }
        loadConfig();
      } catch (err) {
        showMsg("Save failed: " + err.message, "danger");
      }
    });

    $("#save-group-btn")?.addEventListener("click", async () => {
      const name = editingGroupName || $("#group-name")?.value.trim();
      if (!name) {
        const input = $("#group-name");
        input?.classList.add("is-invalid");
        const fb = $("#group-name-feedback");
        if (fb) fb.textContent = "Enter a group name.";
        input?.focus();
        return;
      }
      const selected = [];
      $$("#group-chimes .group-cb:checked").forEach((cb) =>
        selected.push(cb.value),
      );
      try {
        await apiFetch({
          action: "save-group",
          group: name,
          members: selected.join(" "),
        });
        showMsg(
          editingGroupName ? "Group updated." : "Group created.",
          "success",
          3000,
        );
        closeGroupModal();
        loadConfig();
      } catch (err) {
        showMsg("Save failed: " + err.message, "danger");
      }
    });

    /* Clear rename error on input */
    $("#rename-name")?.addEventListener("input", () => {
      $("#rename-name")?.classList.remove("is-invalid");
      const fb = $("#rename-name-feedback");
      if (fb) fb.textContent = "";
    });

    $("#rename-btn")?.addEventListener("click", async () => {
      const name = $("#rename-name")?.value.trim();
      if (!name) {
        const input = $("#rename-name");
        input?.classList.add("is-invalid");
        const fb = $("#rename-name-feedback");
        if (fb) fb.textContent = "Enter a name.";
        input?.focus();
        return;
      }
      try {
        await apiFetch({ action: "rename", id: renamingChimeId, name });
        const modalEl = $("#renameModal");
        if (modalEl && window.bootstrap) {
          const instance = bootstrap.Modal.getInstance(modalEl);
          if (instance) instance.hide();
        }
        loadConfig();
      } catch (err) {
        showMsg("Rename failed: " + err.message, "danger");
      }
    });

    $("#reload-btn")?.addEventListener("click", () => {
      loadConfig();
      showMsg("Reloaded.", "info", 2000);
    });
  }

  const _renderAll = renderAll;
  renderAll = function () {
    _renderAll();
    buildSoundboard();
  };

  bindUI();
  loadConfig();
})();
