/**
 * Agent-backed helpers for raptor streamer WebUI pages.
 * Depends on window.agentJsonRequest from main.js when available.
 */
(function (global) {
  "use strict";

  function preferAgent() {
    return typeof global.agentJsonRequest === "function";
  }

  async function agentRequest(path, options) {
    if (!preferAgent()) {
      throw new Error("agentJsonRequest is not available");
    }
    // Several scripts on one page read the full config, which takes seconds
    // on T20, so they share one request.
    const method = ((options && options.method) || "GET").toUpperCase();
    if (
      method === "GET" &&
      path === "/api/v1/config" &&
      typeof global.getThinginoAgentConfig === "function"
    ) {
      return global.getThinginoAgentConfig();
    }
    if (
      method !== "GET" &&
      typeof global.invalidateThinginoAgentConfig === "function"
    ) {
      // Clear the cache after the write settles, so a read racing the write
      // cannot leave the pre-write config cached.
      try {
        return await global.agentJsonRequest(path, options);
      } finally {
        global.invalidateThinginoAgentConfig();
      }
    }
    return global.agentJsonRequest(path, options);
  }

  async function saveConfig() {
    const res = await fetch("/x/json-config-save.cgi", { method: "POST" });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json().catch(() => ({}));
    if (data.error) throw new Error(data.error.message || "Save failed");
    return data;
  }

  function saveConfirmMessage() {
    return "Save the current configuration to /etc/raptor.conf?\n\nThis will overwrite the saved configuration file on the camera.";
  }

  function saveSuccessMessage() {
    return "Configuration saved successfully to /etc/raptor.conf";
  }

  /** Map form-shaped write payload onto agent setting PATCH calls. */
  async function applyPayload(payload) {
    const patches = [];

    function queue(path, body) {
      patches.push(
        agentRequest("/api/v1/settings/" + path, {
          method: "PATCH",
          body,
          cache: "no-store",
        }),
      );
    }

    if (payload.image) {
      const img = payload.image;
      [
        "brightness",
        "contrast",
        "saturation",
        "sharpness",
        "hflip",
        "vflip",
        "ae_compensation",
        "core_wb_mode",
        "wb_rgain",
        "wb_bgain",
      ].forEach((key) => {
        if (img[key] !== undefined && img[key] !== null) {
          queue("image/" + key.replace(/_/g, "-"), { [key]: img[key] });
        }
      });
      if (img.anti_flicker !== undefined && img.anti_flicker !== null) {
        queue("image/anti-flicker", { anti_flicker: img.anti_flicker });
      }
    }

    [0, 1].forEach((id) => {
      const stream = payload["stream" + id];
      if (!stream) return;
      const map = {
        enabled: "enabled",
        audio_enabled: "audio-enabled",
        width: "width",
        height: "height",
        fps: "fps",
        bitrate: "bitrate",
        gop: "gop",
        buffers: "buffers",
        profile: "profile",
        rtsp_endpoint: "rtsp-endpoint",
        format: "format",
        mode: "mode",
      };
      Object.keys(map).forEach((key) => {
        if (stream[key] !== undefined && stream[key] !== null) {
          const bodyKey = key === "audio_enabled" ? "audio_enabled" : key;
          queue("streams/" + id + "/" + map[key], { [bodyKey]: stream[key] });
        }
      });

      const osd = stream.osd;
      if (!osd) return;
      if (osd.enabled !== undefined && osd.enabled !== null) {
        queue("streams/" + id + "/osd/enabled", { enabled: osd.enabled });
      }
      if (osd.font_path !== undefined && osd.font_path !== null) {
        queue("streams/" + id + "/osd/font-path", { font_path: osd.font_path });
      }
      if (osd.font_size !== undefined && osd.font_size !== null) {
        queue("streams/" + id + "/osd/font-size", { font_size: osd.font_size });
      }
      if (osd.stroke_size !== undefined && osd.stroke_size !== null) {
        queue("streams/" + id + "/osd/stroke-size", {
          stroke_size: osd.stroke_size,
        });
      }
      ["time", "uptime", "usertext", "logo", "privacy"].forEach((section) => {
        const node = osd[section];
        if (!node || typeof node !== "object") return;
        Object.keys(node).forEach((key) => {
          if (node[key] === undefined || node[key] === null) return;
          const leaf = key.replace(/_/g, "-");
          queue("streams/" + id + "/osd/" + section + "/" + leaf, {
            [key]: node[key],
          });
        });
      });
    });

    if (payload.privacy && payload.privacy.enabled !== undefined) {
      await agentRequest("/api/v1/actions/privacy", {
        method: "POST",
        body: { enabled: !!payload.privacy.enabled },
        cache: "no-store",
      });
    }

    if (payload.motion && payload.motion.enabled !== undefined) {
      queue("motion/enabled", { enabled: payload.motion.enabled });
    }

    if (!patches.length && !payload.privacy) {
      return false;
    }
    await Promise.all(patches);
    return true;
  }

  /** Convert agent GET /config into form-shaped object for handleMessage. */
  function configToMessage(cfg) {
    const msg = {
      image: cfg.image || {},
      motion: cfg.motion || {},
      privacy: cfg.privacy || {},
    };
    const streams = Array.isArray(cfg.streams) ? cfg.streams : [];
    streams.forEach((s) => {
      if (!s || s.id === undefined) return;
      msg["stream" + s.id] = {
        enabled: s.enabled,
        audio_enabled: s.audio_enabled,
        width: s.width,
        height: s.height,
        fps: s.fps,
        bitrate: s.bitrate,
        gop: s.gop,
        buffers: s.buffers,
        profile: s.profile,
        rtsp_endpoint: s.rtsp_endpoint,
        format: s.format,
        mode: s.mode,
        osd: s.osd || undefined,
      };
    });
    return msg;
  }

  function hideUnsupportedControls(root) {
    const doc = root || document;
    const unsupportedStream = ["max_gop"];
    const unsupportedImage = [
      "max_gop",
      "backlight",
      "wide_dynamic_range",
      "tone",
      "defog",
      "noise_reduction",
    ];
    [0, 1].forEach((id) => {
      unsupportedStream.forEach((param) => {
        const el = doc.querySelector("#stream" + id + "_" + param);
        if (!el) return;
        const wrap =
          el.closest(".mb-3, .col, .form-check, .row > div, p") ||
          el.parentElement;
        if (wrap) wrap.classList.add("d-none");
        el.disabled = true;
      });
    });
    unsupportedImage.forEach((param) => {
      const el =
        doc.querySelector("#" + param) ||
        doc.querySelector("#image_" + param);
      if (!el) return;
      const wrap =
        el.closest(".mb-3, .col, .form-check, .row > div, p") || el.parentElement;
      if (wrap) wrap.classList.add("d-none");
      el.disabled = true;
    });
  }

  global.thinginoStreamer = {
    preferAgent,
    agentRequest,
    saveConfig,
    saveConfirmMessage,
    saveSuccessMessage,
    applyPayload,
    configToMessage,
    hideUnsupportedControls,
  };
})(window);
