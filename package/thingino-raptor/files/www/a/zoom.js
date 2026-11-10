(function () {
  var levels = [
    [1000, "1x"],
    [2000, "2x"],
    [3000, "3x"],
    [4000, "4x"],
    [8000, "8x"],
  ];

  var current = null;
  var busy = false;
  var bar = null;
  var errorEl = null;

  function render() {
    if (!bar) return;
    bar.querySelectorAll("button").forEach(function (b) {
      var f = Number(b.getAttribute("data-factor"));
      b.disabled = busy;
      b.className =
        "btn btn-sm " + (f === current ? "btn-primary" : "btn-outline-primary");
    });
  }

  function showError(msg) {
    if (!errorEl) return;
    errorEl.textContent = msg;
    errorEl.style.display = msg ? "block" : "none";
  }

  function setZoom(f) {
    if (busy || f === current) return;
    busy = true;
    showError("");
    render();
    fetch("/x/zoom.cgi?f=" + f, { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        if (!d || d.status !== "ok") {
          throw new Error((d && d.reason) || "zoom failed");
        }
        if (d.mode === "none") {
          busy = false;
          current = d.factor;
          render();
          return;
        }
        setTimeout(
          function () {
            window.location.reload();
          },
          d.mode === "restart" ? 12000 : 1800,
        );
      })
      .catch(function (e) {
        busy = false;
        render();
        showError(e.message || "zoom failed");
      });
  }

  function addButton(lv) {
    var b = document.createElement("button");
    b.type = "button";
    b.className = "btn btn-outline-primary btn-sm";
    b.setAttribute("data-factor", lv[0]);
    b.textContent = lv[1];
    b.addEventListener("click", function () {
      setZoom(lv[0]);
    });
    bar.appendChild(b);
  }

  function mount(d) {
    if (!d || d.status !== "ok" || !d.supported) return;
    var anchor =
      document.getElementById("raptor-webrtc-video") ||
      document.getElementById("preview") ||
      document.getElementById("frame");
    if (!anchor) return;
    current = d.factor;
    bar = document.createElement("div");
    bar.id = "zoom-buttons";
    bar.className = "btn-group my-2 d-flex justify-content-center";
    bar.setAttribute("role", "group");
    bar.setAttribute("aria-label", "Zoom");
    levels.forEach(addButton);
    errorEl = document.createElement("div");
    errorEl.id = "zoom-error";
    errorEl.className = "text-danger small text-center";
    errorEl.style.display = "none";
    // Sit above the fixed-aspect, overflow-hidden video wrapper, not inside it.
    var wrap = anchor.closest ? anchor.closest(".raptor-video-wrap") : null;
    var target = wrap || anchor;
    target.insertAdjacentElement("beforebegin", bar);
    bar.insertAdjacentElement("afterend", errorEl);
    render();
  }

  function init() {
    if (document.getElementById("zoom-buttons")) return;
    fetch("/x/zoom.cgi?info=1", { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(mount)
      .catch(function () {});
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", init);
  else init();
})();
