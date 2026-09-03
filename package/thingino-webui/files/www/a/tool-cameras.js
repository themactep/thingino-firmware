(function () {
  "use strict";

  const endpoint = "/x/json-cameras.cgi";
  const refreshButton = $("#cameras-refresh");
  const spinner = $("#cameras-spinner");
  const content = $("#cameras-content");
  const errorAlert = $("#cameras-error");
  const emptyState = $("#cameras-empty");
  const tbody = $("#cameras-tbody");
  const table = $("#cameras-table");
  const thead = $("#cameras-table thead");
  const state = {
    rawCameras: [],
    sortColumn: "name",
    sortDirection: "asc",
  };

  function showSpinner(active) {
    if (!spinner) return;
    spinner.classList.toggle("d-none", !active);
  }

  function showContent(active) {
    if (!content) return;
    content.classList.toggle("d-none", !active);
  }

  function showError(message) {
    if (!errorAlert) return;
    if (!message) {
      errorAlert.classList.add("d-none");
      errorAlert.textContent = "";
      return;
    }
    errorAlert.textContent = message;
    errorAlert.classList.remove("d-none");
  }

  function compareIp(a, b) {
    const x = a || "";
    const y = b || "";
    if (!x.includes(":") && !y.includes(":")) {
      const ax = x.split(".").map((n) => parseInt(n, 10) || 0);
      const ay = y.split(".").map((n) => parseInt(n, 10) || 0);
      for (let i = 0; i < 4; i++) {
        const va = ax[i] || 0;
        const vb = ay[i] || 0;
        if (va !== vb) return va - vb;
      }
      return 0;
    }
    return x.localeCompare(y);
  }

  function sortCameras(cameras) {
    const { sortColumn, sortDirection } = state;
    const dir = sortDirection === "asc" ? 1 : -1;

    return [...cameras].sort((a, b) => {
      let cmp = 0;
      if (sortColumn === "ip") {
        cmp = compareIp(a.ip, b.ip);
      } else if (sortColumn === "model") {
        cmp = (a.model || "").localeCompare(b.model || "");
      } else if (sortColumn === "build") {
        cmp = (a.version || "").localeCompare(b.version || "");
      } else if (sortColumn === "streamer") {
        cmp = (a.streamer || "").localeCompare(b.streamer || "");
      } else {
        cmp = (a.name || "").localeCompare(b.name || "");
      }
      return cmp * dir;
    });
  }

  function updateSortIndicators() {
    document.querySelectorAll(".sort-indicator").forEach((el) => {
      const col = el.dataset.for;
      el.classList.remove("asc", "desc");
      if (col === state.sortColumn) {
        el.classList.add(state.sortDirection);
      }
    });
  }

  function handleSortClick(event) {
    const th = event.target.closest("th[data-sort]");
    if (!th) return;
    const col = th.dataset.sort;
    if (state.sortColumn === col) {
      state.sortDirection = state.sortDirection === "asc" ? "desc" : "asc";
    } else {
      state.sortColumn = col;
      state.sortDirection = "asc";
    }
    updateSortIndicators();
    renderCameras(state.rawCameras);
  }

  function renderCameras(cameras) {
    if (!tbody) return;
    state.rawCameras = cameras || [];
    tbody.innerHTML = "";

    sortCameras(state.rawCameras).forEach((camera) => {
      const row = document.createElement("tr");
      if (camera.self) {
        row.classList.add("camera-self-row");
      }

      const nameCell = document.createElement("td");
      nameCell.textContent = camera.name || camera.ip || "unknown";

      const ipCell = document.createElement("td");
      ipCell.textContent = camera.ip;

      const modelCell = document.createElement("td");
      modelCell.textContent = camera.model || "";

      const buildCell = document.createElement("td");
      if (camera.version) {
        const buildCode = document.createElement("code");
        buildCode.textContent = camera.version;
        buildCell.appendChild(buildCode);
      }

      const streamerCell = document.createElement("td");
      streamerCell.textContent = camera.streamer || "";

      const actionCell = document.createElement("td");
      actionCell.className = "text-end";
      const openBtn = document.createElement("a");
      openBtn.className = "btn btn-sm btn-outline-secondary";
      openBtn.href = "http://" + camera.ip + "/";
      openBtn.target = "_blank";
      openBtn.rel = "noreferrer noopener";
      const openIcon = document.createElement("i");
      openIcon.className = "bi bi-box-arrow-up-right me-1";
      openBtn.appendChild(openIcon);
      openBtn.appendChild(document.createTextNode("Web UI"));
      actionCell.appendChild(openBtn);

      row.appendChild(nameCell);
      row.appendChild(ipCell);
      row.appendChild(modelCell);
      row.appendChild(buildCell);
      row.appendChild(streamerCell);
      row.appendChild(actionCell);
      tbody.appendChild(row);
    });

    const hasCameras = state.rawCameras.length > 0;
    if (table) {
      table.classList.toggle("d-none", !hasCameras);
    }
    if (emptyState) {
      emptyState.classList.toggle("d-none", hasCameras);
    }
  }

  async function fetchCameras(refresh) {
    const url = refresh ? endpoint + "?refresh=1" : endpoint;
    const response = await fetch(url, {
      headers: { Accept: "application/json" },
    });
    if (!response.ok) {
      throw new Error("Request failed with status " + response.status);
    }
    const payload = await response.json();
    if (payload && payload.error) {
      throw new Error(payload.error);
    }
    const data = payload && payload.data;
    if (!data || !Array.isArray(data.cameras)) {
      throw new Error("Unexpected response from the camera scan.");
    }
    return data.cameras;
  }

  async function loadCameras(refresh) {
    if (refreshButton) {
      refreshButton.disabled = true;
    }
    showError("");
    showContent(false);
    showSpinner(true);

    try {
      const cameras = await fetchCameras(refresh);
      renderCameras(cameras);
      updateSortIndicators();
      showSpinner(false);
      showContent(true);
    } catch (err) {
      showSpinner(false);
      showContent(false);
      showError(
        err && err.message ? err.message : "Unable to scan the network.",
      );
    } finally {
      if (refreshButton) {
        refreshButton.disabled = false;
      }
    }
  }

  function initCamerasPage() {
    if (refreshButton) {
      refreshButton.addEventListener("click", () => loadCameras(true));
    }
    if (thead) {
      thead.addEventListener("click", handleSortClick);
    }
    loadCameras(false);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initCamerasPage, {
      once: true,
    });
  } else {
    initCamerasPage();
  }
})();
