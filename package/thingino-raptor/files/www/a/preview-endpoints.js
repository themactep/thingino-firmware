(function () {
  "use strict";

  var list = document.querySelector("#preview-endpoint-list");
  var dropdownMenu = document.querySelector("#preview-endpoint-dropdown-menu");
  if (!list && !dropdownMenu) return;

  var apiKey = "";

  function origin() {
    return (
      window.location.origin ||
      window.location.protocol + "//" + window.location.host
    );
  }

  function withToken(baseUrl) {
    if (!apiKey) return baseUrl;
    return (
      baseUrl +
      (baseUrl.indexOf("?") >= 0 ? "&" : "?") +
      "token=" +
      encodeURIComponent(apiKey)
    );
  }

  function markCopied(link) {
    link.classList.add("copied");
    if (link._copyTimer) clearTimeout(link._copyTimer);
    link._copyTimer = window.setTimeout(function () {
      link.classList.remove("copied");
      link._copyTimer = null;
    }, 1200);
  }

  async function copyEndpoint(ev) {
    ev.preventDefault();
    var link = ev.currentTarget;
    var url = link && link.dataset ? link.dataset.copyUrl : "";
    var clipboard = window.thinginoClipboard;
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

  function addLink(container, entry, asDropdownItem) {
    var link = document.createElement("a");
    if (asDropdownItem) {
      link.className = "dropdown-item preview-endpoint-dropdown-item";
      link.innerHTML =
        '<span class="preview-endpoint-short">' +
        entry.label +
        '</span> <i class="bi bi-clipboard"></i>';
    } else {
      link.className = "preview-endpoint-link";
      var short = document.createElement("span");
      short.className = "preview-endpoint-short";
      short.textContent = entry.label;
      var hint = document.createElement("span");
      hint.className = "preview-endpoint-hint";
      hint.innerHTML = '<i class="bi bi-clipboard"></i>';
      link.appendChild(short);
      link.appendChild(hint);
    }
    link.href = entry.url;
    link.rel = "noopener";
    link.dataset.copyUrl = entry.url;
    link.title = entry.label + ": " + entry.url;
    link.setAttribute("aria-label", entry.label + " endpoint");
    link.addEventListener("click", copyEndpoint);

    if (asDropdownItem) {
      var item = document.createElement("li");
      item.appendChild(link);
      container.appendChild(item);
    } else {
      container.appendChild(link);
    }
  }

  function render(rtspUrls) {
    var entries = [];
    if (rtspUrls[0]) entries.push({ label: "RTSP Ch0", url: rtspUrls[0] });
    if (rtspUrls[1]) entries.push({ label: "RTSP Ch1", url: rtspUrls[1] });
    entries.push(
      { label: "MJPEG Ch0", url: withToken(origin() + "/x/ch0.mjpg") },
      { label: "MJPEG Ch1", url: withToken(origin() + "/x/ch1.mjpg") },
      { label: "Snapshot Ch0", url: withToken(origin() + "/x/ch0.jpg") },
      { label: "Snapshot Ch1", url: withToken(origin() + "/x/ch1.jpg") }
    );

    if (list) list.innerHTML = "";
    if (dropdownMenu) dropdownMenu.innerHTML = "";

    entries.forEach(function (entry) {
      if (list) addLink(list, entry, false);
      if (dropdownMenu) addLink(dropdownMenu, entry, true);
    });
  }

  async function loadApiKey() {
    try {
      var res = await fetch("/x/api-key.cgi", { cache: "no-store" });
      if (!res.ok) return;
      var data = await res.json();
      if (data.exists && data.api_key) apiKey = data.api_key;
    } catch (err) {
      console.warn("Could not load API key for preview endpoints:", err);
    }
  }

  async function loadRtspUrls() {
    var urls = [null, null];
    if (typeof window.agentJsonRequest === "function") {
      try {
        var runtime = await window.agentJsonRequest("/api/v1/runtime/all", {
          cache: "no-store",
        });
        var streams = runtime && runtime.streams;
        if (Array.isArray(streams)) {
          if (streams[0] && streams[0].rtsp_url) urls[0] = streams[0].rtsp_url;
          if (streams[1] && streams[1].rtsp_url) urls[1] = streams[1].rtsp_url;
        }
      } catch (err) {
        console.warn("Could not load RTSP endpoints:", err);
      }
    }
    return urls;
  }

  async function init() {
    await loadApiKey();
    render(await loadRtspUrls());
  }

  init();
})();
