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

  function renderCameras(cameras) {
    if (!tbody) return;
    tbody.innerHTML = "";

    (cameras || []).forEach((camera) => {
      const row = document.createElement("tr");

      const nameCell = document.createElement("td");
      nameCell.textContent = camera.name || camera.ip || "unknown";
      if (camera.self) {
        const badge = document.createElement("span");
        badge.className = "badge text-bg-secondary ms-2";
        badge.textContent = "this camera";
        nameCell.appendChild(badge);
      }

      const modelCell = document.createElement("td");
      modelCell.textContent = camera.model || "";

      const streamerCell = document.createElement("td");
      if (camera.streamer) {
        const streamerBadge = document.createElement("span");
        streamerBadge.className = "badge text-bg-info";
        streamerBadge.textContent = camera.streamer;
        streamerCell.appendChild(streamerBadge);
      }

      const buildCell = document.createElement("td");
      if (camera.version) {
        const buildCode = document.createElement("code");
        buildCode.textContent = camera.version;
        buildCell.appendChild(buildCode);
      }

      const ipCell = document.createElement("td");
      const ipLink = document.createElement("a");
      ipLink.href = "http://" + camera.ip + "/";
      ipLink.target = "_blank";
      ipLink.rel = "noreferrer noopener";
      ipLink.textContent = camera.ip;
      ipCell.appendChild(ipLink);

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
      row.appendChild(modelCell);
      row.appendChild(streamerCell);
      row.appendChild(buildCell);
      row.appendChild(ipCell);
      row.appendChild(actionCell);
      tbody.appendChild(row);
    });

    const hasCameras = !!(cameras && cameras.length);
    if (table) {
      table.classList.toggle("d-none", !hasCameras);
    }
    if (emptyState) {
      emptyState.classList.toggle("d-none", hasCameras);
    }
  }

  async function fetchCameras() {
    const response = await fetch(endpoint, {
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

  async function loadCameras() {
    if (refreshButton) {
      refreshButton.disabled = true;
    }
    showError("");
    showContent(false);
    showSpinner(true);

    try {
      const cameras = await fetchCameras();
      renderCameras(cameras);
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
      refreshButton.addEventListener("click", loadCameras);
    }
    loadCameras();
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", initCamerasPage, {
      once: true,
    });
  } else {
    initCamerasPage();
  }
})();
