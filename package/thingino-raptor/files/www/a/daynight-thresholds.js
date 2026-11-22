(function () {
  "use strict";

  const BASE = "/api/v1/settings/ric/";
  const NUMBERS = [
    "night_luma",
    "night_gain",
    "day_gain_pct",
    "probe_gain_pct",
    "probe_holdoff_sec",
    "night_threshold",
    "day_threshold",
    "adc_night",
    "adc_day",
    "photo_ev_night",
    "photo_ev_deep",
    "photo_ev_day",
    "hysteresis_sec",
    "night_fps",
  ];
  const SWITCHES = ["ir850", "ir940"];

  const $id = (id) => document.getElementById(id);
  const trigger = $id("ric_trigger");
  const saveBtn = $id("save-photosensing");
  let loaded = {};

  function notify(type, message) {
    if (window.showAlert) window.showAlert(type, message, 6000);
    else alert(message);
  }

  function showTriggerCards() {
    document.querySelectorAll("[data-trigger]").forEach((card) => {
      card.classList.toggle("d-none", card.dataset.trigger !== trigger.value);
    });
  }

  function read() {
    const values = { trigger: trigger.value };
    NUMBERS.forEach((key) => {
      const v = $id("ric_" + key).value.trim();
      values[key] = v === "" ? null : Number(v);
    });
    SWITCHES.forEach((key) => {
      values[key] = $id("ric_" + key).checked;
    });
    return values;
  }

  async function load() {
    try {
      const cfg = await agentJsonRequest(BASE + "settings", {
        cache: "no-store",
      });
      if (cfg.trigger) trigger.value = cfg.trigger;
      NUMBERS.forEach((key) => {
        if (cfg[key] !== undefined) $id("ric_" + key).value = cfg[key];
      });
      SWITCHES.forEach((key) => {
        $id("ric_" + key).checked = cfg[key] === true;
      });
      loaded = read();
    } catch (err) {
      console.error("Failed to load photosensing settings", err);
      notify("danger", "Failed to load photosensing settings: " + err.message);
    }
    showTriggerCards();
  }

  async function refreshLive() {
    try {
      const st = await agentJsonRequest(BASE + "status", { cache: "no-store" });
      const exp = st.exposure || {};
      $id("live_state").textContent = st.state || "-";
      $id("live_mode").textContent = st.mode || "-";
      $id("live_luma").textContent = exp.ae_luma ?? "-";
      $id("live_gain").textContent = exp.total_gain ?? "-";
      $id("live_ev").textContent = exp.ev ?? "-";
    } catch (err) {
      console.warn("Failed to read ric status", err);
    }
  }

  // Trigger first, so its thresholds land on the trigger the user picked.
  // Each write is applied live by ric, which rejects out-of-range values.
  async function save() {
    saveBtn.disabled = true;
    const now = read();
    const keys = ["trigger", ...NUMBERS, ...SWITCHES];
    try {
      for (const key of keys) {
        if (now[key] === null || now[key] === loaded[key]) continue;
        const res = await agentJsonRequest(BASE + key.replace(/_/g, "-"), {
          method: "PATCH",
          body: { [key]: now[key] },
          cache: "no-store",
        });
        if (!res || res.status !== "accepted") {
          throw new Error(key + " was rejected by the camera");
        }
        loaded[key] = now[key];
      }
      notify("success", "Photosensing settings saved.");
    } catch (err) {
      console.error("Failed to save photosensing settings", err);
      notify("danger", "Failed to save: " + err.message);
    } finally {
      saveBtn.disabled = false;
    }
  }

  trigger.addEventListener("change", showTriggerCards);
  saveBtn.addEventListener("click", save);
  // Seed from the rendered defaults so a failed GET cannot turn Save into a
  // write of trigger=luma and both IR banks off.
  loaded = read();
  load();
  refreshLive();
  setInterval(refreshLive, 3000);
})();
