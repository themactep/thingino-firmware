/* tool-sensor-data.js - day/night tuning graph, two data sources.
 *
 * Background collection OFF (daynight.history_s = 0, the default): the page
 * collects for itself, subscribing to timps' "daynight" SSE stream into a
 * local array. Nothing is recorded on the camera and nothing survives the tab.
 *
 * Background collection ON: the DAEMON keeps the series (a ring in events.c)
 * and the page pages through it with a cursor - ?last=N to backfill, then
 * follow "next". That is the only way the graph can show hours nobody was
 * looking at: the WebUI is plain HTTP on a LAN IP, so navigator.serviceWorker
 * is undefined and a hidden or closed tab collects nothing at all.
 *
 * Which source is live follows the daemon's retain_s, never a local flag, and
 * nothing here POSTs the key except the user flipping the switch. Opening or
 * closing the page changes no state on the camera.
 */
(function () {
  const chartCanvas = $("#dataChart");
  if (!chartCanvas || typeof Chart === "undefined") return;

  const POLL_MS = 10000;        // matches the daemon's sample period
  const POLL_HIDDEN_MS = 60000; // still collecting server-side; just look less
  const RETAIN_S = 14400;       // 4 h, the retention the switch asks for

  function num(v) {
    const n = parseFloat(v);
    return Number.isNaN(n) ? -1 : n;   // -1 is the daemon's "not measurable"
  }

  function fmtDur(s) {
    if (s >= 3600) return `${Math.round(s / 360) / 10} h`;
    return s >= 60 ? `${Math.round(s / 60)} min` : `${s} s`;
  }

  class SensorDataCollector {
    constructor() {
      this.maxPoints = 300;
      this.samples = [];   // {t|wall, gain, exposure, luma, bright, mode}
      this.chart = null;
      this.isPaused = false;
      this.mode = null;    // "live" (local SSE) | "ring" (daemon's buffer)
      this.stream = null;
      this.cursor = null;  // next seq to ask for
      this.head = null;
      this.clock = null;   // {t_now, wall_now} from the newest response
      this.nightThreshold = null;
      this.dayThreshold = null;
      this.timer = null;
      this.retainS = 0;    // the daemon's live daynight.history_s
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
      // one request decides the mode: the response carries retain_s AND, if
      // collection is on, the backfill we would have asked for anyway
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
          pointButtons.forEach((b) => {
            b.classList.remove("btn-primary", "active");
            b.classList.add("btn-secondary");
          });
          e.target.classList.remove("btn-secondary");
          e.target.classList.add("btn-primary", "active");
          const want = parseInt(e.target.dataset.points, 10) || 300;
          const grew = want > this.maxPoints;
          this.maxPoints = want;
          // a bigger window is a backfill request, not just a trim - but only
          // the ring has anything to backfill FROM
          if (grew && this.mode === "ring") this.reload();
          else { this.trimData(); this.render(); }
        });
      });
    }

    initChart() {
      this.chart = new Chart(chartCanvas.getContext("2d"), {
        type: "line",
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
              position: "bottom",
              labels: { boxWidth: 12, font: { size: 10 } },
            },
          },
          scales: {
            x: {
              display: true,
              ticks: { maxTicksLimit: 12, autoSkip: true },
              title: {
                display: true,
                text: "Time",
              },
            },
            y: {
              display: true,
              beginAtZero: true,
              title: {
                display: true,
                text: "Gain / exposure index",
              },
            },
            // luma (0-255) and brightness (0-100 %) are three orders of
            // magnitude below a railed gain and would be a flat line on y
            y2: {
              display: true,
              position: "right",
              beginAtZero: true,
              suggestedMax: 255,
              grid: { drawOnChartArea: false },
              title: {
                display: true,
                text: "Luma / %",
              },
            },
            y1: {
              display: false,
              type: "linear",
              min: 0,
              max: 1,
              position: "right",
            },
          },
        },
      });
    }

    /* ---- data ---------------------------------------------------------- */

    schedule() {
      clearTimeout(this.timer);
      this.timer = setTimeout(() => this.poll(),
                              document.hidden ? POLL_HIDDEN_MS : POLL_MS);
    }

    /* ---- collection on/off --------------------------------------------- */

    // The one place that writes daynight.history_s. Opening or closing this
    // page never does - collection is a deliberate act with a life of its own.
    setCollection(on) {
      if (this.busy || !window.timpsApi) { this.syncBgUi(); return; }
      this.busy = true;
      const want = on ? RETAIN_S : 0;
      window.timpsApi.set({ daynight: { history_s: want } }).then(
        () => {
          this.busy = false;
          this.retainS = want;
          this.syncBgUi();
          if (want) this.reload();     // ingest() hands the graph to the ring
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
        ? `— the camera is recording a ${fmtDur(this.retainS)} window, whether or not this page is open`
        : "— off: this page graphs only what arrives while it is open";
    }

    /* ---- mode: local SSE vs the daemon's ring --------------------------- */

    // A mode change resets the view. The two sources have different cadences
    // and timebases, so splicing them would draw a seam that is not real.
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
    }

    startStream() {
      if (!window.timpsApi) { this.updateStreamStatus(false); return; }
      if (this.stream) return;
      // timps pushes "daynight" over its native SSE /events - the full state on
      // connect, then every meaningful change. "config" rides along so a
      // history_s flipped elsewhere moves this page too.
      this.stream = window.timpsApi.events(
        "daynight,config",
        (type, d) => this.onEvent(type, d),
        () => this.updateStreamStatus(false),
      );
      this.updateStreamStatus(true);
    }

    onEvent(type, d) {
      if (!d) return;
      if (type === "config") {
        if (d.key === "daynight.history_s") {
          this.retainS = Number(d.value) || 0;
          this.syncBgUi();
          // !busy: our own POST echoes back here too, and setCollection is
          // already handing the graph over - a second reload would double it
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

    // full backfill: ask from the newest maxPoints samples and follow "next"
    // until the daemon says we are level with its head.
    reload() {
      this.samples = [];
      this.cursor = null;
      this.fetchPage({ last: this.maxPoints });
    }

    poll() {
      if (this.mode === "live") return;   // a timer that outlived the handover
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

      // the switch tracks the daemon's live retain_s, never a remembered local
      // state - and it is that value, not this page being open, that decides
      // which of the two sources draws the graph
      this.retainS = Number(d.retain_s) || 0;
      this.syncBgUi();
      if (!this.retainS) { this.enterLive(); return; }
      if (this.mode !== "ring") { this.stopStream(); this.mode = "ring"; }
      this.updateStreamStatus(true);   // after the mode: it words the tooltip

      this.clock = { t_now: Number(d.t_now), wall_now: Number(d.wall_now) };
      this.head = Number(d.head);

      // our cursor fell out of the ring's retained window: the series has a
      // hole, so refetch it whole rather than splicing across the gap
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

      // one chart update per response, not per sample - a 600-row backfill
      // would otherwise redraw 600 times
      this.render();

      // still behind the daemon's head: keep paging immediately
      if (this.cursor !== this.head) this.fetchPage({ since: this.cursor });
      else this.schedule();
    }

    trimData() {
      if (this.samples.length > this.maxPoints)
        this.samples.splice(0, this.samples.length - this.maxPoints);
    }

    // samples are stamped with the daemon's MONOTONIC clock; every response
    // carries the (t_now, wall_now) pair to convert against. Deriving labels
    // fresh on each render is what keeps the series intact across the NTP
    // step this camera takes shortly after boot.
    wallOf(s) {
      if (s.wall !== undefined) return new Date(s.wall * 1000);  // live mode
      if (!this.clock) return new Date();
      return new Date((this.clock.wall_now - (this.clock.t_now - s.t)) * 1000);
    }

    // -1 is the daemon's "not measurable"; Chart.js draws a null as a gap
    // rather than a dip to zero
    static val(v) {
      return (typeof v === "number" && v >= 0) ? v : null;
    }

    /* ---- rendering ----------------------------------------------------- */

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
          borderWidth: 2,
          tension: 0.4,
          fill: false,
          pointRadius: 1,
          pointBackgroundColor: metric.color,
          pointBorderColor: metric.color,
          pointBorderWidth: 1,
          yAxisID: metric.axis || "y",
        });
      });

      const n = this.samples.length;
      if (this.nightThreshold !== null && !Number.isNaN(this.nightThreshold)) {
        this.chart.data.datasets.push({
          label: `Night Threshold (${this.nightThreshold})`,
          data: Array(n).fill(this.nightThreshold),
          borderColor: "rgba(255, 0, 0, 0.7)",
          borderWidth: 1,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
        });
      }
      if (this.dayThreshold !== null && !Number.isNaN(this.dayThreshold)) {
        this.chart.data.datasets.push({
          label: `Day Threshold (${this.dayThreshold})`,
          data: Array(n).fill(this.dayThreshold),
          borderColor: "rgba(0, 255, 0, 0.7)",
          borderWidth: 1,
          borderDash: [5, 5],
          fill: false,
          pointRadius: 0,
        });
      }
      if (n) {
        this.chart.data.datasets.push({
          label: "Mode (0=Day, 1=Night)",
          data: this.samples.map((s) => (s.mode >= 0 ? s.mode : null)),
          borderColor: "rgba(128, 128, 128, 0.5)",
          backgroundColor: "rgba(128, 128, 128, 0.1)",
          borderWidth: 1,
          tension: 0,
          fill: false,
          pointRadius: 0,
          yAxisID: "y1",
        });
      }

      this.chart.update("none");
      this.updateStatsDisplay();
    }

    // recomputed over the whole loaded window rather than accumulated: a
    // backfill arrives as a batch, and a trimmed-away sample must stop
    // counting towards min/max/avg
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
        div.className = `stat-card ${metric.key}`;
        div.innerHTML = `
          <div class="stat-label">${metric.label}</div>
          <div class="stat-value">${stat.latest.toFixed(1)}</div>
          <div class="stat-detail">Min: ${stat.min.toFixed(1)} | Max: ${stat.max.toFixed(1)} | Avg: ${stat.avg.toFixed(1)}</div>
        `;
        container.appendChild(div);
      });
    }

    /* ---- controls ------------------------------------------------------ */

    async clearData() {
      const confirmed = await confirm("Clear all data?");
      if (!confirmed) return;
      // only the local view: the daemon's ring keeps its series
      this.samples = [];
      this.render();
    }

    togglePause(e) {
      this.isPaused = !this.isPaused;
      if (e && e.target) {
        e.target.textContent = this.isPaused ? "Resume" : "Pause";
        e.target.classList.toggle("btn-warning", this.isPaused);
        e.target.classList.toggle("btn-secondary", !this.isPaused);
      }
      // resuming backfills the paused stretch out of the ring; in live mode
      // that stretch simply never existed
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

    /* ---- export -------------------------------------------------------- */

    exportJSON() {
      const payload = {
        exported_at: new Date().toISOString(),
        stats: this.stats(),
        samples: this.samples.map((s) => ({
          time: this.wallOf(s).toISOString(),
          exposure: s.exposure, total_gain: s.gain,
          ae_luma: s.luma, brightness: s.bright, mode: s.mode,
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
        return `"${this.wallOf(s).toISOString()}",${values}`;
      });
      const csv = `Time,${headers}\n${rows.join("\n")}`;
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
