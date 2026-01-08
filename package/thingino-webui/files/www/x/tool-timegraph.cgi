#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Time Series Graph"
pagename="timegraph"
%>
<%in _header.cgi %>

<style>
#chart-container {
	position: relative;
	height: 400px;
	margin-bottom: 2rem;
}

.graph-controls {
	display: flex;
	gap: 1rem;
	flex-wrap: wrap;
	margin-bottom: 1rem;
	align-items: center;
}

.graph-controls select,
.graph-controls input[type="number"],
.graph-controls input[type="checkbox"] {
	padding: 0.5rem;
	border: 1px solid #ccc;
	border-radius: 0.25rem;
}

.graph-controls label {
	display: flex;
	align-items: center;
	gap: 0.5rem;
	margin-bottom: 0;
}

.data-stats {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
	gap: 1rem;
	margin-top: 1rem;
}

.stat-item {
	padding: 1rem;
	border: 1px solid #e0e0e0;
	border-radius: 0.25rem;
	background-color: var(--bs-body-bg);
}

.stat-label {
	font-size: 0.875rem;
	color: #666;
	margin-bottom: 0.5rem;
}

.stat-value {
	font-size: 1.5rem;
	font-weight: bold;
	color: var(--bs-body-color);
}

.stream-status {
	padding: 0.5rem 1rem;
	border-radius: 0.25rem;
	font-size: 0.875rem;
	margin-bottom: 1rem;
}

.stream-status.connected {
	background-color: #d4edda;
	color: #155724;
	border: 1px solid #c3e6cb;
}

.stream-status.disconnected {
	background-color: #f8d7da;
	color: #721c24;
	border: 1px solid #f5c6cb;
}

.metric-list {
	display: grid;
	grid-template-columns: repeat(auto-fill, minmax(150px, 1fr));
	gap: 0.5rem;
	margin-top: 1rem;
}

.metric-checkbox {
	padding: 0.75rem;
	border: 1px solid #ccc;
	border-radius: 0.25rem;
	background-color: var(--bs-body-bg);
	display: flex;
	align-items: center;
	gap: 0.5rem;
	cursor: pointer;
}

.metric-checkbox input[type="checkbox"] {
	margin: 0;
}
</style>

<div class="row">
	<div class="col-12">
		<h2>Real-Time Sensor Data Graph</h2>

		<div id="stream-status" class="stream-status disconnected">
			<span class="status-indicator">●</span> Connecting...
		</div>

		<div class="graph-controls">
			<label for="max-points">
				Max Points:
				<input type="number" id="max-points" min="10" max="3600" value="300" style="width: 80px;">
			</label>
			<label for="auto-scroll">
				<input type="checkbox" id="auto-scroll" checked>
				Auto Scroll
			</label>
			<button class="btn btn-sm btn-secondary" id="clear-data">Clear Data</button>
			<button class="btn btn-sm btn-info" id="toggle-pause">Pause</button>
			<button class="btn btn-sm btn-success" id="export-json">Export JSON</button>
			<button class="btn btn-sm btn-success" id="export-csv">Export CSV</button>
		</div>

		<h5>Metrics to Display</h5>
		<div class="metric-list" id="metric-list">
			<!-- Will be populated by JavaScript -->
		</div>

		<h5>EV Calibration</h5>
		<div class="graph-controls">
			<label for="ev-range-mode">
				<input type="radio" id="ev-platform-range" name="ev-range-mode" value="platform">
				Platform Defaults (EVmin: <span id="platform-ev-min">0</span>, EVmax: <span id="platform-ev-max">60000</span>)
			</label>
			<label for="ev-observed-range">
				<input type="radio" id="ev-observed-range" name="ev-range-mode" value="observed" checked>
				Observed Range (EVmin: <span id="observed-ev-min">-</span>, EVmax: <span id="observed-ev-max">-</span>)
			</label>
		</div>

		<div id="chart-container">
			<canvas id="dataChart"></canvas>
		</div>

		<div class="data-stats" id="data-stats">
			<!-- Will be populated by JavaScript -->
		</div>
	</div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
