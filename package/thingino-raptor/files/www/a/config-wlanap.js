(function () {
  "use strict";

  const BASE = "/api/v1/settings/wlan-ap/";
  const el = (id) => document.getElementById(id);
  let loaded = null;

  function status(text, cls) {
    const s = el("apStatus");
    s.className = "ms-2 " + (cls || "");
    s.textContent = text;
  }

  function showState(st) {
    const badge = el("apState");
    badge.textContent = st.running ? (st.timer ? "On (timer running)" : "On") : "Off";
    badge.className = "badge " + (st.running ? "text-bg-success" : "text-bg-secondary");
    el("apSsid").textContent = st.ssid || "–";
    el("apIp").textContent = st.running ? st.ip : "–";
    el("apBand").textContent = st.freq ? (st.freq >= 5000 ? "5 GHz" : "2.4 GHz") + " (" + st.freq + " MHz)" : "–";
    el("apOn").disabled = st.running;
    el("apOff").disabled = !st.running;
  }

  async function refresh(helper) {
    showState(await helper.agentRequest(BASE + "state", { cache: "no-store" }));
  }

  async function load(helper) {
    try {
      const [mode, timeout, band, ssid, password] = await Promise.all(
        ["mode", "timeout", "band", "ssid", "password"].map((k) =>
          helper.agentRequest(BASE + k, { cache: "no-store" })
        )
      );
      loaded = {
        mode: mode.mode,
        minutes: Math.round(Number(timeout.timeout) / 60),
        band: band.band,
        ssid: ssid.ssid || "",
        password: password.password,
      };
      el("apMode").value = loaded.mode;
      el("apTimeout").value = loaded.minutes;
      el("apBandPref").value = loaded.band;
      el("apSsidIn").value = loaded.ssid;
      el("apPassword").value = loaded.password;
      await refresh(helper);
    } catch (err) {
      el("apUnavailable").classList.remove("d-none");
      el("apContent").classList.add("d-none");
    }
  }

  async function setRunning(helper, running) {
    el("apOn").disabled = el("apOff").disabled = true;
    try {
      await helper.agentRequest(BASE + "state", { method: "PATCH", body: { running } });
      await refresh(helper);
    } catch (err) {
      status("Failed: " + (err && err.message ? err.message : err), "text-danger");
      refresh(helper).catch(() => {});
    }
  }

  async function save(helper, ev) {
    ev.preventDefault();
    const now = {
      mode: el("apMode").value,
      minutes: Number(el("apTimeout").value),
      band: el("apBandPref").value,
      ssid: el("apSsidIn").value.trim(),
      password: el("apPassword").value,
    };
    if (!(Number.isInteger(now.minutes) && now.minutes >= 0 && now.minutes <= 1440))
      return status("Timeout must be 0 to 1440 minutes", "text-danger");
    if (now.ssid.length > 32 || /["\\]/.test(now.ssid))
      return status("Network name: up to 32 characters, no quotes or backslashes", "text-danger");
    if (now.password.length < 8 || now.password.length > 63 || /["\\]/.test(now.password))
      return status("Password: 8 to 63 characters, no quotes or backslashes", "text-danger");

    const patch = (leaf, body) => helper.agentRequest(BASE + leaf, { method: "PATCH", body });
    const writes = [];
    if (!loaded || now.mode !== loaded.mode) writes.push(patch("mode", { mode: now.mode }));
    if (!loaded || now.minutes !== loaded.minutes) writes.push(patch("timeout", { timeout: now.minutes * 60 }));
    if (!loaded || now.band !== loaded.band) writes.push(patch("band", { band: now.band }));
    if (!loaded || now.ssid !== loaded.ssid) writes.push(patch("ssid", { ssid: now.ssid }));
    if (!loaded || now.password !== loaded.password) writes.push(patch("password", { password: now.password }));
    if (!writes.length) return status("No changes", "text-muted");

    el("apSubmit").disabled = true;
    try {
      await Promise.all(writes);
      loaded = now;
      status("Saved", "text-success");
      refresh(helper).catch(() => {});
    } catch (err) {
      status("Save failed: " + (err && err.message ? err.message : err), "text-danger");
    } finally {
      el("apSubmit").disabled = false;
    }
  }

  function start() {
    const helper = window.thinginoStreamer;
    if (!helper || !helper.agentRequest) {
      el("apUnavailable").classList.remove("d-none");
      el("apContent").classList.add("d-none");
      return;
    }
    load(helper);
    el("apOn").addEventListener("click", () => setRunning(helper, true));
    el("apOff").addEventListener("click", () => setRunning(helper, false));
    el("apForm").addEventListener("submit", (ev) => save(helper, ev));
  }

  if (document.readyState === "loading") document.addEventListener("DOMContentLoaded", start);
  else start();
})();
