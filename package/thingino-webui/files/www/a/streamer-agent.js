/**
 * Shared helpers for streamer-agnostic WebUI controls via the camera agent.
 * Depends on window.agentApiUrl / agentJsonRequest from main.js when available.
 */
(function (global) {
  "use strict";

  function getStreamerName() {
    const ui = global.thinginoUIConfig || {};
    const device = ui.device || {};
    if (typeof device.streamer === "string" && device.streamer) {
      return device.streamer;
    }
    return "prudynt";
  }

  function isRaptor() {
    return getStreamerName() === "raptor";
  }

  function preferAgent() {
    return typeof global.agentJsonRequest === "function";
  }

  async function agentRequest(path, options) {
    if (!preferAgent()) {
      throw new Error("agentJsonRequest is not available");
    }
    return global.agentJsonRequest(path, options);
  }

  async function saveStreamerConfig() {
    const streamer = getStreamerName();
    if (streamer === "raptor") {
      const res = await fetch("/x/json-streamer-save.cgi", { method: "POST" });
      if (!res.ok) throw new Error("HTTP " + res.status);
      const data = await res.json().catch(() => ({}));
      if (data.error) throw new Error(data.error.message || "Save failed");
      return data;
    }
    // prudynt (and unknown): existing save_config action
    const res = await fetch("/x/json-prudynt.cgi", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ action: { save_config: null } }),
    });
    if (!res.ok) throw new Error("HTTP " + res.status);
    const data = await res.json();
    if (!data?.action || data.action.save_config !== "ok") {
      throw new Error("Save failed");
    }
    return data;
  }

  function saveConfirmMessage() {
    if (isRaptor()) {
      return "Save the current configuration to /etc/raptor.conf?\n\nThis will overwrite the saved configuration file on the camera.";
    }
    return "Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.";
  }

  function saveSuccessMessage() {
    return isRaptor()
      ? "Configuration saved successfully to /etc/raptor.conf"
      : "Configuration saved successfully to /etc/prudynt.json";
  }

  /** Map a prudynt-shaped write payload onto agent setting PATCH calls. */
  async function applyPrudyntShapedPayload(payload) {
    const patches = [];

    function queue(path, body) {
      patches.push(agentRequest("/api/v1/settings/" + path, {
        method: "PATCH",
        body,
        cache: "no-store",
      }));
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
          const bodyKey = key;
          queue("streams/" + id + "/osd/" + section + "/" + leaf, {
            [bodyKey]: node[key],
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

  /** Convert agent GET /config into a prudynt-shaped object for handleMessage. */
  function configToPreviewMessage(cfg) {
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

  function hideRaptorUnsupportedControls(root) {
    if (!isRaptor()) return;
    const doc = root || document;
    // max_gop has no raptor backend; keep hidden.
    const unsupported = ["max_gop"];
    [0, 1].forEach((id) => {
      unsupported.forEach((param) => {
        const el = doc.querySelector("#stream" + id + "_" + param);
        if (!el) return;
        const wrap =
          el.closest(".mb-3, .col, .form-check, .row > div") || el.parentElement;
        if (wrap) wrap.classList.add("d-none");
        el.disabled = true;
      });
    });
    unsupported.forEach((param) => {
      const el = doc.querySelector("#image_" + param);
      if (!el) return;
      const wrap =
        el.closest(".mb-3, .col, .form-check, .row > div") || el.parentElement;
      if (wrap) wrap.classList.add("d-none");
      el.disabled = true;
    });
  }

  global.thinginoStreamerAgent = {
    getStreamerName,
    isRaptor,
    preferAgent,
    agentRequest,
    saveStreamerConfig,
    saveConfirmMessage,
    saveSuccessMessage,
    applyPrudyntShapedPayload,
    configToPreviewMessage,
    hideRaptorUnsupportedControls,
  };
})(window);