class TimeSeriesGraph {
	constructor() {
		this.sseUrl = '/x/json-timegraph-stream.cgi';
		this.configUrl = '/x/json-timegraph-config.cgi';
		this.maxPoints = 300;
		this.data = {};
		this.rawData = {};  // Store raw EV values for display in stats
		this.chart = null;
		this.eventSource = null;
		this.isPaused = false;
		this.enabledMetrics = new Set();
		this.stats = {};

		// Platform-specific EV calibration (will be loaded from backend)
		this.platformEVmin = 0;
		this.platformEVmax = 60000;

		// Day/Night mode switching thresholds (as percentages)
		this.dayThresholdPercent = 20;    // Lower threshold - switch to day mode below this
		this.nightThresholdPercent = 85;  // Upper threshold - switch to night mode above this

		// Actual observed EV range (calibrated from real data)
		this.observedEVmin = Infinity;
		this.observedEVmax = -Infinity;
		this.useObservedRange = true;  // Default to observed range for accurate calibration

		// Photosensing metrics only - focus on daynight algorithm analysis
		this.availableMetrics = [
			{ key: 'ev', label: 'Exposure Value (EV %)', color: '#FFB84D' },
			{ key: 'gb_gain', label: 'GB Gain (Blue/Green)', color: '#00D4FF' },
			{ key: 'gr_gain', label: 'GR Gain (Red/Green)', color: '#FF1744' },
			{ key: 'daynight_brightness', label: 'Daynight Brightness (%)', color: '#C9CBCF' }
		];

		this.init();
	}

	init() {
		this.setupEventListeners();
		this.loadPlatformConfig();
		this.setupMetricCheckboxes();
		this.initChart();
		this.startStream();
	}

	loadPlatformConfig() {
		fetch(this.configUrl)
			.then(response => response.json())
			.then(data => {
				if (data.platform) {
					this.platformEVmin = data.platform.ev_min || 0;
					this.platformEVmax = data.platform.ev_max || 60000;
					document.getElementById('platform-ev-min').textContent = this.platformEVmin;
					document.getElementById('platform-ev-max').textContent = this.platformEVmax;
					console.log(`Platform EV range: ${this.platformEVmin} - ${this.platformEVmax}`);
				}
				if (data.daynight) {
					this.dayThresholdPercent = data.daynight.day_percent || 20;
					this.nightThresholdPercent = data.daynight.night_percent || 85;
					console.log(`Day/Night thresholds: ${this.dayThresholdPercent}% (day) / ${this.nightThresholdPercent}% (night)`);
					this.updateChart(); // Redraw chart with new threshold lines
				}
			})
			.catch(error => console.warn('Failed to load platform config:', error));
	}

	updateObservedRangeDisplay() {
		const minEl = document.getElementById('observed-ev-min');
		const maxEl = document.getElementById('observed-ev-max');

		if (isFinite(this.observedEVmin) && isFinite(this.observedEVmax)) {
			minEl.textContent = Math.round(this.observedEVmin);
			maxEl.textContent = Math.round(this.observedEVmax);
		}
	}

	evToPercent(ev) {
		// EV is INVERTED: Higher EV = darker, Lower EV = brighter
		// Use observed range if we have enough data, otherwise use platform defaults
		const min = this.useObservedRange && isFinite(this.observedEVmin) ? this.observedEVmin : this.platformEVmin;
		const max = this.useObservedRange && isFinite(this.observedEVmax) ? this.observedEVmax : this.platformEVmax;

		const range = max - min;
		if (range <= 0) return 0;
		// Inverted: higher EV = lower percentage (darker)
		const pct = ((ev - min) * 100) / range;
		return Math.max(0, Math.min(100, Math.round(pct)));
	}

