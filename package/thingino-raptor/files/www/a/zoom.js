(function () {
  var levels = [
    [1000, "1x"],
    [2000, "2x"],
    [3000, "3x"],
    [4000, "4x"],
    [8000, "8x"],
  ];

  function setZoom(f) {
    fetch("/x/zoom.cgi?f=" + f, { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        var delay = d && d.mode === "restart" ? 12000 : 1800;
        setTimeout(function () {
          window.location.reload();
        }, delay);
      })
      .catch(function () {
        setTimeout(function () {
          window.location.reload();
        }, 12000);
      });
  }

  function mount() {
    if (document.getElementById("zoom-buttons")) return;
    var anchor =
      document.getElementById("raptor-webrtc-video") ||
      document.getElementById("preview") ||
      document.getElementById("frame");
    if (!anchor) return;
    var bar = document.createElement("div");
    bar.id = "zoom-buttons";
    bar.className = "btn-group my-2 d-flex justify-content-center";
    bar.setAttribute("role", "group");
    bar.setAttribute("aria-label", "Zoom");
    levels.forEach(function (lv) {
      var b = document.createElement("button");
      b.type = "button";
      b.className = "btn btn-outline-primary btn-sm";
      b.textContent = lv[1];
      b.addEventListener("click", function () {
        setZoom(lv[0]);
      });
      bar.appendChild(b);
    });
    anchor.insertAdjacentElement("beforebegin", bar);
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", mount);
  else mount();
})();
