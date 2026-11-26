(function () {
  var levels = [
    [1000, "1x"],
    [2000, "2x"],
    [3000, "3x"],
    [4000, "4x"],
  ];

  var select = document.getElementById("webrtc-zoom");
  var current = null;
  var busy = false;

  function setBusy(state) {
    busy = state;
    if (select) select.disabled = state;
  }

  function showError(msg) {
    if (!select) return;
    select.classList.toggle("is-invalid", !!msg);
    select.title = msg || "Select digital zoom";
  }

  function setZoom(f) {
    if (busy || f === current) return;
    setBusy(true);
    showError("");
    fetch("/x/zoom.cgi?f=" + f, { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        if (!d || d.status !== "ok") {
          throw new Error((d && d.reason) || "zoom failed");
        }
        if (d.mode === "none") {
          current = d.factor;
          setBusy(false);
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
        setBusy(false);
        if (select) select.value = String(current);
        showError(e.message || "zoom failed");
      });
  }

  function mount(d) {
    if (!d || d.status !== "ok" || !d.supported || !select) return;
    current = Number(d.factor) || 1000;
    levels.forEach(function (lv) {
      var opt = document.createElement("option");
      opt.value = String(lv[0]);
      opt.textContent = lv[1];
      select.appendChild(opt);
    });
    select.value = String(current);
    select.style.display = "";
    select.addEventListener("change", function () {
      setZoom(Number(select.value));
    });
  }

  function init() {
    if (!select || select.options.length) return;
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