	percentToEv(pct) {
		// EV is INVERTED: Higher EV = darker, Lower EV = brighter
		pct = Math.max(0, Math.min(100, pct));
		const min = this.useObservedRange && isFinite(this.observedEVmin) ? this.observedEVmin : this.platformEVmin;
		const max = this.useObservedRange && isFinite(this.observedEVmax) ? this.observedEVmax : this.platformEVmax;

		const range = max - min;
		// Inverted: convert percentage back to EV
		return min + (range * pct) / 100;
	}

	updateEVRange(ev) {
		// Track actual observed EV range from incoming data
		if (ev > 0) {
			if (ev < this.observedEVmin) this.observedEVmin = ev;
			if (ev > this.observedEVmax) this.observedEVmax = ev;
		}
	}

	setupEventListeners() {
		document.getElementById('clear-data').addEventListener('click', () => this.clearData());
		document.getElementById('toggle-pause').addEventListener('click', (e) => this.togglePause(e));
		document.getElementById('export-json').addEventListener('click', () => this.exportJSON());
		document.getElementById('export-csv').addEventListener('click', () => this.exportCSV());
		document.getElementById('max-points').addEventListener('change', (e) => {
			this.maxPoints = parseInt(e.target.value);
			this.trimData();
		});

		// EV range calibration toggle
		document.querySelectorAll('input[name="ev-range-mode"]').forEach(radio => {
			radio.addEventListener('change', (e) => {
				this.useObservedRange = (e.target.value === 'observed');
				this.updateChart();
				this.updateStatsDisplay();
			});
		});
	}

	setupMetricCheckboxes() {
		const container = document.getElementById('metric-list');
		this.availableMetrics.forEach((metric, idx) => {
			const label = document.createElement('label');
			label.className = 'metric-checkbox';

			const checkbox = document.createElement('input');
			checkbox.type = 'checkbox';
			checkbox.value = metric.key;
			checkbox.id = `metric-${metric.key}`;

			// Enable sensor metrics (EV, GB Gain, GR Gain) by default for daynight analysis
			const sensorMetrics = ['ev', 'gb_gain', 'daynight_brightness'];
			if (sensorMetrics.includes(metric.key)) {
				checkbox.checked = true;
				this.enabledMetrics.add(metric.key);
				this.data[metric.key] = [];
			}

			checkbox.addEventListener('change', (e) => {
				if (e.target.checked) {
					this.enabledMetrics.add(metric.key);
					if (!this.data[metric.key]) {
						this.data[metric.key] = [];
					}
				} else {
					this.enabledMetrics.delete(metric.key);
				}
				this.updateChart();
			});

			const textSpan = document.createElement('span');
			textSpan.textContent = metric.label;

			label.appendChild(checkbox);
			label.appendChild(textSpan);
			container.appendChild(label);
		});
	}

	initChart() {
		const ctx = document.getElementById('dataChart').getContext('2d');
		this.chart = new Chart(ctx, {
			type: 'line',
			data: {
				labels: [],
				datasets: []
			},
			options: {
				responsive: true,
				maintainAspectRatio: false,
				interaction: {
					mode: 'index',
					intersect: false
				},
				plugins: {
					legend: {
						display: true,
						position: 'top'
					},
					title: {
						display: false
					}
				},
				scales: {
					x: {
						display: true,
						title: {
							display: true,
							text: 'Time'
						}
					},
					y: {
						display: true,
						title: {
							display: true,
							text: 'Value (%)'
						},
						min: 0,
						max: 100
					}
				}
			}
		});
	}

