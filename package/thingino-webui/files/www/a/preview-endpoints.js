/**
 * Shared preview endpoint links.
 *
 * Renders the combined set of direct-stream endpoints (RTSP, fMP4, MJPEG,
 * snapshot) into the endpoint list/dropdown on every preview page. Both the
 * fMP4 and MJPEG preview pages include this script; a page may refine the
 * RTSP/stream state via thinginoPreviewEndpoints.updateState().
 */
(function () {
  "use strict";

  const HTTP_PORT = "8080";

  const state = {
    rtsp: { username: "thingino", password: "thingino", port: "554" },
    stream0: { rtsp_endpoint: "ch0" },
    stream1: { rtsp_endpoint: "ch1" },
  };
  let apiKey = "";

  function value(v, fallback) {
    return v === undefined || v === null || v === "" ? fallback : v;
  }

  function wrapIpv6Host(host) {
    return host && host.includes(":") && !host.startsWith("[")
      ? `[${host}]`
      : host;
  }

  function formatHostWithPort(host, port, defaultPort) {
    const numericPort = parseInt(port, 10);
    if (!port || Number.isNaN(numericPort) || numericPort === defaultPort) {
      return host;
    }
    return `${host}:${numericPort}`;
  }

  function origin() {
    if (window.location && window.location.origin) {
      return window.location.origin;
    }
    return `${window.location.protocol}//${window.location.host}`;
  }

  function rtspCredential(user, pass) {
    return `${encodeURIComponent(user)}:${encodeURIComponent(pass)}`;
  }

  function withToken(url) {
    if (!apiKey) return url;
    const separator = url.includes("?") ? "&" : "?";
    return `${url}${separator}token=${encodeURIComponent(apiKey)}`;
  }

  function hostName() {
    return window.network_address || window.location.hostname || "localhost";
  }

  function markCopied(link) {
    if (!link) return;
    link.classList.add("copied");
    if (link._copyTimer) {
      clearTimeout(link._copyTimer);
    }
    link._copyTimer = window.setTimeout(() => {
      link.classList.remove("copied");
      link._copyTimer = null;
    }, 1200);
  }

  async function copy(ev) {
    ev.preventDefault();
    const link = ev.currentTarget;
    const url = link?.dataset?.copyUrl || link?.href || "";
    const clipboard = window.thinginoClipboard;
    if (!url || !clipboard || typeof clipboard.copy !== "function") {
      if (typeof window.showAlert === "function") {
        window.showAlert("warning", "Clipboard copy is not available.", 3000);
      }
      return;
    }
    try {
      await clipboard.copy(url);
      markCopied(link);
    } catch (err) {
      if (typeof window.showAlert === "function") {
        window.showAlert("danger", "Unable to copy the endpoint.", 3000);
      }
    }
  }

  function entries() {
    const host = wrapIpv6Host(hostName());
    const httpOrigin = origin();
    const rtspHost = formatHostWithPort(host, state.rtsp.port, 554);
    const rtspAuth = rtspCredential(state.rtsp.username, state.rtsp.password);
    const fmp4Base = `http://${host}:${HTTP_PORT}`;
    return [
      {
        label: "RTSP Ch0",
        url: `rtsp://${rtspAuth}@${rtspHost}/${state.stream0.rtsp_endpoint}`,
      },
      {
        label: "RTSP Ch1",
        url: `rtsp://${rtspAuth}@${rtspHost}/${state.stream1.rtsp_endpoint}`,
      },
      { label: "fMP4 Main", url: withToken(`${fmp4Base}/ch0.mp4`) },
      { label: "fMP4 Sub", url: withToken(`${fmp4Base}/ch1.mp4`) },
      { label: "MJPEG Ch0", url: withToken(`${httpOrigin}/x/ch0.mjpg`) },
      { label: "MJPEG Ch1", url: withToken(`${httpOrigin}/x/ch1.mjpg`) },
      { label: "Snapshot Ch0", url: withToken(`${httpOrigin}/x/ch0.jpg`) },
      { label: "Snapshot Ch1", url: withToken(`${httpOrigin}/x/ch1.jpg`) },
    ];
  }

  function appendLink(container, entry, isDropdown) {
    const link = document.createElement("a");
    link.className = isDropdown
      ? "dropdown-item preview-endpoint-dropdown-item"
      : "preview-endpoint-link";
    link.href = entry.url;
    link.rel = "noopener";
    link.dataset.copyUrl = entry.url;
    link.title = `${entry.label}: ${entry.url}`;
    link.setAttribute("aria-label", `${entry.label} endpoint`);
    link.innerHTML =
      `<span class="preview-endpoint-short">${entry.label}</span> ` +
      '<i class="bi bi-clipboard"></i>';
    link.addEventListener("click", copy);

    if (isDropdown) {
      const li = document.createElement("li");
      li.appendChild(link);
      container.appendChild(li);
    } else {
      container.appendChild(link);
    }
  }

  function render() {
    const list = document.getElementById("preview-endpoint-list");
    const dropdown = document.getElementById("preview-endpoint-dropdown-menu");
    if (!list && !dropdown) return;
    const all = entries();
    if (list) list.innerHTML = "";
    if (dropdown) dropdown.innerHTML = "";
    all.forEach((entry) => {
      if (list) appendLink(list, entry, false);
      if (dropdown) appendLink(dropdown, entry, true);
    });
  }

  function updateState(msg) {
    if (!msg) return;
    if (msg.rtsp) {
      state.rtsp.username = value(msg.rtsp.username, state.rtsp.username);
      state.rtsp.password = value(msg.rtsp.password, state.rtsp.password);
      state.rtsp.port = value(msg.rtsp.port, state.rtsp.port);
    }
    if (msg.stream0) {
      state.stream0.rtsp_endpoint = value(
        msg.stream0.rtsp_endpoint,
        state.stream0.rtsp_endpoint,
      );
    }
    if (msg.stream1) {
      state.stream1.rtsp_endpoint = value(
        msg.stream1.rtsp_endpoint,
        state.stream1.rtsp_endpoint,
      );
    }
    render();
  }

  async function loadApiKey() {
    try {
      const response = await fetch("/x/api-key.cgi", { cache: "no-store" });
      if (!response.ok) return;
      const data = await response.json();
      if (data.exists && data.api_key) {
        apiKey = data.api_key;
      }
    } catch (err) {
      /* ignore */
    }
  }

  async function init() {
    await loadApiKey();
    render();
  }

  window.thinginoPreviewEndpoints = {
    updateState: updateState,
    render: render,
    refresh: init,
  };

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
