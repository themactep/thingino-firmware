(function () {
  "use strict";

  const api = () => window.thinginoStreamer;

  // Page field -> agent setting leaf. Each write is applied live by rad and
  // saved to raptor.conf by the agent.
  const FIELDS = [
    { id: "audio_mic_format", path: "mic-format", key: "mic_format" },
    { id: "audio_mic_vol", path: "mic-vol", key: "mic_vol" },
    { id: "audio_mic_gain", path: "mic-gain", key: "mic_gain" },
    {
      id: "audio_mic_noise_suppression",
      path: "mic-noise-suppression",
      key: "mic_noise_suppression",
    },
    {
      id: "audio_mic_high_pass_filter",
      path: "mic-high-pass-filter",
      key: "mic_high_pass_filter",
    },
    {
      id: "audio_mic_agc_enabled",
      path: "mic-agc-enabled",
      key: "mic_agc_enabled",
    },
    {
      id: "audio_mic_agc_target_level_dbfs",
      path: "mic-agc-target-level-dbfs",
      key: "mic_agc_target_level_dbfs",
    },
    {
      id: "audio_mic_agc_compression_gain_db",
      path: "mic-agc-compression-gain-db",
      key: "mic_agc_compression_gain_db",
    },
    { id: "audio_spk_vol", path: "spk-vol", key: "spk_vol" },
    { id: "audio_spk_gain", path: "spk-gain", key: "spk_gain" },
  ];

  // Controls raptor has no equivalent for.
  const UNSUPPORTED = ["audio_mic_alc_gain", "audio_force_stereo"];

  function showAlert(type, message, duration) {
    if (window.showAlert) {
      window.showAlert(type, message, duration);
      return;
    }
    if (type === "danger") alert(message);
  }

  function hideUnsupported() {
    UNSUPPORTED.forEach((id) => {
      const el = document.getElementById(id);
      if (!el) return;
      const wrap = el.closest("p") || el.parentElement;
      if (wrap) wrap.classList.add("d-none");
      el.disabled = true;
    });
    const g726 = document.querySelector(
      '#audio_mic_format option[value="G726"]',
    );
    if (g726) g726.remove();
  }

  function setField(el, value) {
    if (value === null || typeof value === "undefined") return;
    if (el.type === "checkbox") {
      el.checked = value === true;
    } else {
      el.value = String(value);
      const slider = document.getElementById(el.id + "-slider");
      if (slider) slider.value = value;
    }
  }

  function readField(el) {
    if (el.type === "checkbox") return el.checked;
    if (el.tagName === "SELECT") return el.value;
    const n = Number(el.value);
    return Number.isFinite(n) ? n : null;
  }

  async function loadAudioConfig() {
    const helper = api();
    if (!helper || !helper.agentRequest) return;
    const reload = document.getElementById("audio-reload");
    if (reload) reload.disabled = true;
    await Promise.all(
      FIELDS.map(async (f) => {
        const el = document.getElementById(f.id);
        if (!el) return;
        try {
          const data = await helper.agentRequest(
            "/api/v1/settings/audio/" + f.path,
            { cache: "no-store" },
          );
          setField(el, data ? data[f.key] : null);
        } catch (err) {
          console.warn("audio load failed:", f.path, err);
        }
      }),
    );
    if (reload) reload.disabled = false;
  }

  async function saveField(f, el) {
    const helper = api();
    const value = readField(el);
    if (!helper || !helper.agentRequest || value === null || value === "")
      return;
    try {
      await helper.agentRequest("/api/v1/settings/audio/" + f.path, {
        method: "PATCH",
        body: { [f.key]: value },
        cache: "no-store",
      });
    } catch (err) {
      showAlert(
        "danger",
        "Failed to update " + f.key + ": " + (err.message || err),
        6000,
      );
    }
  }

  document.addEventListener("DOMContentLoaded", () => {
    hideUnsupported();
    FIELDS.forEach((f) => {
      const el = document.getElementById(f.id);
      if (el) el.addEventListener("change", () => saveField(f, el));
    });
    const reload = document.getElementById("audio-reload");
    if (reload) reload.addEventListener("click", loadAudioConfig);
    const save = document.getElementById("save-config");
    if (save) {
      save.addEventListener("click", async () => {
        const helper = api();
        try {
          if (helper && helper.saveConfig) await helper.saveConfig();
          showAlert("success", "Audio configuration saved", 4000);
        } catch (err) {
          showAlert("danger", "Failed to save: " + (err.message || err), 6000);
        }
      });
    }
    loadAudioConfig();
  });
})();