	startStream() {
		if (this.eventSource) return;

		this.eventSource = new EventSource(this.sseUrl);
		this.eventSource.onmessage = (event) => {
			if (this.isPaused) return;

			try {
				const json = JSON.parse(event.data);
				this.addDataPoint(json);
			} catch (error) {
				console.error('Failed to parse SSE data:', error);
			}
		};

		this.eventSource.onerror = (error) => {
			console.error('SSE connection error:', error);
			this.updateStreamStatus(false);
			this.eventSource.close();
			this.eventSource = null;

			// Reconnect after 5 seconds
			setTimeout(() => this.startStream(), 5000);
		};

		this.updateStreamStatus(true);
	}

	addDataPoint(jsonData) {
		const timestamp = new Date(parseInt(jsonData.time_now) * 1000);
		const timeStr = timestamp.toLocaleTimeString();

		// Track observed EV range for calibration
		if ('ev' in jsonData) {
			const ev = parseFloat(jsonData.ev);
			if (!isNaN(ev)) {
				this.updateEVRange(ev);
				this.updateObservedRangeDisplay();
			}
		}

		// Initialize time axis if needed
		if (!this.chart.data.labels.includes(timeStr)) {
			this.chart.data.labels.push(timeStr);
		}

		// Add data for enabled metrics
		this.enabledMetrics.forEach(metricKey => {
			if (!(metricKey in jsonData)) return;

			if (!this.data[metricKey]) {
				this.data[metricKey] = [];
			}

			let value = parseFloat(jsonData[metricKey]);
			if (!isNaN(value)) {
				// Store raw EV value separately for stats display
				if (metricKey === 'ev') {
					if (!this.rawData.ev) {
						this.rawData.ev = [];
					}
					this.rawData.ev.push(value);
					// Convert EV to percentage (0-100%) for consistent scaling with thresholds
					value = this.evToPercent(value);
				}
				this.data[metricKey].push(value);
				this.updateStats(metricKey, value);
			}
		});

		this.trimData();
		this.updateChart();
	}

	updateStats(metricKey, value) {
		if (!this.stats[metricKey]) {
			this.stats[metricKey] = {
				latest: value,
				min: value,
				max: value,
				avg: value,
				count: 1,
				sum: value,
				rawLatest: null,  // For EV: store raw value
				rawMin: null,
				rawMax: null,
				rawAvg: null,
				rawCount: 0,
				rawSum: 0
			};
		} else {
			const stat = this.stats[metricKey];
			stat.latest = value;
			stat.min = Math.min(stat.min, value);
			stat.max = Math.max(stat.max, value);
			stat.count++;
			stat.sum += value;
			stat.avg = stat.sum / stat.count;
		}

		// Update raw EV stats if we have raw data
		if (metricKey === 'ev' && this.rawData.ev && this.rawData.ev.length > 0) {
			const rawValue = this.rawData.ev[this.rawData.ev.length - 1];
			const stat = this.stats[metricKey];
			stat.rawLatest = rawValue;
			if (stat.rawMin === null) {
				stat.rawMin = rawValue;
				stat.rawMax = rawValue;
				stat.rawSum = rawValue;
				stat.rawCount = 1;
			} else {
				stat.rawMin = Math.min(stat.rawMin, rawValue);
				stat.rawMax = Math.max(stat.rawMax, rawValue);
				stat.rawCount++;
				stat.rawSum += rawValue;
			}
			stat.rawAvg = stat.rawSum / stat.rawCount;
		}

		this.updateStatsDisplay();
	}

