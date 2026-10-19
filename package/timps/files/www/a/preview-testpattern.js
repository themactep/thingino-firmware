(function () {
  "use strict";

  const panel = document.getElementById("tp-panel");
  if (!panel) return;
  const $ = (id) => document.getElementById(id);
  const btns = Array.from(document.querySelectorAll("#tp-btns [data-tp]"));
  const NAMES = ["off", "pattern", "moving square", "motion test"];
  let mode = -1, timer = null, busy = false;

  function show(j) {
    const caps = (j.caps && j.caps.testpattern) || {};
    panel.hidden = !caps.available;
    if (!caps.available) return false;
    const t = j.testpattern || {};
    mode = +t.mode || 0;
    btns.forEach((b) => {
      const on = +b.dataset.tp === mode;
      b.classList.toggle("active", on);
      b.classList.toggle("btn-secondary", on);
      b.classList.toggle("btn-outline-secondary", !on);
      b.disabled = busy;
    });
    $("tp-chip").textContent = mode ? NAMES[mode] + " · " + (t.frames || 0) + " frames" : "off";
    const e = t.eval || {};
    $("tp-eval").hidden = mode !== 3;
    if (mode === 3) {
      $("tp-hits").textContent = (e.hits || 0) + " / " + (e.objects || 0);
      $("tp-miss").textContent = e.misses || 0;
      $("tp-fa").textContent = e.false_alarms || 0;
      $("tp-lat").textContent = e.hits ? e.lat_avg_ms + " ms" : "–";
      $("tp-lat-s").textContent = e.hits ? "detection delay, max " + e.lat_max_ms + " ms" : "detection delay";
      $("tp-note").textContent = e.motion ? "Objects appear in the grid; each one should raise a motion event." :
        "Motion detection is off: enable it on the Motion page to score the test.";
    } else {
      $("tp-note").textContent = "Replaces the camera picture with a synthetic one to check encoder, rotation, OSD and motion detection. Day/night stays in day mode meanwhile.";
    }
    return true;
  }

  function poll() {
    clearTimeout(timer);
    window.timpsApiReady().then((api) => api.get()).then((j) => {
      if (show(j)) timer = setTimeout(poll, mode ? 1000 : 5000);
    }).catch(() => { timer = setTimeout(poll, 10000); });
  }

  btns.forEach((b) => b.addEventListener("click", () => {
    busy = true;
    btns.forEach((x) => { x.disabled = true; });
    window.timpsApiReady().then((api) => api.set({ testpattern: { mode: +b.dataset.tp } }))
      .catch(() => {}).then(() => { busy = false; poll(); });
  }));

  if (window.timpsApiReady) poll();
})();
