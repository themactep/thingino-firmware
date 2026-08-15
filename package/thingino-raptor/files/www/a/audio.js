(function () {
  "use strict";

  const api = () => window.thinginoStreamer;

  async function loadAudioConfig() {
    const helper = api();
    if (!helper || !helper.preferAgent || !helper.preferAgent()) {
      hideUnsupported();
      return;
    }
    try {
      const mic = await helper.agentRequest("/api/v1/settings/audio/mic-enabled", {
        cache: "no-store",
      });
      const spk = await helper.agentRequest("/api/v1/settings/audio/spk-enabled", {
        cache: "no-store",
      });
      const micEl = $("#audio_mic_enabled");
      const spkEl = $("#audio_spk_enabled");
      if (micEl && mic && typeof mic.mic_enabled !== "undefined") {
        micEl.checked = !!mic.mic_enabled;
      }
      if (spkEl && spk && typeof spk.spk_enabled !== "undefined") {
        spkEl.checked = !!spk.spk_enabled;
      }
    } catch (err) {
      console.warn("audio load failed:", err);
    }
    hideUnsupported();
  }

  function hideUnsupported() {
    // Only mic/spk toggles are mapped; hide the rest of the form.
    const keep = new Set(["audio_mic_enabled", "audio_spk_enabled"]);
    document.querySelectorAll("input, select, textarea").forEach((el) => {
      if (!el.id || keep.has(el.id)) return;
      if (!el.id.startsWith("audio_")) return;
      const wrap =
        el.closest(".mb-3, .col, .form-check, .row > div") || el.parentElement;
      if (wrap) wrap.classList.add("d-none");
      el.disabled = true;
    });
  }

  async function saveAudioValue(path, body) {
    const helper = api();
    if (!helper || !helper.agentRequest) {
      throw new Error("Agent unavailable");
    }
    await helper.agentRequest("/api/v1/settings/" + path, {
      method: "PATCH",
      body,
      cache: "no-store",
    });
  }

  document.addEventListener("DOMContentLoaded", () => {
    loadAudioConfig();
    const micEl = $("#audio_mic_enabled");
    const spkEl = $("#audio_spk_enabled");
    if (micEl) {
      micEl.addEventListener("change", async () => {
        try {
          await saveAudioValue("audio/mic-enabled", {
            mic_enabled: !!micEl.checked,
          });
        } catch (err) {
          console.error(err);
        }
      });
    }
    if (spkEl) {
      spkEl.addEventListener("change", async () => {
        try {
          await saveAudioValue("audio/spk-enabled", {
            spk_enabled: !!spkEl.checked,
          });
        } catch (err) {
          console.error(err);
        }
      });
    }
  });
})();