	updateStatsDisplay() {
		const container = document.getElementById('data-stats');
		container.innerHTML = '';

		// Only show photosensing metrics
		const photosensoringMetrics = ['ev', 'gb_gain', 'gr_gain', 'daynight_brightness'];

		for (const [metricKey, stat] of Object.entries(this.stats)) {
			// Skip non-photosensing metrics
			if (!photosensoringMetrics.includes(metricKey)) continue;

			const metric = this.availableMetrics.find(m => m.key === metricKey);
			if (!metric) continue;

			const div = document.createElement('div');
			div.className = 'stat-item';

			let html = `
				<div class="stat-label">${metric.label}</div>
				<div style="font-size: 0.875rem; color: #999;">
					Current: <span class="stat-value" style="font-size: 1.125rem;">${stat.latest.toFixed(2)}</span>`;

			// For EV metric, also show raw values
			if (metricKey === 'ev' && stat.rawLatest !== null) {
				html += ` (raw: ${stat.rawLatest.toFixed(0)})`;
			}

			html += `</div>
				<div style="font-size: 0.875rem; margin-top: 0.5rem; color: #999;">
					Min: ${stat.min.toFixed(2)} | Max: ${stat.max.toFixed(2)} | Avg: ${stat.avg.toFixed(2)}`;

			// For EV metric, also show raw stats
			if (metricKey === 'ev' && stat.rawLatest !== null) {
				html += `<br/><strong>Raw EV:</strong> Min: ${stat.rawMin.toFixed(0)} | Max: ${stat.rawMax.toFixed(0)} | Avg: ${stat.rawAvg.toFixed(0)}`;
			}

			html += `</div>`;

			div.innerHTML = html;
			container.appendChild(div);
		}
	}

	trimData() {
		const maxLabels = this.maxPoints;

		// Trim labels
		if (this.chart.data.labels.length > maxLabels) {
			const excess = this.chart.data.labels.length - maxLabels;
			this.chart.data.labels.splice(0, excess);
		}

		// Trim data points
		for (const metricKey in this.data) {
			if (this.data[metricKey].length > maxLabels) {
				const excess = this.data[metricKey].length - maxLabels;
				this.data[metricKey].splice(0, excess);
			}
		}
	}

	updateChart() {
		// Clear existing datasets
		this.chart.data.datasets = [];

		// Add new datasets for enabled metrics
		this.enabledMetrics.forEach(metricKey => {
			const metric = this.availableMetrics.find(m => m.key === metricKey);
			if (!metric) return;

			// Add main metric line
			this.chart.data.datasets.push({
				label: metric.label,
				data: this.data[metricKey] || [],
				borderColor: metric.color,
				backgroundColor: metric.color + '20',
				borderWidth: 2,
				tension: 0.4,
				fill: false,
				pointRadius: 3,
				pointBackgroundColor: metric.color,
				pointBorderColor: '#fff',
				pointBorderWidth: 2
			});

			// Add average value line (dashed, lighter)
			const avgValue = this.stats[metricKey]?.avg || 0;
			const avgData = this.chart.data.labels.map(() => avgValue);
			this.chart.data.datasets.push({
				label: `${metric.label} (Avg: ${avgValue.toFixed(2)})`,
				data: avgData,
				borderColor: metric.color,
				borderWidth: 2,
				borderDash: [5, 5],
				fill: false,
				pointRadius: 0,
				tension: 0,
				borderOpacity: 0.6
			});
		});

		// Add threshold reference lines only for EV metric
		if (this.enabledMetrics.has('ev')) {
			// Day threshold (lower - bright) at 20%
			const dayThresholdData = this.chart.data.labels.map(() => this.dayThresholdPercent);
			this.chart.data.datasets.push({
				label: `Day Threshold (${this.dayThresholdPercent}%)`,
				data: dayThresholdData,
				borderColor: '#4CAF50',
				borderWidth: 2.5,
				borderDash: [8, 4],
				fill: false,
				pointRadius: 0,
				tension: 0
			});

			// Night threshold (upper - dark) at 85%
			const nightThresholdData = this.chart.data.labels.map(() => this.nightThresholdPercent);
			this.chart.data.datasets.push({
				label: `Night Threshold (${this.nightThresholdPercent}%)`,
				data: nightThresholdData,
				borderColor: '#2196F3',
				borderWidth: 2.5,
				borderDash: [8, 4],
				fill: false,
				pointRadius: 0,
				tension: 0
			});

			// Shaded region between thresholds
			const betweenThresholdData = this.chart.data.labels.map(() => (this.dayThresholdPercent + this.nightThresholdPercent) / 2);
			this.chart.data.datasets.push({
				label: 'Mode Switch Zone',
				data: betweenThresholdData,
				borderColor: 'transparent',
				backgroundColor: 'rgba(255, 193, 7, 0.1)',
				borderWidth: 0,
				fill: true,
				pointRadius: 0,
				tension: 0
			});
		}

		this.chart.update('none'); // No animation for smooth real-time updates
	}

