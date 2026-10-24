(function () {
  "use strict";

  const panel = document.getElementById("tp-panel");
  if (!panel) return;
  const $ = (id) => document.getElementById(id);
  const btns = Array.from(document.querySelectorAll("#tp-btns [data-tp]"));
  const NAMES = ["off", "pattern", "moving square", "motion test", "sensor pattern"];
  const NOTE = "Replaces the camera picture with a synthetic one to check encoder, rotation, OSD and motion detection. Day/night stays in day mode meanwhile.";
  let mode = -1, timer = null, busy = false, err = "", sensor = "";

  function show(j) {
    const caps = (j.caps && j.caps.testpattern) || {};
    panel.hidden = !caps.available;
    if (!caps.available) return false;
    const t = j.testpattern || {};
    mode = +t.mode || 0;
    $("tp-sensor").hidden = !caps.sensor;
    $("tp-holds").hidden = !caps.sensor;
    sensor = caps.sensor ? (caps.sensor_name || "sensor") + (caps.sensor_desc ? ", " + caps.sensor_desc : "") : "";
    if (mode === 4) { $("tp-ae").checked = !!t.ae_hold; $("tp-awb").checked = !!t.awb_hold; }
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
    } else if (t.pending) {
      $("tp-note").textContent = "Switching to day mode first; the sensor pattern follows once the exposure has settled (a few seconds).";
    } else if (mode === 4) {
      $("tp-note").textContent = "The sensor outputs its own test pattern (" + sensor + "), so it runs through the whole ISP. AE" +
        ($("tp-ae").checked ? " is held" : " keeps running") + ", white balance" + ($("tp-awb").checked ? " is held." : " keeps running.");
    } else {
      if (+t.refused === 4) err = "The sensor refused its test pattern (no register table for it, or the driver cannot write sensor registers).";
      $("tp-note").textContent = err || NOTE;
    }
    return true;
  }

  function poll() {
    clearTimeout(timer);
    window.timpsApiReady().then((api) => api.get()).then((j) => {
      if (show(j)) timer = setTimeout(poll, mode || (j.testpattern && j.testpattern.pending) ? 1000 : 5000);
    }).catch(() => { timer = setTimeout(poll, 10000); });
  }

  function send(m) {
    busy = true; err = "";
    btns.forEach((x) => { x.disabled = true; });
    const tp = { mode: m };
    if (m === 4) { tp.ae_hold = $("tp-ae").checked ? 1 : 0; tp.awb_hold = $("tp-awb").checked ? 1 : 0; }
    window.timpsApiReady().then((api) => api.set({ testpattern: tp })).then((r) => {
      if (r && r.rejected) err = m === 4 ? "The sensor refused its test pattern (no register table for it, or it is not running)." :
        "The camera refused this test pattern.";
    }).catch(() => {}).then(() => { busy = false; poll(); });
  }
  btns.forEach((b) => b.addEventListener("click", () => send(+b.dataset.tp)));
  ["tp-ae", "tp-awb"].forEach((id) => $(id).addEventListener("change", () => { if (mode === 4) send(4); }));

  if (window.timpsApiReady) poll();
})();
