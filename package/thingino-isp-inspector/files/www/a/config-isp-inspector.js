(function () {
  "use strict";

  // ── DOM refs ───────────────────────────────────────────────────
  const autoRefreshCb = $("#auto-refresh");
  const pollIntervalSel = $("#poll-interval");
  const pollStatus = $("#isp-poll-status");
  const errorAlert = $("#isp-error-alert");
  const statsRow = $("#isp-stats-row");
  const ispHdrPlatform = $("#isp-hdr-platform");
  const ispHdrSensor = $("#isp-hdr-sensor");
  const ispHdrRes = $("#isp-hdr-res");
  const ispHdrImg = $("#isp-hdr-img");
  const ispHdrAf = $("#isp-hdr-af");
  const ispHdrOrient = $("#isp-hdr-orient");
  const issuesCard = $("#isp-issues-card");
  const issuesCount = $("#isp-issues-count");
  const issuesBody = $("#isp-issues-body");
  const rawM0 = $("#raw-isp-m0");
  const rawFs = $("#raw-isp-fs");

  // ── LLM refs ───────────────────────────────────────────────────
  const apiKeyInput = $("#llm-api-key");
  const apiKeyToggle = $("#llm-api-key-toggle");
  const providerSel = $("#llm-provider");
  const modelInput = $("#llm-model");
  const endpointInput = $("#llm-endpoint");
  const analyzeBtn = $("#llm-analyze-btn");
  const llmStatus = $("#llm-status");
  const llmResponse = $("#llm-response");

  // ── State ───────────────────────────────────────────────────────
  const MAX_HISTORY = 120; // 10 min at 5s poll
  let history = [];
  let lastData = null;
  let lastFs = null;
  let charts = {};

  // ── LLM config ──────────────────────────────────────────────────
  const LLM_STORAGE_KEY = "isp_inspector_llm";

  function loadLlmConfig() {
    try {
      const raw = localStorage.getItem(LLM_STORAGE_KEY);
      if (raw) {
        const cfg = JSON.parse(raw);
        if (cfg.apiKey) apiKeyInput.value = cfg.apiKey;
        if (cfg.provider) providerSel.value = cfg.provider;
        if (cfg.model) modelInput.value = cfg.model;
        if (cfg.endpoint) endpointInput.value = cfg.endpoint;
      }
    } catch (_) { /* ignore */ }
  }

  function saveLlmConfig() {
    try {
      localStorage.setItem(LLM_STORAGE_KEY, JSON.stringify({
        apiKey: apiKeyInput.value || "",
        provider: providerSel.value,
        model: modelInput.value,
        endpoint: endpointInput.value || ""
      }));
    } catch (_) { /* ignore */ }
  }

  function getLlmEndpoint() {
    switch (providerSel.value) {
      case "deepseek": return "https://api.deepseek.com/v1/chat/completions";
      case "openai": return "https://api.openai.com/v1/chat/completions";
      case "custom": return (endpointInput.value || "").replace(/\/+$/, "") + "/v1/chat/completions";
      default: return "https://api.deepseek.com/v1/chat/completions";
    }
  }

  function getLlmModel() {
    return modelInput.value || "deepseek-chat";
  }

  function updateLlmUi() {
    const hasKey = !!apiKeyInput.value.trim();
    analyzeBtn.disabled = !hasKey;
    endpointInput.disabled = providerSel.value !== "custom";
    if (providerSel.value === "deepseek") modelInput.value = "deepseek-chat";
    else if (providerSel.value === "openai" && modelInput.value === "deepseek-chat") modelInput.value = "gpt-4o-mini";
  }

  // ── Alert helper ────────────────────────────────────────────────
  function showAlert(type, msg) {
    if (typeof window.showAlert === "function") {
      window.showAlert(type, msg);
    }
  }

  // ── Stats card builder ─────────────────────────────────────────
  function statCard(label, value, unit, status) {
    const colors = { ok: "success", warn: "warning", crit: "danger", info: "secondary" };
    const c = colors[status] || "secondary";

    return '<div class="col">' +
      '<div class="card isp-stat-card h-100 border-' + c + '">' +
      '<div class="card-body d-flex flex-column p-1 p-md-2">' +
      '<div class="isp-stat-label text-muted">' + (label || "&nbsp;") + '</div>' +
      '<div class="isp-stat-value text-' + c + '">' + (value || "-") +
      (unit ? ' <small class="text-muted">' + unit + '</small>' : "") + '</div>' +
      '</div></div></div>';
  }

  // ── Issue detection ────────────────────────────────────────────
  function detectIssues(data, fsData) {
    var issues = [];

    // FPS: check if num/div ratio is below common targets
    if (data.fps && data.fps.num && data.fps.div) {
      var fps = parseFloat(data.fps.num) / parseFloat(data.fps.div);
      if (fps < 10) {
        issues.push({ severity: "crit", msg: "FPS critically low: " + fps.toFixed(1) + " fps" +
          " (causes: integration time at max, sensor bottleneck, high gain)" });
      } else if (fps < 15) {
        issues.push({ severity: "warn", msg: "FPS low: " + fps.toFixed(1) + " fps" +
          " (may be normal at night; check integration time)" });
      }
    }

    // Integration time at max → FPS floor
    var intTime = parseInt(data.exposure.int_time, 10);
    var intMax = parseInt(data.exposure.int_time_max, 10);
    if (intMax > 0 && intTime >= intMax) {
      issues.push({ severity: "warn", msg: "Integration time at maximum (" + intTime + " / " + intMax +
        " lines) — sensor at FPS floor. Normal at night, but if scene is bright, check AE config." });
    }

    // Analog gain at max → struggling for light
    var again = parseInt(data.exposure.again, 10);
    var againMax = parseInt(data.exposure.again_max, 10);
    if (againMax > 0 && again >= againMax) {
      issues.push({ severity: "crit", msg: "Analog gain pinned at maximum (" + again + " / " + againMax +
        ") — image will be extremely noisy. Scene is too dark or IR illumination failed." });
    } else if (againMax > 0 && again > againMax * 0.8) {
      issues.push({ severity: "warn", msg: "Analog gain high (" + again + " / " + againMax +
        ") — approach noise ceiling. Check lighting or IR-cut filter state." });
    }

    // Digital gain in use while analog has headroom → driver misconfiguration
    var dgain = parseInt(data.exposure.dgain, 10);
    if (dgain > 0 && againMax > 0 && again < againMax * 0.5) {
      issues.push({ severity: "warn", msg: "Digital gain active (" + dgain +
        ") while analog gain has headroom (" + again + " / " + againMax +
        ") — analog gain is always preferable. Possible driver misconfiguration." });
    }

    // Frame source buffer issues
    if (fsData && fsData.ch0) {
      var drop = parseInt(fsData.ch0.drop, 10);
      var intc = parseInt(fsData.ch0.intc_ahead, 10);
      if (drop > 0) {
        issues.push({ severity: "crit", msg: "Frame drops on channel 0: " + drop +
          " frames dropped. Buffer starvation — reduce resolution, drop sub stream, or lower FPS." });
      }
      if (intc > 0) {
        issues.push({ severity: "warn", msg: "Near-misses on channel 0: " + intc +
          " interrupt-ahead events. Pipeline close to dropping frames." });
      }
      var qc = parseInt(fsData.ch0.queue_count, 10);
      if (qc < 2) {
        issues.push({ severity: "crit", msg: "Queue count is " + qc +
          " — pipeline has no slack. Any hiccup will drop a frame." });
      }

      if (fsData.ch1) {
        var drop1 = parseInt(fsData.ch1.drop, 10);
        if (drop1 > 0) {
          issues.push({ severity: "crit", msg: "Frame drops on channel 1 (sub stream): " + drop1 +
            " frames. If ch0 is clean, problem is specific to the sub stream." });
        }
      }
    }

    // WDR and FPS
    if (data.mode && data.mode.wdr === "Enable") {
      issues.push({ severity: "info", msg: "WDR is enabled — effective frame rate is halved (two captures per frame)." });
    }

    // Custom mode off when user may expect tuning
    if (data.mode && data.mode.custom === "Disable" && data.mode.running === "Day") {
      // Only flag if we have a sensor IQ file — we can't check that, so keep it informational
    }

    // Antiflicker disabled
    if (data.antiflicker && (data.antiflicker.mode === "0" || data.antiflicker.mode === "Disable")) {
      issues.push({ severity: "info", msg: "Antiflicker is disabled. If under artificial light, expect rolling bands." });
    }

    return issues;
  }

  function renderIssues(issues) {
    if (!issues || issues.length === 0) {
      issuesCard.classList.add("d-none");
      return;
    }
    issuesCard.classList.remove("d-none");
    var critCount = issues.filter(function(i) { return i.severity === "crit"; }).length;
    var warnCount = issues.filter(function(i) { return i.severity === "warn"; }).length;

    if (critCount > 0) {
      issuesCount.className = "badge bg-danger";
      issuesCount.textContent = critCount + " critical, " + warnCount + " warnings";
    } else if (warnCount > 0) {
      issuesCount.className = "badge bg-warning text-dark";
      issuesCount.textContent = warnCount + " warnings";
    } else {
      issuesCount.className = "badge bg-info";
      issuesCount.textContent = issues.length + " info";
    }

    issuesBody.innerHTML = issues.map(function(i) {
      var cls = i.severity === "crit" ? "isp-issue critical mb-1" :
                i.severity === "warn" ? "isp-issue mb-1" :
                "isp-issue ok mb-1";
      return '<div class="' + cls + '">' +
        '<strong class="text-' + (i.severity === "crit" ? "danger" : i.severity === "warn" ? "warning" : "info") + '">' +
        i.severity.toUpperCase() + '</strong>: ' + i.msg + '</div>';
    }).join("");
  }

  // ── Stats rendering ────────────────────────────────────────────
  function renderStats(data, fsData) {
    var cards = [];

    // Header line
    var plat = data.platform || "?";
    var sn = data.sensor || {};
    var img = data.image || {};
    var af = data.antiflicker || {};

    if (ispHdrPlatform) ispHdrPlatform.textContent = plat.toUpperCase();
    if (ispHdrSensor) ispHdrSensor.textContent = sn.name || "?";
    if (ispHdrRes) ispHdrRes.textContent = (sn.width || "?") + "\u00d7" + (sn.height || "?");

    // Tuning knobs
    var imgParts = [];
    if (img.saturation) imgParts.push("Saturation: " + img.saturation);
    if (img.sharpness) imgParts.push("Sharpness: " + img.sharpness);
    if (img.contrast) imgParts.push("Contrast: " + img.contrast);
    if (img.brightness) imgParts.push("Brightness: " + img.brightness);
    if (ispHdrImg) ispHdrImg.textContent = imgParts.length ? imgParts.join(" / ") : "";

    // Antiflicker
    var afVal = af.mode || "";
    if (afVal === "0") afVal = "Antiflicker: Off";
    else if (afVal === "1") afVal = "Antiflicker: 50Hz";
    else if (afVal === "2") afVal = "Antiflicker: 60Hz";
    else if (afVal && afVal !== "Disable") afVal = "AF:" + afVal;
    if (ispHdrAf) ispHdrAf.textContent = afVal || "";

    // Mirror/Flip
    var orient = "";
    if (af.mirror && af.flip) orient = "Mirror: " + af.mirror + " Flip: " + af.flip;
    if (ispHdrOrient) ispHdrOrient.textContent = orient;

    // FPS
    var fpsNum = parseFloat(data.fps.num);
    var fpsDiv = parseFloat(data.fps.div);
    var fps = fpsDiv > 0 ? fpsNum / fpsDiv : 0;
    var fpsStatus = fps >= 20 ? "ok" : fps >= 10 ? "warn" : "crit";
    cards.push(statCard("FPS", fps.toFixed(1), "", fpsStatus, "Target frame rate. Below 15 may indicate sensor bottleneck."));

    // Mode
    var mode = data.mode || {};
    var modeStr = mode.running || "?";
    if (mode.custom === "Enable") modeStr += " +Custom";
    if (mode.wdr === "Enable") modeStr += " +WDR";
    cards.push(statCard("Mode", modeStr, "", "info"));

    // Integration time
    var intT = data.exposure.int_time || "0";
    var intMax = data.exposure.int_time_max || "0";
    var intStatus = (parseInt(intMax, 10) > 0 && parseInt(intT, 10) >= parseInt(intMax, 10)) ? "warn" : "ok";
    cards.push(statCard("Integration Time", intT + " / " + intMax, "lines", intStatus,
      "At max = sensor at FPS floor. Normal at night."));

    // Analog gain
    var ag = data.exposure.again || "0";
    var agMax = data.exposure.again_max || "0";
    var agMaxNum = parseInt(agMax, 10);
    var agNum = parseInt(ag, 10);
    var agStatus = "ok";
    if (agMaxNum > 0 && agNum >= agMaxNum) agStatus = "crit";
    else if (agMaxNum > 0 && agNum > agMaxNum * 0.8) agStatus = "warn";
    cards.push(statCard("Analog Gain", ag + " / " + agMax, "\u00d7", agStatus,
      "Sensor amplification. High = noisy image."));

    // Digital gain
    var dg = data.exposure.dgain || "0";
    var dgMax = data.exposure.dgain_max || "0";
    var dgStatus = parseInt(dg, 10) > 0 ? "warn" : "ok";
    cards.push(statCard("Digital Gain", dg + " / " + dgMax, "", dgStatus,
      "Digital amplification. Prefer analog gain."));

    // EV
    cards.push(statCard("EV", data.ev.value || "?", "", "info",
      data.ev.us ? data.ev.us + " \u00b5s exposure" : ""));

    // White balance
    var wb = data.wb || {};
    cards.push(statCard("WB Color Temp", wb.color_temp ? wb.color_temp + "K" : "?", "", "info",
      "Rgain: " + (wb.rgain || "?") + " Bgain: " + (wb.bgain || "?")));

    // Frame source: queue count
    if (fsData && fsData.ch0) {
      var qc = fsData.ch0.queue_count || "?";
      var qcNum = parseInt(qc, 10);
      var qcStatus = qcNum < 2 ? "crit" : qcNum < 3 ? "warn" : "ok";
      cards.push(statCard("DMA Queue", qc, "", qcStatus, "DMA buffer pool size. <2 = no slack."));

      var drop = fsData.ch0.drop || "0";
      var dropStatus = parseInt(drop, 10) > 0 ? "crit" : "ok";
      cards.push(statCard("Dropped Frames", drop, "", dropStatus, "Frames lost between sensor and encoder."));

      var intcAhead = fsData.ch0.intc_ahead || "0";
      var intcStatus = parseInt(intcAhead, 10) > 0 ? "warn" : "ok";
      cards.push(statCard("Interrupt Ahead", intcAhead, "", intcStatus, "Near-misses: close to dropping frames."));
    }

    // Debug counters
    if (data.debug) {
      var dbg = data.debug.ch0 || "";
      var ch0Done = "";
      var ipDone = "";
      if (dbg) {
        var m0 = dbg.match(/ch0 done (\d+)/);
        var m1 = dbg.match(/ip done (\d+)/);
        if (m0) ch0Done = m0[1];
        if (m1) ipDone = m1[1];
      }
      if (ch0Done) {
        cards.push(statCard("Frames Processed", ch0Done, "", "info", "ISP channel 0 frame counter"));
      }
      if (ipDone && ch0Done) {
        var diff = parseInt(ipDone, 10) - parseInt(ch0Done, 10);
        var diffStatus = diff > 5 ? "warn" : "ok";
        cards.push(statCard("IP \u0394 Ch0", diff.toString(), "", diffStatus, "Interrupt completions minus channel done. >5 means frames dropping between sensor and ISP output."));
      }
    }

    statsRow.innerHTML = cards.join("");
  }

  // ── Charts ──────────────────────────────────────────────────────
  function initCharts() {
    var opts = {
      responsive: true,
      maintainAspectRatio: false,
      animation: { duration: 300 },
      scales: {
        x: { display: true, ticks: { maxTicksLimit: 10, font: { size: 9 } } },
        y: { beginAtZero: false, ticks: { font: { size: 9 } } }
      },
      plugins: {
        legend: { labels: { boxWidth: 12, font: { size: 10 } } }
      }
    };

    var ctxFps = $("#chart-fps");
    if (ctxFps) {
      charts.fps = new Chart(ctxFps.getContext("2d"), {
        type: "line",
        data: { labels: [], datasets: [{ label: "FPS", data: [], borderColor: "#0d6efd", backgroundColor: "rgba(13,110,253,0.1)", tension: 0.2, fill: true }] },
        options: Object.assign({}, opts, { scales: Object.assign({}, opts.scales, { y: { beginAtZero: true, ticks: { font: { size: 9 } } } }) })
      });
    }

    var ctxGain = $("#chart-gain");
    if (ctxGain) {
      charts.gain = new Chart(ctxGain.getContext("2d"), {
        type: "line",
        data: {
          labels: [],
          datasets: [
            { label: "Analog Gain", data: [], borderColor: "#fd7e14", tension: 0.2, yAxisID: "y" },
            { label: "Digital Gain", data: [], borderColor: "#6f42c1", tension: 0.2, yAxisID: "y" }
          ]
        },
        options: Object.assign({}, opts)
      });
    }

    var ctxInt = $("#chart-inttime");
    if (ctxInt) {
      charts.inttime = new Chart(ctxInt.getContext("2d"), {
        type: "line",
        data: {
          labels: [],
          datasets: [
            { label: "Integration Time", data: [], borderColor: "#198754", tension: 0.2, yAxisID: "y" },
            { label: "Max Int. Time", data: [], borderColor: "#dc3545", borderDash: [4, 4], tension: 0.2, yAxisID: "y" }
          ]
        },
        options: Object.assign({}, opts)
      });
    }

    var ctxEv = $("#chart-ev");
    if (ctxEv) {
      charts.ev = new Chart(ctxEv.getContext("2d"), {
        type: "line",
        data: { labels: [], datasets: [{ label: "EV Value", data: [], borderColor: "#20c997", tension: 0.2, fill: true, backgroundColor: "rgba(32,201,151,0.1)" }] },
        options: opts
      });
    }
  }

  function truncateHistory() {
    if (history.length > MAX_HISTORY) {
      history = history.slice(-MAX_HISTORY);
    }
  }

  function updateCharts() {
    if (!charts.fps) return;
    var labels = history.map(function(_, i) {
      var d = new Date(history[i].ts * 1000);
      return d.toLocaleTimeString().replace(/:\d{2}$/, "");
    });

    // FPS
    var fpsValues = history.map(function(h) {
      var num = parseFloat(h.data.fps.num);
      var div = parseFloat(h.data.fps.div);
      return div > 0 ? parseFloat((num / div).toFixed(1)) : null;
    });
    charts.fps.data.labels = labels;
    charts.fps.data.datasets[0].data = fpsValues;
    charts.fps.update("none");

    // Gains
    var againVals = history.map(function(h) { return parseInt(h.data.exposure.again, 10) || 0; });
    var dgainVals = history.map(function(h) { return parseInt(h.data.exposure.dgain, 10) || 0; });
    charts.gain.data.labels = labels;
    charts.gain.data.datasets[0].data = againVals;
    charts.gain.data.datasets[1].data = dgainVals;
    charts.gain.update("none");

    // Integration time
    var intVals = history.map(function(h) { return parseInt(h.data.exposure.int_time, 10) || 0; });
    var intMaxVals = history.map(function(h) { return parseInt(h.data.exposure.int_time_max, 10) || 0; });
    charts.inttime.data.labels = labels;
    charts.inttime.data.datasets[0].data = intVals;
    charts.inttime.data.datasets[1].data = intMaxVals;
    charts.inttime.update("none");

    // EV
    var evVals = history.map(function(h) { return parseInt(h.data.ev.value, 10) || 0; });
    charts.ev.data.labels = labels;
    charts.ev.data.datasets[0].data = evVals;
    charts.ev.update("none");
  }

  // ── SSE connection ───────────────────────────────────────────
  var eventSource = null;

  function handleSseEvent(event) {
    var payload;
    try {
      payload = JSON.parse(event.data);
    } catch (e) {
      return;
    }

    errorAlert.classList.add("d-none");

    var data = payload.m0;
    var fsData = payload.fs;

    // The SSE combines both into a unified payload; mirror platform/timestamp
    if (data) {
      data.platform = payload.platform;
      data.timestamp = payload.timestamp;
    }

    lastData = data;
    lastFs = fsData;

    if (!data) {
      errorAlert.textContent = "No ISP data received from SSE";
      errorAlert.classList.remove("d-none");
      pollStatus.textContent = "\u25cf no data";
      pollStatus.className = "text-warning small";
      return;
    }

    renderStats(data, fsData);
    var issues = detectIssues(data, fsData);
    renderIssues(issues);

    if (rawM0) rawM0.textContent = JSON.stringify(data, null, 2);
    if (rawFs) rawFs.textContent = fsData ? JSON.stringify(fsData, null, 2) : "No isp-fs data";

    history.push({ ts: payload.timestamp || Math.floor(Date.now() / 1000), data: data, fs: fsData });
    truncateHistory();
    updateCharts();

    pollStatus.textContent = "\u25cf live";
    pollStatus.className = "text-success small";
  }

  function startSse() {
    stopSse();
    var interval = parseInt(pollIntervalSel.value, 10) || 5000;
    var intervalSec = Math.max(1, Math.round(interval / 1000));
    var url = "/x/isp-sse.cgi?interval=" + intervalSec;

    pollStatus.textContent = "\u25cf connecting...";
    pollStatus.className = "text-info small";

    eventSource = new EventSource(url);
    eventSource.addEventListener("isp", handleSseEvent);

    eventSource.addEventListener("open", function() {
      pollStatus.textContent = "\u25cf live";
      pollStatus.className = "text-success small";
    });

    eventSource.addEventListener("error", function() {
      pollStatus.textContent = "\u25cf reconnecting...";
      pollStatus.className = "text-warning small";
    });
  }

  function stopSse() {
    if (eventSource) {
      eventSource.close();
      eventSource = null;
    }
  }

  // ── LLM Analysis ───────────────────────────────────────────────
  function buildLlmPrompt(data, fsData, issues) {
    var parts = [];

    parts.push("You are an Ingenic ISP hardware expert analyzing live camera sensor data.");
    parts.push("");
    parts.push("## Current ISP Snapshot");
    parts.push("");

    var sn = data.sensor || {};
    parts.push("Sensor: " + (sn.name || "unknown"));
    parts.push("Platform: " + (data.platform || "unknown"));
    parts.push("Resolution: " + (sn.width || "?") + "x" + (sn.height || "?"));

    var fpsNum = parseFloat(data.fps.num);
    var fpsDiv = parseFloat(data.fps.div);
    var fps = fpsDiv > 0 ? (fpsNum / fpsDiv).toFixed(1) : "?";
    parts.push("FPS: " + fps + " (raw: " + data.fps.num + " / " + data.fps.div + ")");

    var mode = data.mode || {};
    parts.push("Mode: " + (mode.running || "?") +
      " | Custom: " + (mode.custom || "?") +
      " | WDR: " + (mode.wdr || "?"));

    var exp = data.exposure || {};
    parts.push("Integration Time: " + (exp.int_time || "?") + " / " + (exp.int_time_max || "?") + " lines");
    parts.push("Analog Gain: " + (exp.again || "?") + " / " + (exp.again_max || "?"));
    parts.push("Digital Gain: " + (exp.dgain || "?") + " / " + (exp.dgain_max || "?"));
    parts.push("Tgain DB: " + (exp.tgain_db || "?"));

    var ev = data.ev || {};
    parts.push("EV: " + (ev.value || "?") + " (" + (ev.us || "?") + " us)");

    var wb = data.wb || {};
    parts.push("White Balance: Rgain=" + (wb.rgain || "?") + " Bgain=" + (wb.bgain || "?") +
      " ColorTemp=" + (wb.color_temp || "?") + "K");

    var img = data.image || {};
    parts.push("Image: Saturation=" + (img.saturation || "?") + " Sharpness=" + (img.sharpness || "?") +
      " Contrast=" + (img.contrast || "?") + " Brightness=" + (img.brightness || "?"));

    var af = data.antiflicker || {};
    parts.push("Antiflicker: " + (af.mode || "?"));
    if (af.mirror) parts.push("Mirror/Flip: " + af.mirror + " / " + af.flip);

    // Frame source
    if (fsData && fsData.ch0) {
      parts.push("");
      parts.push("## Frame Source (DMA buffers)");
      parts.push("Queue count: " + fsData.ch0.queue_count);
      parts.push("Ch0 drops: " + fsData.ch0.drop + "  interrupt-ahead: " + fsData.ch0.intc_ahead);
      if (fsData.ch1) {
        parts.push("Ch1 drops: " + fsData.ch1.drop + "  interrupt-ahead: " + fsData.ch1.intc_ahead);
      }
    }

    // Detected issues
    if (issues && issues.length > 0) {
      parts.push("");
      parts.push("## Auto-detected Issues");
      issues.forEach(function(i) {
        parts.push("- [" + i.severity.toUpperCase() + "] " + i.msg);
      });
    }

    parts.push("");
    parts.push("## Instructions");
    parts.push("1. Analyze the ISP state and identify any problems.");
    parts.push("2. Explain what each abnormal value means in plain terms.");
    parts.push("3. Suggest specific corrective actions (tuning changes, hardware checks, configuration fixes).");
    parts.push("4. If everything looks healthy, say so clearly.");
    parts.push("5. Be concise — this is an embedded camera, not a datacenter.");

    return parts.join("\n");
  }

  function runLlmAnalysis() {
    var apiKey = apiKeyInput.value.trim();
    if (!apiKey) {
      showAlert("warning", "Please enter an API key in the LLM Configuration section.");
      return;
    }
    if (!lastData) {
      showAlert("warning", "No ISP data available. Wait for the first poll to complete.");
      return;
    }

    // Save config
    saveLlmConfig();

    llmStatus.innerHTML = '<div class="alert alert-info"><span class="spinner-border spinner-border-sm me-2"></span>Analyzing with ' + getLlmModel() + '...</div>';
    llmResponse.classList.add("d-none");
    analyzeBtn.disabled = true;

    var issues = detectIssues(lastData, lastFs);
    var prompt = buildLlmPrompt(lastData, lastFs, issues);

    fetch(getLlmEndpoint(), {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": "Bearer " + apiKey
      },
      body: JSON.stringify({
        model: getLlmModel(),
        messages: [
          { role: "system", content: "You are an embedded camera ISP expert. Analyze sensor data and provide concise, actionable advice. Be direct and technical. Focus on practical fixes." },
          { role: "user", content: prompt }
        ],
        temperature: 0.3,
        max_tokens: 2000
      })
    }).then(function(r) {
      if (!r.ok) return r.json().then(function(e) { throw new Error("API error " + r.status + ": " + (e.error && e.error.message ? e.error.message : JSON.stringify(e))); });
      return r.json();
    }).then(function(resp) {
      llmStatus.innerHTML = '<div class="alert alert-success">Analysis complete</div>';
      var text = resp.choices && resp.choices[0] && resp.choices[0].message ?
        resp.choices[0].message.content : JSON.stringify(resp, null, 2);
      llmResponse.textContent = text;
      llmResponse.classList.remove("d-none");
    }).catch(function(e) {
      llmStatus.innerHTML = '<div class="alert alert-danger">Analysis failed: ' + (e.message || e) + '</div>';
    }).finally(function() {
      analyzeBtn.disabled = !apiKeyInput.value.trim();
    });
  }

  // ── Event bindings ─────────────────────────────────────────────
  autoRefreshCb.addEventListener("change", function() {
    if (autoRefreshCb.checked) {
      startSse();
    } else {
      stopSse();
      pollStatus.textContent = "\u25cf paused";
      pollStatus.className = "text-secondary small";
    }
  });

  pollIntervalSel.addEventListener("change", function() {
    saveLlmConfig();
    if (autoRefreshCb.checked) startSse();
  });

  apiKeyToggle.addEventListener("click", function() {
    if (apiKeyInput.type === "password") {
      apiKeyInput.type = "text";
      apiKeyToggle.innerHTML = '<i class="bi bi-eye-slash"></i>';
    } else {
      apiKeyInput.type = "password";
      apiKeyToggle.innerHTML = '<i class="bi bi-eye"></i>';
    }
  });

  providerSel.addEventListener("change", function() {
    updateLlmUi();
    saveLlmConfig();
  });

  modelInput.addEventListener("change", saveLlmConfig);
  endpointInput.addEventListener("change", saveLlmConfig);
  apiKeyInput.addEventListener("input", function() {
    updateLlmUi();
    saveLlmConfig();
  });

  analyzeBtn.addEventListener("click", runLlmAnalysis);

  // ── Tab activation for charts resize ──────────────────────────
  document.querySelectorAll('#ispTabs button[data-bs-toggle="tab"]').forEach(function(btn) {
    btn.addEventListener("shown.bs.tab", function(e) {
      if (e.target.id === "charts-tab") {
        Object.values(charts).forEach(function(c) { if (c && c.resize) c.resize(); });
      }
    });
  });

  // ── Init ───────────────────────────────────────────────────────
  function init() {
    loadLlmConfig();
    updateLlmUi();
    initCharts();
    if (autoRefreshCb.checked) {
      startSse();
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init);
  } else {
    init();
  }
})();