	clearData() {
		if (!confirm('Clear all collected data?')) return;

		this.data = {};
		this.rawData = {};
		this.stats = {};
		this.chart.data.labels = [];
		this.chart.data.datasets = [];
		this.chart.update();
		this.updateStatsDisplay();
	}

	togglePause(e) {
		this.isPaused = !this.isPaused;
		e.target.textContent = this.isPaused ? 'Resume' : 'Pause';
		e.target.classList.toggle('btn-warning', this.isPaused);
		e.target.classList.toggle('btn-info', !this.isPaused);
	}

	updateStreamStatus(connected) {
		const statusEl = document.getElementById('stream-status');
		if (connected) {
			statusEl.classList.remove('disconnected');
			statusEl.classList.add('connected');
			statusEl.innerHTML = '<span class="status-indicator">●</span> Connected - Streaming data...';
		} else {
			statusEl.classList.remove('connected');
			statusEl.classList.add('disconnected');
			statusEl.innerHTML = '<span class="status-indicator">●</span> Disconnected - Reconnecting...';
		}
	}

	exportJSON() {
		const dataPoints = [];
		const labels = this.chart.data.labels;

		labels.forEach((label, idx) => {
			const point = { timestamp: label };
			this.chart.data.datasets.forEach((dataset) => {
				if (dataset.data[idx] !== undefined) {
					point[dataset.label] = dataset.data[idx];
				}
			});
			dataPoints.push(point);
		});

		const jsonData = {
			exportedAt: new Date().toISOString(),
			dataPoints: dataPoints,
			summary: {
				totalPoints: dataPoints.length,
				metrics: Array.from(this.enabledMetrics)
			}
		};

		const dataStr = JSON.stringify(jsonData, null, 2);
		this.downloadFile(dataStr, `timegraph-${Date.now()}.json`, 'application/json');
	}

	exportCSV() {
		const labels = this.chart.data.labels;
		const headers = ['timestamp', ...this.chart.data.datasets.map(d => d.label)];

		const rows = [headers];
		labels.forEach((label, idx) => {
			const row = [label];
			this.chart.data.datasets.forEach((dataset) => {
				row.push(dataset.data[idx] !== undefined ? dataset.data[idx] : '');
			});
			rows.push(row);
		});

		const csvContent = rows.map(row =>
			row.map(cell => {
				const str = String(cell);
				return str.includes(',') || str.includes('"') || str.includes('\n')
					? `"${str.replace(/"/g, '""')}"`
					: str;
			}).join(',')
		).join('\n');

		this.downloadFile(csvContent, `timegraph-${Date.now()}.csv`, 'text/csv');
	}

	downloadFile(content, filename, mimeType) {
		const blob = new Blob([content], { type: mimeType });
		const url = URL.createObjectURL(blob);
		const link = document.createElement('a');
		link.href = url;
		link.download = filename;
		document.body.appendChild(link);
		link.click();
		document.body.removeChild(link);
		URL.revokeObjectURL(url);
	}

	destroy() {
		if (this.eventSource) {
			this.eventSource.close();
			this.eventSource = null;
		}
	}
}

// Initialize on page load
document.addEventListener('DOMContentLoaded', () => {
	window.timeSeriesGraph = new TimeSeriesGraph();
});

// Cleanup on page unload
window.addEventListener('beforeunload', () => {
	if (window.timeSeriesGraph) {
		window.timeSeriesGraph.destroy();
	}
});
</script>

<%in _footer.cgi %>
