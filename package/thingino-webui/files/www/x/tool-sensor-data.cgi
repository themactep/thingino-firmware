#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Sensor Data Collector"
pagename="sensor-data"
%>
<%in _header.cgi %>

<style>
#chart-container {
	position: relative;
	height: 500px;
	margin-bottom: 2rem;
}

.controls {
	display: flex;
	gap: 1rem;
	flex-wrap: wrap;
	margin-bottom: 1rem;
	align-items: center;
}

.controls button,
.controls select {
	padding: 0.5rem 1rem;
	border: 1px solid #ccc;
	border-radius: 0.25rem;
	background-color: var(--bs-body-bg);
	cursor: pointer;
}

.stat-grid {
	display: grid;
	grid-template-columns: repeat(auto-fit, minmax(200px, 1fr));
	gap: 1rem;
	margin-bottom: 2rem;
}

.stat-card {
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
	font-size: 1.75rem;
	font-weight: bold;
	color: var(--bs-body-color);
}

.stat-detail {
	font-size: 0.75rem;
	color: #999;
	margin-top: 0.5rem;
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
</style>

<div class="container-fluid">
	<h2>Raw Sensor Data Collection</h2>
	<p>Graphs raw unprocessed sensor values for day/night algorithm analysis</p>

	<div id="stream-status" class="stream-status disconnected">
		<span class="status-indicator">●</span> Connecting...
	</div>

	<div class="controls">
		<button id="clear-data" class="btn btn-danger">Clear Data</button>
		<button id="toggle-pause" class="btn btn-info">Pause</button>
		<select id="max-points">
			<option value="100">Last 100 points</option>
			<option value="300" selected>Last 300 points</option>
			<option value="600">Last 600 points</option>
			<option value="1200">Last 1200 points (10min)</option>
		</select>
		<button id="export-json" class="btn btn-info">Export JSON</button>
		<button id="export-csv" class="btn btn-info">Export CSV</button>
	</div>

	<div id="chart-container">
		<canvas id="dataChart"></canvas>
	</div>

	<h3>Current Values</h3>
	<div class="stat-grid" id="data-stats">
		<!-- Populated by JavaScript -->
	</div>
</div>

<script src="https://cdn.jsdelivr.net/npm/chart.js@4.4.0/dist/chart.umd.min.js"></script>
<script>
class SensorDataCollector {
	constructor() {
		this.sseUrl = '/x/json-timegraph-stream.cgi';
		this.maxPoints = 300;
		this.data = {};
		this.chart = null;
		this.eventSource = null;
		this.isPaused = false;

		// Metrics to track: raw, unprocessed values only
		// NOTE: GB/GR gains always return 0 from ISP (not populated on T23)
		this.metrics = [
			{ key: 'ev', label: 'Exposure Time (EV)', color: '#FF6384' },
			{ key: 'total_gain', label: 'Total Gain', color: '#36A2EB' },
			{ key: 'ae_luma', label: 'AE Luma', color: '#FFCE56' },
			{ key: 'daynight_brightness', label: 'Brightness %', color: '#FFB84D' }
		];

		// Track mode changes separately (day=0, night=1)
		this.modeData = [];
		this.lastMode = null;

		this.stats = {};

		this.init();
	}

	init() {
		this.setupEventListeners();
		this.initChart();
		this.startStream();
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
							text: 'Raw Value'
						}
					},
					y1: {
						display: false,
						type: 'linear',
						min: 0,
						max: 1,
						position: 'right'
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
			setTimeout(() => this.startStream(), 5000);
		};

		this.updateStreamStatus(true);
	}

	addDataPoint(jsonData) {
		const timestamp = new Date(parseInt(jsonData.time_now) * 1000);
		const timeStr = timestamp.toLocaleTimeString();

		if (!this.chart.data.labels.includes(timeStr)) {
			this.chart.data.labels.push(timeStr);
		}

		// Store thresholds from the first data point
		if (jsonData.total_gain_night_threshold !== undefined && !this.nightThreshold) {
			this.nightThreshold = parseInt(jsonData.total_gain_night_threshold);
			this.dayThreshold = parseInt(jsonData.total_gain_day_threshold);
		}

		// Track daynight mode (day=0, night=1)
		const currentMode = jsonData.daynight_mode === 'night' ? 1 : 0;
		this.modeData.push(currentMode);
		if (this.lastMode === null) this.lastMode = currentMode;

		// Add data for all metrics (raw, unprocessed values)
		this.metrics.forEach(metric => {
			if (!(metric.key in jsonData)) return;

			if (!this.data[metric.key]) {
				this.data[metric.key] = [];
			}

			const value = parseFloat(jsonData[metric.key]);
			if (!isNaN(value)) {
				this.data[metric.key].push(value);
				this.updateStats(metric.key, value);
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
				sum: value
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

		this.updateStatsDisplay();
	}

	updateStatsDisplay() {
		const container = document.getElementById('data-stats');
		container.innerHTML = '';

		this.metrics.forEach(metric => {
			const stat = this.stats[metric.key];
			if (!stat) return;

			const div = document.createElement('div');
			div.className = 'stat-card';
			div.innerHTML = `
				<div class="stat-label">${metric.label}</div>
				<div class="stat-value">${stat.latest.toFixed(1)}</div>
				<div class="stat-detail">
					Min: ${stat.min.toFixed(1)} | Max: ${stat.max.toFixed(1)} | Avg: ${stat.avg.toFixed(1)}
				</div>
			`;
			container.appendChild(div);
		});
	}

	updateChart() {
		this.chart.data.datasets = [];

		this.metrics.forEach(metric => {
			if (!this.data[metric.key]) return;

			this.chart.data.datasets.push({
				label: metric.label,
				data: this.data[metric.key],
				borderColor: metric.color,
				backgroundColor: metric.color + '20',
				borderWidth: 2,
				tension: 0.4,
				fill: false,
				pointRadius: 2,
				pointBackgroundColor: metric.color,
				pointBorderColor: '#fff',
				pointBorderWidth: 1
			});
		});

		// Add threshold lines if we have them
		if (this.nightThreshold && this.data.total_gain) {
			const numPoints = this.chart.data.labels.length;

			// Night threshold line (red dashed)
			this.chart.data.datasets.push({
				label: `Night Threshold (${this.nightThreshold})`,
				data: Array(numPoints).fill(this.nightThreshold),
				borderColor: 'rgba(255, 0, 0, 0.7)',
				borderWidth: 2,
				borderDash: [5, 5],
				fill: false,
				pointRadius: 0
			});

			// Day threshold line (green dashed)
			this.chart.data.datasets.push({
				label: `Day Threshold (${this.dayThreshold})`,
				data: Array(numPoints).fill(this.dayThreshold),
				borderColor: 'rgba(0, 255, 0, 0.7)',
				borderWidth: 2,
				borderDash: [5, 5],
				fill: false,
				pointRadius: 0
			});
		}

		// Add daynight mode as background color (day=light, night=dark)
		if (this.modeData.length > 0) {
			this.chart.data.datasets.push({
				label: 'Mode (0=Day, 1=Night)',
				data: this.modeData,
				borderColor: 'rgba(128, 128, 128, 0.5)',
				backgroundColor: 'rgba(128, 128, 128, 0.1)',
				borderWidth: 1,
				tension: 0,
				fill: false,
				pointRadius: 0,
				yAxisID: 'y1'
			});
		}

		this.chart.update('none');
	}

	trimData() {
		if (this.chart.data.labels.length > this.maxPoints) {
			const excess = this.chart.data.labels.length - this.maxPoints;
			this.chart.data.labels.splice(0, excess);
			this.modeData.splice(0, excess);
			this.metrics.forEach(metric => {
				if (this.data[metric.key]) {
					this.data[metric.key].splice(0, excess);
				}
			});
		}
	}

	clearData() {
		if (!confirm('Clear all data?')) return;
		this.data = {};
		this.modeData = [];
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
		const el = document.getElementById('stream-status');
		if (connected) {
			el.classList.remove('disconnected');
			el.classList.add('connected');
			el.innerHTML = '<span class="status-indicator">●</span> Connected - Collecting sensor data';
		} else {
			el.classList.remove('connected');
			el.classList.add('disconnected');
			el.innerHTML = '<span class="status-indicator">●</span> Disconnected - Reconnecting...';
		}
	}

	exportJSON() {
		const data = {
			exported_at: new Date().toISOString(),
			stats: this.stats,
			datapoints: this.data,
			labels: this.chart.data.labels
		};
		const json = JSON.stringify(data, null, 2);
		this.downloadFile(json, 'sensor-data.json', 'application/json');
	}

	exportCSV() {
		const headers = this.metrics.map(m => m.label).join(',');
		const rows = this.chart.data.labels.map((label, idx) => {
			const values = this.metrics.map(m => {
				const v = this.data[m.key]?.[idx];
				return v !== undefined ? v.toFixed(2) : '';
			}).join(',');
			return `"${label}",${values}`;
		});

		const csv = `Time,${headers}\n${rows.join('\n')}`;
		this.downloadFile(csv, 'sensor-data.csv', 'text/csv');
	}

	downloadFile(content, filename, type) {
		const blob = new Blob([content], { type });
		const url = URL.createObjectURL(blob);
		const a = document.createElement('a');
		a.href = url;
		a.download = filename;
		document.body.appendChild(a);
		a.click();
		document.body.removeChild(a);
		URL.revokeObjectURL(url);
	}
}

document.addEventListener('DOMContentLoaded', () => {
	new SensorDataCollector();
});
</script>

<%in _footer.cgi %>
