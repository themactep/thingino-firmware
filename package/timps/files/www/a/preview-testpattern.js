(function () {
  "use strict";

  const panel = document.getElementById("tp-panel");
  if (!panel) return;
  const $ = (id) => document.getElementById(id);
  const btns = Array.from(panel.querySelectorAll("[data-tp]"));
  const nodes = Array.from(panel.querySelectorAll(".tp-node"));
  const arrows = Array.from(panel.querySelectorAll(".tp-arr"));
  const NAMES = ["off", "still", "moving", "motion test", "sensor pattern", "mid-ISP"];
  const NOTE = "Pick a stage: its test picture enters the pipeline there and runs through every stage after it. Day/night stays in day mode meanwhile.";
  const toggle = $("ms-tp-toggle");
  let mode = -1, timer = null, busy = false, err = "", sensor = "", avail = false, live = false;
  let want = false;
  try { want = localStorage.getItem("ms.tp") === "1"; } catch (e) { /* no storage */ }

  // shown on request, and always while a pattern runs
  function place() {
    if (toggle) {
      toggle.hidden = !avail;
      toggle.classList.toggle("active", avail && (want || live));
    }
    panel.hidden = !avail || !(want || live);
  }

  // where each picture enters: the sensor's own (4) at the sensor, mid-ISP (5)
  // inside the ISP, the synthetic ones replace the ISP output (arrow ISP -> encoder)
  function paint(m) {
    const from = m === 4 ? 0 : m === 5 ? 1 : m ? 2 : -1;
    nodes.forEach((n, i) => {
      n.classList.toggle("pass", from >= 0 && i >= from);
      n.classList.toggle("skip", from > 0 && i < from);
      n.classList.toggle("inj", (from === 0 || from === 1) && i === from);
    });
    arrows.forEach((a, i) => {
      a.classList.toggle("pass", from >= 0 && i >= from - 1);
      a.classList.toggle("inj", from === 2 && i === 1);
    });
  }

  function show(j) {
    const caps = (j.caps && j.caps.testpattern) || {};
    const t = j.testpattern || {};
    avail = !!caps.available;
    mode = +t.mode || 0;
    live = avail && (mode !== 0 || !!t.pending);
    place();
    if (!avail) return false;
    const sb = $("tp-sensor");
    sb.disabled = busy || !caps.sensor;
    sb.title = caps.sensor ? "The sensor's own test pattern (" + (caps.sensor_name || "sensor") + "), through the whole ISP" :
      "This sensor has no test pattern in the libimp";
    $("tp-holds").hidden = !caps.sensor;
    const mb = $("tp-mid");
    mb.disabled = busy || !caps.isp_mid;
    mb.title = caps.isp_mid ? "A test picture inside the ISP, after sharpening: colour, scaler, encoder" :
      "Needs an OpenIMP libimp with the mid-ISP pattern (T23 so far)";
    sensor = caps.sensor ? (caps.sensor_name || "sensor") + (caps.sensor_desc ? ", " + caps.sensor_desc : "") : "";
    if (mode === 4) { $("tp-ae").checked = !!t.ae_hold; $("tp-awb").checked = !!t.awb_hold; }
    btns.forEach((b) => {
      const m = +b.dataset.tp;
      b.classList.toggle("on", m !== 0 && m === mode);
      if (m !== 4 && m !== 5) b.disabled = busy || (m === 0 && !mode && !t.pending);
    });
    paint(t.pending ? 4 : mode);
    $("tp-chip").textContent = t.pending ? "sensor pattern · waiting for day" :
      mode ? NAMES[mode] + " · " + (t.frames || 0) + " frames" : "off";
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
    } else if (mode === 5) {
      $("tp-note").textContent = "The picture enters inside the ISP, after sharpening: colour, scaler and encoder process it, the OSD is drawn on top.";
    } else if (mode) {
      $("tp-note").textContent = "The synthetic picture replaces the ISP output: sensor and ISP are bypassed.";
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
  btns.forEach((b) => b.addEventListener("click", () => {
    const m = +b.dataset.tp;
    send(m && m === mode ? 0 : m);
  }));
  ["tp-ae", "tp-awb"].forEach((id) => $(id).addEventListener("change", () => { if (mode === 4) send(4); }));
  if (toggle) toggle.addEventListener("click", () => {
    want = !want;
    try { localStorage.setItem("ms.tp", want ? "1" : "0"); } catch (e) { /* no storage */ }
    place();
    if (want) poll();
  });

  if (window.timpsApiReady) poll();
})();
