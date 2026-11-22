(function () {
  "use strict";

  const KN_TO_KMH = 1.852;
  const KN_TO_MPH = 1.15078;
  const IMPACT_SCALE_G = 2; // full bar
  let speedUnit = "kmh";

  const el = (id) => document.getElementById(id);
  const set = (id, text) => {
    const e = el(id);
    if (e) e.textContent = text;
  };

  function badge(state) {
    const b = el("gpsState");
    const map = {
      fix: ["text-bg-success", "Fix"],
      nofix: ["text-bg-warning", "No fix"],
      nogps: ["text-bg-secondary", "No GPS"],
    };
    const [cls, text] = map[state];
    b.className = "badge " + cls;
    b.textContent = text;
  }

  function coord(v, pos, neg) {
    return Math.abs(v).toFixed(5) + "° " + (v >= 0 ? pos : neg);
  }

  function render(s) {
    el("gpsUnavailable").classList.add("d-none");
    badge(!s.gps ? "nogps" : s.fix ? "fix" : "nofix");
    el("gpsEvent").classList.toggle("d-none", !s.event);

    set("gpsSats", s.gps ? s.sats : "–");
    set("gpsHdop", s.fix ? Number(s.hdop).toFixed(1) : "–");
    if (s.fix) {
      const mph = speedUnit === "mph";
      const v = s.speed_kn * (mph ? KN_TO_MPH : KN_TO_KMH);
      set("gpsSpeed", Math.round(v) + (mph ? " mph" : " km/h"));
      set("gpsCourse", Math.round(s.course) + "°");
      set("gpsLat", coord(s.lat, "N", "S"));
      set("gpsLon", coord(s.lon, "E", "W"));
      set("gpsAlt", Math.round(s.alt) + " m");
      const map = el("gpsMap");
      map.href =
        "https://www.openstreetmap.org/?mlat=" + s.lat + "&mlon=" + s.lon + "#map=16/" + s.lat + "/" + s.lon;
      map.classList.remove("d-none");
      el("gpsMapNone").classList.add("d-none");
    } else {
      ["gpsSpeed", "gpsCourse", "gpsLat", "gpsLon", "gpsAlt"].forEach((id) => set(id, "–"));
      el("gpsMap").classList.add("d-none");
      el("gpsMapNone").classList.remove("d-none");
    }

    const now = Date.now() / 1000;
    set("gpsClock", new Date(now * 1000).toISOString().replace("T", " ").slice(0, 19));
    if (s.utc > 0) {
      set("gpsUtc", new Date(s.utc * 1000).toISOString().replace("T", " ").slice(0, 19));
      const diff = Math.round(now - s.utc);
      set("gpsClockDiff", Math.abs(diff) <= 2 ? "in step" : (diff > 0 ? "+" : "") + diff + " s");
    } else {
      set("gpsUtc", "–");
      set("gpsClockDiff", "");
    }

    const hasAccel = Array.isArray(s.accel);
    el("gsensorAxes").classList.toggle("d-none", !hasAccel);
    el("gDevBar").parentElement.classList.toggle("d-none", !hasAccel);
    el("gsensorNone").classList.toggle("d-none", hasAccel);
    if (hasAccel) {
      set("gX", s.accel[0].toFixed(2));
      set("gY", s.accel[1].toFixed(2));
      set("gZ", s.accel[2].toFixed(2));
      set("gDev", Number(s.accel_dev).toFixed(2));
      const bar = el("gDevBar");
      const pct = Math.min(100, (s.accel_dev / IMPACT_SCALE_G) * 100);
      bar.style.width = pct + "%";
      bar.className = "progress-bar " + (s.event ? "bg-danger" : pct > 50 ? "bg-warning" : "bg-success");
    }
  }

  async function poll(helper) {
    try {
      const s = await helper.agentRequest("/api/v1/settings/telematics/status", { cache: "no-store" });
      if (s && s.status === "ok") render(s);
      else throw new Error("no status");
    } catch (err) {
      el("gpsUnavailable").classList.remove("d-none");
      badge("nogps");
    }
  }

  async function start() {
    const helper = window.thinginoStreamer;
    if (!helper || !helper.agentRequest) {
      el("gpsUnavailable").classList.remove("d-none");
      return;
    }
    try {
      const leaf = await helper.agentRequest("/api/v1/settings/telematics/speed-unit", { cache: "no-store" });
      if (leaf && leaf.speed_unit) speedUnit = leaf.speed_unit;
    } catch (err) {
      /* default km/h */
    }
    poll(helper);
    setInterval(() => {
      if (!document.hidden) poll(helper);
    }, 1000);
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
