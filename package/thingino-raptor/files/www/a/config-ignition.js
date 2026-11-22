(function () {
  "use strict";

  const BASE = "/api/v1/settings/ignition/";
  const el = (id) => document.getElementById(id);
  let loaded = null;

  function status(text, cls) {
    const s = el("ignitionStatus");
    s.className = "ms-2 " + (cls || "");
    s.textContent = text;
  }

  async function load(helper) {
    try {
      const [park, g, delay] = await Promise.all([
        helper.agentRequest(BASE + "park", { cache: "no-store" }),
        helper.agentRequest(BASE + "park-impact-g", { cache: "no-store" }),
        helper.agentRequest(BASE + "off-delay", { cache: "no-store" }),
      ]);
      loaded = {
        park: park.park === true || park.park === "true",
        g: Number(g.park_impact_g),
        minutes: Math.round(Number(delay.off_delay) / 60),
      };
      el("ignitionPark").checked = loaded.park;
      el("ignitionImpactG").value = loaded.g;
      el("ignitionOffDelay").value = loaded.minutes;
    } catch (err) {
      el("ignitionUnavailable").classList.remove("d-none");
      el("ignitionForm").classList.add("d-none");
    }
  }

  async function save(helper, ev) {
    ev.preventDefault();
    const park = el("ignitionPark").checked;
    const g = Number(el("ignitionImpactG").value);
    const minutes = Number(el("ignitionOffDelay").value);
    if (!(g >= 0 && g <= 16)) return status("Impact threshold must be 0 to 16 g", "text-danger");
    if (!(Number.isInteger(minutes) && minutes >= 0 && minutes <= 1440))
      return status("Power off must be 0 to 1440 minutes", "text-danger");

    const writes = [];
    const patch = (leaf, body) => helper.agentRequest(BASE + leaf, { method: "PATCH", body });
    if (!loaded || park !== loaded.park) writes.push(patch("park", { park }));
    if (!loaded || g !== loaded.g) writes.push(patch("park-impact-g", { park_impact_g: g }));
    if (!loaded || minutes !== loaded.minutes) writes.push(patch("off-delay", { off_delay: minutes * 60 }));
    if (!writes.length) return status("No changes", "text-muted");

    el("ignitionSubmit").disabled = true;
    try {
      await Promise.all(writes);
      loaded = { park, g, minutes };
      status("Saved", "text-success");
    } catch (err) {
      status("Save failed: " + (err && err.message ? err.message : err), "text-danger");
    } finally {
      el("ignitionSubmit").disabled = false;
    }
  }

  function start() {
    const helper = window.thinginoStreamer;
    if (!helper || !helper.agentRequest) {
      el("ignitionUnavailable").classList.remove("d-none");
      return;
    }
    load(helper);
    el("ignitionForm").addEventListener("submit", (ev) => save(helper, ev));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
