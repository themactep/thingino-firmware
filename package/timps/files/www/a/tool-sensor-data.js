(function () {
  const chartCanvas = $("#dataChart");
  if (!chartCanvas || typeof Chart === "undefined") return;

  const POLL_MS = 10000;
  const POLL_HIDDEN_MS = 60000;
  const RETAIN_S = 14400;

  function num(v) {
    const n = parseFloat(v);
    return Number.isNaN(n) ? -1 : n;
  }

  function fmtDur(s) {
    if (s >= 3600) return `${Math.round(s / 360) / 10} h`;
    return s >= 60 ? `${Math.round(s / 60)} min` : `${s} s`;
  }

  class SensorDataCollector {
    constructor() {
      this.maxPoints = 300;
      this.samples = [];
      this.chart = null;
      this.isPaused = false;
      this.mode = null;
      this.stream = null;
      this.cursor = null;
      this.head = null;
      this.clock = null;
      this.nightThreshold = null;
      this.dayThreshold = null;
      this.timer = null;
      this.retainS = 0;
      this.busy = false;

      this.metrics = [
        { key: "exposure", label: "Exposure Index", color: "#FF6384" },
        { key: "gain", label: "Total Gain", color: "#36A2EB" },
        { key: "luma", label: "AE Luma", color: "#FFCE56", axis: "y2" },
        { key: "bright", label: "Brightness %", color: "#B8FF4D", axis: "y2" },
      ];

      this.init();
    }

    init() {
      this.setupEventListeners();
      this.initChart();
      this.reload();
      document.addEventListener("visibilitychange", () => {
        if (this.mode === "ring") this.schedule();
      });
    }

    setupEventListeners() {
      const clearBtn = $("#clear-data");
      const pauseBtn = $("#toggle-pause");
      const exportJsonBtn = $("#export-json");
      const exportCsvBtn = $("#export-csv");
      const pointButtons = $$("#max-points button");

      if (clearBtn) {
        clearBtn.addEventListener("click", () => this.clearData());
      }
      if (pauseBtn) {
        pauseBtn.addEventListener("click", (e) => this.togglePause(e));
      }
      if (exportJsonBtn) {
        exportJsonBtn.addEventListener("click", () => this.exportJSON());
      }
      if (exportCsvBtn) {
        exportCsvBtn.addEventListener("click", () => this.exportCSV());
      }
      const bgBox = $("#bg-collect");
      if (bgBox) {
        bgBox.addEventListener("change", (e) => this.setCollection(e.target.checked));
      }
      pointButtons.forEach((btn) => {
        btn.addEventListener("click", (e) => {
          pointButtons.forEach((b) => b.classList.toggle("active", b === e.target));
          const want = parseInt(e.target.dataset.points, 10) || 300;
          const grew = want > this.maxPoints;
          this.maxPoints = want;
          if (grew && this.mode === "ring") this.reload();
          else { this.trimData(); this.render(); }
        });
      });
    }

    initChart() {
      const shade = {
        id: "nightShade",
        beforeDatasetsDraw: (c) => {
          const { ctx, chartArea: a, scales: { x } } = c;
          const n = this.samples.length;
          if (!a || n < 2) return;
          ctx.save();
          ctx.fillStyle = "rgba(58,95,205,.13)";
          this.samples.forEach((smp, i) => {
            if (smp.mode !== 1) return;
            const x0 = x.getPixelForValue(i), x1 = x.getPixelForValue(Math.min(i + 1, n - 1));
            ctx.fillRect(x0, a.top, Math.max(1, x1 - x0 + 1), a.bottom - a.top);
          });
          ctx.restore();
        },
      };
      this.chart = new Chart(chartCanvas.getContext("2d"), {
        type: "line",
        plugins: [shade],
        data: {
          labels: [],
          datasets: [],
        },
        options: {
          responsive: true,
          maintainAspectRatio: false,
          animation: false,
          interaction: {
            mode: "index",
            intersect: false,
          },
          plugins: {
            legend: {
              display: true,
              position: "top",
              labels: { boxWidth: 10, boxHeight: 10, font: { size: 11 } },
            },
          },
          scales: {
            x: {
              display: true,
              ticks: { maxTicksLimit: 8, autoSkip: true },
            },
            y: {
              display: true,
              beginAtZero: true,
              title: {
                display: true,
                text: "gain",
              },
            },
            y2: {
              display: true,
              position: "right",
              beginAtZero: true,
              suggestedMax: 255,
              grid: { drawOnChartArea: false },
              title: {
                display: true,
                text: "luma / %",
              },
            },
          },
        },
      });
    }

    schedule() {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.poll(),
                              document.hidden ? POLL_HIDDEN_MS : POLL_MS);
    }

    setCollection(on) {
      if (this.busy || !window.timpsApi) { this.syncBgUi(); return; }
      this.busy = true;
      const want = on ? RETAIN_S : 0;
      window.timpsApi.set({ daynight: { history_s: want } }).then(
        () => {
          this.busy = false;
          this.retainS = want;
          this.syncBgUi();
          if (want) this.reload();
          else this.enterLive();
        },
        () => { this.busy = false; this.syncBgUi(); },
      );
    }

    syncBgUi() {
      const box = $("#bg-collect");
      if (box) box.checked = this.retainS > 0;
      const note = $("#bg-collect-note");
      if (!note) return;
      note.textContent = this.retainS
        ? `The camera keeps a ${fmtDur(this.retainS)} history, a sample every 10 s, page open or not.`
        : "Live while this page is open: timps sends changes, steady values are repeated every 2 s.";
    }

    enterLive() {
      if (this.mode === "live") return;
      this.mode = "live";
      clearTimeout(this.timer);
      this.timer = null;
      this.cursor = null;
      this.clock = null;
      this.samples = [];
      this.render();
      this.startStream();
    }

    stopStream() {
      if (this.stream) { this.stream.close(); this.stream = null; }
      clearInterval(this.carryTimer);
      this.carryTimer = null;
    }

    startCarry() {
      clearInterval(this.carryTimer);
      const every = this.intervalMs || 2000;
      this.carryTimer = setInterval(() => {
        const last = this.samples[this.samples.length - 1];
        if (this.mode !== "live" || this.isPaused || !last) return;
        const now = Date.now() / 1000;
        if (now - last.wall < every / 1000 * 0.9) return;
        this.samples.push(Object.assign({}, last, { wall: now, carried: true }));
        this.trimData();
        this.render();
      }, every);
    }

    startStream() {
      if (!window.timpsApi) { this.updateStreamStatus(false); return; }
      if (this.stream) return;
      this.stream = window.timpsApi.events(
        "daynight,config",
        (type, d) => this.onEvent(type, d),
        () => this.updateStreamStatus(false),
      );
      this.updateStreamStatus(true);
      window.timpsApi.get().then((j) => {
        this.intervalMs = Number(j.daynight && j.daynight.interval_ms) || 2000;
        this.updatePointHints();
        if (this.mode === "live") this.startCarry();
      }, () => { if (this.mode === "live") this.startCarry(); });
    }

    updatePointHints() {
      const step = this.mode === "ring" ? 10 : (this.intervalMs || 2000) / 1000;
      document.querySelectorAll("#max-points [data-points]").forEach((b) => {
        const s = b.dataset.points * step;
        b.textContent = s >= 3600 ? +(s / 3600).toFixed(1) + " h" : Math.round(s / 60) + " min";
        b.title = "Last " + b.dataset.points + " samples";
      });
    }

    onEvent(type, d) {
      if (!d) return;
      if (type === "config") {
        if (d.key === "daynight.history_s") {
          this.retainS = Number(d.value) || 0;
          this.syncBgUi();
          if (this.retainS && this.mode === "live" && !this.busy) this.reload();
        }
        return;
      }
      if (this.mode !== "live") return;
      this.updateStreamStatus(true);
      if (isFinite(Number(d.night_gain))) this.nightThreshold = Number(d.night_gain);
      if (isFinite(Number(d.day_gain))) this.dayThreshold = Number(d.day_gain);
      if (this.isPaused) return;
      this.samples.push({
        wall: Date.now() / 1000,
        gain: num(d.total_gain), exposure: num(d.exposure),
        luma: num(d.ae_luma), bright: num(d.brightness),
        mode: Number(d.mode) === 1 ? 1 : 0,
      });
      this.trimData();
      this.render();
    }

    reload() {
      this.samples = [];
      this.cursor = null;
      this.fetchPage({ last: this.maxPoints });
    }

    poll() {
      if (this.mode === "live") return;
      if (this.cursor === null) this.reload();
      else this.fetchPage({ since: this.cursor });
    }

    fetchPage(opts) {
      if (!window.timpsApi || !window.timpsApi.dnHistory) {
        console.error("timps-api.js too old: no dnHistory()");
        this.updateStreamStatus(false);
        return;
      }
      window.timpsApi.dnHistory(opts).then(
        (d) => this.ingest(d),
        () => { this.updateStreamStatus(false); this.schedule(); },
      );
    }

    ingest(d) {
      if (isFinite(Number(d.night_gain))) this.nightThreshold = Number(d.night_gain);
      if (isFinite(Number(d.day_gain))) this.dayThreshold = Number(d.day_gain);

      this.retainS = Number(d.retain_s) || 0;
      this.syncBgUi();
      if (!this.retainS) { this.enterLive(); return; }
      if (this.mode !== "ring") { this.stopStream(); this.mode = "ring"; this.updatePointHints(); }
      this.updateStreamStatus(true);

      this.clock = { t_now: Number(d.t_now), wall_now: Number(d.wall_now) };
      this.head = Number(d.head);

      if (d.lapped && this.samples.length) { this.reload(); return; }

      if (!this.isPaused) {
        (d.samples || []).forEach((r) => {
          this.samples.push({
            t: r[0], gain: r[1], exposure: r[2],
            luma: r[3], bright: r[4], mode: r[5],
          });
        });
        this.trimData();
      }
      this.cursor = Number(d.next);

      this.render();

      if (this.cursor !== this.head) this.fetchPage({ since: this.cursor });
      else this.schedule();
    }

    trimData() {
      if (this.samples.length > this.maxPoints)
        this.samples.splice(0, this.samples.length - this.maxPoints);
    }

    wallOf(s) {
      if (s.wall !== undefined) return new Date(s.wall * 1000);
      if (!this.clock) return new Date();
      return new Date((this.clock.wall_now - (this.clock.t_now - s.t)) * 1000);
    }

    static val(v) {
      return (typeof v === "number" && v >= 0) ? v : null;
    }

    render() {
      const S = SensorDataCollector;
      this.chart.data.labels = this.samples.map((s) =>
        this.wallOf(s).toLocaleTimeString());
      this.chart.data.datasets = [];

      this.metrics.forEach((metric) => {
        this.chart.data.datasets.push({
          label: metric.label,
          data: this.samples.map((s) => S.val(s[metric.key])),
          borderColor: metric.color,
          backgroundColor: `${metric.color}20`,
          borderWidth: 1.6,
          tension: 0.3,
          fill: false,
          pointRadius: 0,
          yAxisID: metric.axis || "y",
        });
      });

      const n = this.samples.length;
      if (this.nightThreshold !== null && !Number.isNaN(this.nightThreshold)) {
        this.chart.data.datasets.push({
          label: `night > ${this.nightThreshold}`,
          data: Array(n).fill(this.nightThreshold),
          borderColor: "rgba(123, 156, 255, 0.8)",
          borderWidth: 1,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
        });
      }
      if (this.dayThreshold !== null && !Number.isNaN(this.dayThreshold)) {
        this.chart.data.datasets.push({
          label: `day < ${this.dayThreshold}`,
          data: Array(n).fill(this.dayThreshold),
          borderColor: "rgba(240, 192, 64, 0.8)",
          borderWidth: 1,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
        });
      }
      this.chart.update("none");
      this.updateStatsDisplay();
    }

    stats() {
      const S = SensorDataCollector;
      const out = {};
      this.metrics.forEach((metric) => {
        let min = null, max = null, sum = 0, count = 0, latest = null;
        this.samples.forEach((s) => {
          const v = S.val(s[metric.key]);
          if (v === null) return;
          if (min === null || v < min) min = v;
          if (max === null || v > max) max = v;
          sum += v; count += 1; latest = v;
        });
        if (count) out[metric.key] = { latest, min, max, avg: sum / count, count };
      });
      return out;
    }

    updateStatsDisplay() {
      const container = $("#data-stats");
      if (!container) return;
      const stats = this.stats();
      container.innerHTML = "";

      this.metrics.forEach((metric) => {
        const stat = stats[metric.key];
        if (!stat) return;
        const div = document.createElement("div");
        div.className = "col-6";
        div.innerHTML = `<div class="mt-tile"><div class="l"><i style="background:${metric.color}"></i>${metric.label}</div>
          <div class="v">${Math.round(stat.latest)}</div>
          <div class="r" title="avg ${stat.avg.toFixed(1)}">min ${Math.round(stat.min)} · max ${Math.round(stat.max)}</div></div>`;
        container.appendChild(div);
      });
    }

    async clearData() {
      const confirmed = await confirm("Clear all data?");
      if (!confirmed) return;
      this.samples = [];
      this.render();
    }

    togglePause(e) {
      this.isPaused = !this.isPaused;
      if (e && e.target) {
        e.target.textContent = this.isPaused ? "Resume" : "Pause";
        e.target.classList.toggle("active", this.isPaused);
      }
      if (!this.isPaused && this.mode === "ring") this.reload();
    }

    updateStreamStatus(connected) {
      const statusIcon = $("#stream-status");
      if (!statusIcon) return;
      if (connected) {
        statusIcon.classList.remove("disconnected");
        statusIcon.classList.add("connected");
        statusIcon.title = this.mode === "ring"
          ? "Connected - reading the camera's recorded history"
          : "Connected - collecting live into this page";
      } else {
        statusIcon.classList.remove("connected");
        statusIcon.classList.add("disconnected");
        statusIcon.title = "Disconnected - retrying...";
      }
    }

    exportJSON() {
      const payload = {
        exported_at: new Date().toISOString(),
        stats: this.stats(),
        samples: this.samples.map((s) => ({
          time: this.wallOf(s).toISOString(),
          exposure: s.exposure, total_gain: s.gain,
          ae_luma: s.luma, brightness: s.bright, mode: s.mode,
          carried: !!s.carried,
        })),
      };
      this.downloadFile(
        JSON.stringify(payload, null, 2),
        "sensor-data.json",
        "application/json",
      );
    }

    exportCSV() {
      const headers = this.metrics.map((m) => m.label).join(",");
      const rows = this.samples.map((s) => {
        const values = this.metrics
          .map((m) => {
            const v = SensorDataCollector.val(s[m.key]);
            return v === null ? "" : v.toFixed(2);
          })
          .join(",");
        return `"${this.wallOf(s).toISOString()}",${values},${s.carried ? 1 : 0}`;
      });
      const csv = `Time,${headers},Carried\n${rows.join("\n")}`;
      this.downloadFile(csv, "sensor-data.csv", "text/csv");
    }

    downloadFile(content, filename, type) {
      const blob = new Blob([content], { type });
      const url = URL.createObjectURL(blob);
      const a = document.createElement("a");
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();
      document.body.removeChild(a);
      URL.revokeObjectURL(url);
    }
  }

  new SensorDataCollector();
})();
