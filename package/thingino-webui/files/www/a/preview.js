const ImageBlackMode = 1;
const ImageColorMode = 0;

const endpoint = '/x/json-prudynt.cgi';

// Create fullscreen preview modal dynamically if preview element exists
(function createPreviewModal() {
  const preview = $('#preview');
  if (!preview) return;

  // Create modal HTML
  const modalHTML = `
    <div class="modal fade" id="mdPreview" tabindex="-1" aria-labelledby="mdlPreview" aria-hidden="true">
      <div class="modal-dialog modal-fullscreen">
        <div class="modal-content">
          <div class="modal-header">
            <h1 class="modal-title fs-4" id="mdlPreview">Full screen preview</h1>
            <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
          </div>
          <div class="modal-body text-center">
            <img id="preview_fullsize" src="/a/nostream.svg" alt="Image: Stream Preview" class="img-fluid">
          </div>
        </div>
      </div>
    </div>
  `;

  // Append modal to body
  document.body.insertAdjacentHTML('beforeend', modalHTML);

  // Add click event to preview image to open modal
  preview.addEventListener('click', () => {
    const previewModal = new bootstrap.Modal($('#mdPreview'));
    previewModal.show();
  });
})();

const stream_params = [
  'width', 'height', 'fps', 'bitrate', 'gop', 'max_gop', 'format', 'mode',
  'buffers', 'profile', 'rtsp_endpoint', 'video_enabled', 'audio_enabled'
];
const osd_params = ['enabled', 'fontname', 'fontsize', 'strokesize'];

function rgba2color(hex8) {
  return hex8.substring(0, 7);
}

function rgba2alpha(hex8) {
  const alphaHex = hex8.substring(7, 9);
  const alpha = parseInt(alphaHex, 16);
  return alpha;
}

function handleOsdData(osd, streamIndex) {
  if (!osd) return;

  if (osd.enabled !== undefined) {
    const el = $(`#osd${streamIndex}_enabled`);
    if (el) {
      el.checked = osd.enabled;
      el.disabled = false;
    }
  }
  if (osd.font_path) {
    const el = $(`#osd${streamIndex}_fontname`);
    if (el) {
      el.value = osd.font_path.split('/').pop();
      el.disabled = false;
    }
  }
  if (osd.font_size !== undefined) {
    const el = $(`#osd${streamIndex}_fontsize`);
    if (el) {
      el.value = osd.font_size;
      el.disabled = false;
    }
  }
  if (osd.stroke_size !== undefined) {
    const el = $(`#osd${streamIndex}_strokesize`);
    if (el) {
      el.value = osd.stroke_size;
      el.disabled = false;
    }
  }

  // Logo element
  if (osd.logo) {
    if (osd.logo.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_logo_enabled`);
      if (el) {
        el.checked = osd.logo.enabled;
        el.disabled = false;
      }
    }
    if (osd.logo.position !== undefined) {
      const el = $(`#osd${streamIndex}_logo_position`);
      if (el) {
        el.value = osd.logo.position;
        el.disabled = false;
      }
    }
  }

  // Time element
  if (osd.time) {
    if (osd.time.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_time_enabled`);
      if (el) {
        el.checked = osd.time.enabled;
        el.disabled = false;
      }
    }
    if (osd.time.format !== undefined) {
      const el = $(`#osd${streamIndex}_time_format`);
      if (el) {
        el.value = osd.time.format;
        el.disabled = false;
      }
    }
    if (osd.time.position !== undefined) {
      const el = $(`#osd${streamIndex}_time_position`);
      if (el) {
        el.value = osd.time.position;
        el.disabled = false;
      }
    }
    if (osd.time.fill_color) {
      const el = $(`#osd${streamIndex}_time_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.time.fill_color);
        el.disabled = false;
      }
    }
    if (osd.time.stroke_color) {
      const el = $(`#osd${streamIndex}_time_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.time.stroke_color);
        el.disabled = false;
      }
    }
  }

  // Uptime element
  if (osd.uptime) {
    if (osd.uptime.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_enabled`);
      if (el) {
        el.checked = osd.uptime.enabled;
        el.disabled = false;
      }
    }
    if (osd.uptime.position !== undefined) {
      const el = $(`#osd${streamIndex}_uptime_position`);
      if (el) {
        el.value = osd.uptime.position;
        el.disabled = false;
      }
    }
    if (osd.uptime.fill_color) {
      const el = $(`#osd${streamIndex}_uptime_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.uptime.fill_color);
        el.disabled = false;
      }
    }
    if (osd.uptime.stroke_color) {
      const el = $(`#osd${streamIndex}_uptime_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.uptime.stroke_color);
        el.disabled = false;
      }
    }
  }

  // Usertext element
  if (osd.usertext) {
    if (osd.usertext.enabled !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_enabled`);
      if (el) {
        el.checked = osd.usertext.enabled;
        el.disabled = false;
      }
    }
    if (osd.usertext.format !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_format`);
      if (el) {
        el.value = osd.usertext.format;
        el.disabled = false;
      }
    }
    if (osd.usertext.position !== undefined) {
      const el = $(`#osd${streamIndex}_usertext_position`);
      if (el) {
        el.value = osd.usertext.position;
        el.disabled = false;
      }
    }
    if (osd.usertext.fill_color) {
      const el = $(`#osd${streamIndex}_usertext_fillcolor`);
      if (el) {
        el.value = rgba2color(osd.usertext.fill_color);
        el.disabled = false;
      }
    }
    if (osd.usertext.stroke_color) {
      const el = $(`#osd${streamIndex}_usertext_strokecolor`);
      if (el) {
        el.value = rgba2color(osd.usertext.stroke_color);
        el.disabled = false;
      }
    }
  }
}

function handleMessage(msg) {
  if (msg.motion && msg.motion.enabled !== undefined) {
    $('#motion').checked = msg.motion.enabled;
  }
  if (msg.privacy && msg.privacy.enabled !== undefined) {
    $('#privacy').checked = msg.privacy.enabled;
  }

  // if (msg.rtsp) {
  //   const r = msg.rtsp;
  //   if (r.username && r.password && r.port && msg.stream0?.rtsp_endpoint)
  //     $('#playrtsp').innerHTML = `ffplay -hide_banner -rtsp_transport tcp rtsp://${r.username}:${r.password}@${document.location.hostname}:${r.port}/${msg.stream0.rtsp_endpoint}`;
  // }

  // Handle image params
  if (msg.image) {
    const imageParams = ['hflip', 'vflip', 'wb_bgain', 'wb_rgain', 'ae_compensation', 'core_wb_mode'];
    imageParams.forEach(param => {
      if (msg.image[param] !== undefined) {
        setValue(msg.image, 'image', param);
      }
    });
  }

  // Handle stream0 params
  if (msg.stream0) {
    stream_params.forEach(param => {
      if (msg.stream0[param] !== undefined) {
        setValue(msg.stream0, 'stream0', param);
      }
    });
    handleOsdData(msg.stream0.osd, 0);
  }

  // Handle stream1 params
  if (msg.stream1) {
    stream_params.forEach(param => {
      if (msg.stream1[param] !== undefined) {
        setValue(msg.stream1, 'stream1', param);
      }
    });
    handleOsdData(msg.stream1.osd, 1);
  }
}

async function loadMotorParams() {
  try {
    const response = await fetch('/x/json-motor-params.cgi');
    const motorParams = await response.json();
    window.motorParams = motorParams;
    console.log('Motor parameters loaded:', motorParams);
  } catch (error) {
    console.error('Failed to load motor parameters:', error);
    window.motorParams = {steps_pan: 0, steps_tilt: 0, pos_0_x: 0, pos_0_y: 0};
  }
}

async function loadConfig() {
  showBusy('Loading camera configuration...');
  const payload = JSON.stringify({
      image: {
        hflip: null, vflip: null,
        wb_bgain: null, wb_rgain: null,
        ae_compensation: null, core_wb_mode: null
      },
      motion: {enabled: null},
      privacy: {enabled: null},
      rtsp: {username: null, password: null, port: null},
      stream0: {
        width: null, height: null, fps: null, bitrate: null, gop: null, max_gop: null,
        format: null, mode: null, buffers: null, profile: null, rtsp_endpoint: null,
        video_enabled: null, audio_enabled: null,
        osd: {
          enabled: null, font_path: null, font_size: null, stroke_size: null,
          logo: {enabled: null, position: null},
          time: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null},
          uptime: {enabled: null, position: null, fill_color: null, stroke_color: null},
          usertext: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null}
        }
      },
      stream1: {
        width: null, height: null, fps: null, bitrate: null, gop: null, max_gop: null,
        format: null, mode: null, buffers: null, profile: null, rtsp_endpoint: null,
        video_enabled: null, audio_enabled: null,
        osd: {
          enabled: null, font_path: null, font_size: null, stroke_size: null,
          logo: {enabled: null, position: null},
          time: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null},
          uptime: {enabled: null, position: null, fill_color: null, stroke_color: null},
          usertext: {enabled: null, format: null, position: null, fill_color: null, stroke_color: null}
        }
      },
      action: {capture: null}
    });
  console.log('===>', payload);
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payload
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (text) {
      try {
        const msg = JSON.parse(text);
        console.log(ts(), '<===', JSON.stringify(msg));
        handleMessage(msg);
      } catch (parseErr) {
        console.warn(ts(), 'Invalid JSON response', text, parseErr);
      }
    } else {
      console.log(ts(), '<===', 'Empty response');
    }
  } catch (err) {
    console.error('Load config error', err);
  } finally {
    hideBusy();
  }
}

async function sendToEndpoint(payload) {
  console.log(ts(), '--->', payload);
  const payloadStr = typeof payload === 'string' ? payload : JSON.stringify(payload);
  console.log(ts(), '===>', payloadStr);
  try {
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: payloadStr
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (text) {
      try {
        const msg = JSON.parse(text);
        console.log(ts(), '<===', JSON.stringify(msg));
        handleMessage(msg);
      } catch (parseErr) {
        console.warn(ts(), 'Invalid JSON response', text, parseErr);
      }
    } else {
      console.log(ts(), '<===', 'Empty response');
    }
  } catch (err) {
    console.error('Send error', err);
  }
}

// Init on load
Promise.all([loadConfig(), loadMotorParams()]).then(async () => {
  // Load webui config for focus tracking settings
  let webuiConfig = {
    track_focus: false,
    focus_timeout: 0
  };

  async function loadWebuiConfig() {
    try {
      const response = await fetch('/x/json-config-webui.cgi', { headers: { 'Accept': 'application/json' } });
      if (response.ok) {
        const data = await response.json();
        webuiConfig.track_focus = data.track_focus === true;
        webuiConfig.focus_timeout = Math.max(0, parseInt(data.focus_timeout) || 0);
      }
    } catch (err) {
      console.warn('Could not load webui config for focus tracking:', err);
    }
  }

  // Load webui config before continuing
  await loadWebuiConfig();

  // Expose config reload function globally for use in config-webui.js
  window.reloadPreviewFocusSettings = async () => {
    await loadWebuiConfig();
    // Update event listeners based on new settings
    if (webuiConfig.track_focus) {
      // Add listeners if not already added
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('focus', handleWindowFocus);
      window.removeEventListener('blur', handleWindowBlur);
      document.addEventListener('visibilitychange', handleVisibilityChange);
      window.addEventListener('focus', handleWindowFocus);
      window.addEventListener('blur', handleWindowBlur);
    } else {
      // Remove listeners if tracking is disabled
      document.removeEventListener('visibilitychange', handleVisibilityChange);
      window.removeEventListener('focus', handleWindowFocus);
      window.removeEventListener('blur', handleWindowBlur);
      // Clear any pending timeouts
      if (focusTimeoutId) {
        clearTimeout(focusTimeoutId);
        focusTimeoutId = null;
      }
      // Ensure window is marked as visible and start preview
      isWindowVisible = true;
      startPreview();
    }
  };

  // Get stream from data-stream attribute, default to ch0 if not specified
  const preview = $('#preview');
  const streamChannel = preview?.dataset?.stream || 'ch0';
  const streamUrl = `/x/${streamChannel}.mjpg`;

  // Preview
  const timeout = 5000;
  let lastLoadTime = Date.now();
  let isWindowVisible = true;
  let focusTimeoutId = null;

  // Function to start the preview stream
  function startPreview() {
    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
      focusTimeoutId = null;
    }
    if (isWindowVisible) {
      preview.src = streamUrl;
      lastLoadTime = Date.now();
    }
  }

  // Function to stop the preview stream
  function stopPreview() {
    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
      focusTimeoutId = null;
    }
    preview.src = ImageNoStream;
  }

  // Function to stop preview with delay
  function stopPreviewWithDelay() {
    if (!webuiConfig.track_focus) {
      return; // Don't stop if tracking is disabled
    }

    if (focusTimeoutId) {
      clearTimeout(focusTimeoutId);
    }

    if (webuiConfig.focus_timeout > 0) {
      focusTimeoutId = setTimeout(() => {
        if (!isWindowVisible) {
          stopPreview();
        }
      }, webuiConfig.focus_timeout * 1000);
    } else {
      stopPreview();
    }
  }

  // Start the preview stream
  startPreview();

  preview.addEventListener('load', () => {
    lastLoadTime = Date.now();
  });

  // Stream watchdog - restart if no frames received
  setInterval(() => {
    if (isWindowVisible && Date.now() - lastLoadTime > timeout) {
      // Restart stream
      preview.src = preview.src.split('?')[0] + '?' + new Date().getTime();
      lastLoadTime = Date.now();
    }
  }, 1000);

  // Handle window visibility changes
  function handleVisibilityChange() {
    if (document.hidden) {
      isWindowVisible = false;
      stopPreviewWithDelay();
    } else {
      isWindowVisible = true;
      startPreview();
    }
  }

  // Handle window focus/blur events
  function handleWindowFocus() {
    isWindowVisible = true;
    startPreview();
  }

  function handleWindowBlur() {
    isWindowVisible = false;
    stopPreviewWithDelay();
  }

  // Add event listeners for visibility changes only if tracking is enabled
  if (webuiConfig.track_focus) {
    document.addEventListener('visibilitychange', handleVisibilityChange);
    window.addEventListener('focus', handleWindowFocus);
    window.addEventListener('blur', handleWindowBlur);
  }

  // Full-screen preview modal
  const previewModal = $('#mdPreview');
  const previewFullsize = $('#preview_fullsize');
  let savedPreviewSrc = '';

  if (previewModal && previewFullsize) {
    previewModal.addEventListener('show.bs.modal', () => {
      // Save current small preview source
      savedPreviewSrc = preview.src;
      // Stop the small preview
      preview.src = ImageNoStream;
      // Load main stream (ch0) in full-screen modal
      previewFullsize.src = '/x/ch0.mjpg?' + new Date().getTime();
    });

    previewModal.addEventListener('hidden.bs.modal', () => {
      // Stop the full-screen stream
      previewFullsize.src = ImageNoStream;
      // Restart the small preview
      if (savedPreviewSrc && isWindowVisible) {
        preview.src = savedPreviewSrc.split('?')[0] + '?' + new Date().getTime();
        lastLoadTime = Date.now();
      }
    });
  }
});

const imagingFields = [
  "brightness",
  "contrast",
  "sharpness",
  "saturation",
  "backlight",
  "wide_dynamic_range",
  "tone",
  "defog",
  "noise_reduction"
];

const imageConfigKeyMap = {
  brightness: "brightness",
  contrast: "contrast",
  sharpness: "sharpness",
  saturation: "saturation",
  backlight: "backlight_compensation",
  wide_dynamic_range: "drc_strength",
  tone: "highlight_depress",
  defog: "defog_strength",
  noise_reduction: "sinter_strength"
};

const previewSliderIds = [
  'brightness', 'contrast', 'sharpness', 'saturation',
  'backlight', 'wide_dynamic_range', 'tone', 'defog',
  'noise_reduction', 'image_wb_bgain', 'image_wb_rgain',
  'image_ae_compensation', 'stream0_fps', 'stream1_fps'
];

(function initPreviewSliders() {
  if (typeof window === 'undefined' || typeof window.initSliders !== 'function') {
    return;
  }
  const run = () => window.initSliders(previewSliderIds);
  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', () => run(), { once: true });
  } else {
    run();
  }
})();

// Load sensor information on sensor page
(function loadSensorInfo() {
  if (!$('#sensor-info')) {
    return; // Not on sensor page
  }

  const sensorLoading = $('#sensor-loading');
  const sensorDetails = $('#sensor-details');
  const sensorFilePath = $('#sensor-file-path');
  const sensorMd5 = $('#sensor-md5');

  async function fetchSensorInfo() {
    try {
      const response = await fetch('/x/json-sensor-info.cgi');
      if (!response.ok) {
        throw new Error(`HTTP ${response.status}`);
      }
      const data = await response.json();

      if (data.error) {
        throw new Error(data.error.message || 'Unknown error');
      }

      sensorFilePath.textContent = data.file_path || 'Unknown';
      sensorMd5.textContent = data.md5 || 'Unknown';

      sensorLoading.classList.add('d-none');
      sensorDetails.classList.remove('d-none');
    } catch (err) {
      sensorLoading.textContent = `Error loading sensor info: ${err.message}`;
    }
  }

  fetchSensorInfo();
})();

// Disable all imaging controls initially
imagingFields.forEach(field => {
  const input = $(`#${field}`);
  if (input) {
    input.disabled = true;
    const wrapper = input.closest('.number-range, .col');
    if (wrapper) wrapper.classList.add('disabled');
  }
  // Also disable the modal slider if it exists
  const slider = $(`#${field}-slider`);
  if (slider) slider.disabled = true;
});

function updateImagingLabel(name, value) {
  const input = $(`#${name}`);
  if (input) {
    input.value = value === undefined || value === null ? '' : value;
  }
  // Also update the slider value display in modal
  const sliderValue = $(`#${name}-slider-value`);
  if (sliderValue) {
    const displayValue = value === undefined || value === null ? '—' : value;
    sliderValue.textContent = displayValue;
  }
  // Update the actual slider
  const slider = $(`#${name}-slider`);
  if (slider && value !== undefined && value !== null) {
    slider.value = value;
  }
}

function setSliderBounds(input, slider, min, max, value, defaultValue) {
  if (Number.isFinite(min)) {
    if (input) input.dataset.min = min;
    if (slider) slider.min = min;
  }
  if (Number.isFinite(max)) {
    if (input) input.dataset.max = max;
    if (slider) slider.max = max;
  }
  if (Number.isFinite(value)) {
    if (input) input.value = value;
    if (slider) slider.value = value;
  }
  if (Number.isFinite(defaultValue)) {
    if (input) input.dataset.defaultValue = defaultValue;
    if (slider) slider.dataset.defaultValue = defaultValue;
  } else {
    if (input) delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
  }
}

function applyFieldMetadata(field, data) {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);
  if (!input) return;
  const wrapper = input.closest('.col, .number-range') || input.parentElement;
  const isSupported = data && data.supported !== false;
  if (!isSupported) {
    input.disabled = true;
    if (slider) slider.disabled = true;
    if (wrapper) wrapper.classList.add('disabled');
    delete input.dataset.defaultValue;
    if (slider) delete slider.dataset.defaultValue;
    updateImagingLabel(field, '—');
    return;
  }
  input.disabled = false;
  if (slider) slider.disabled = false;
  if (wrapper) wrapper.classList.remove('disabled');
  setSliderBounds(input, slider, Number(data.min), Number(data.max), Number(data.value), Number(data.default));
  updateImagingLabel(field, data.value);
}

async function fetchImagingState() {
  showBusy('Loading imaging settings...');
  try {
    const res = await fetch('/x/json-imaging.cgi', {cache: 'no-store'});
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const payload = await res.json();
    const fields = payload && payload.message && payload.message.fields;
    if (!fields) return;
    imagingFields.forEach(field => applyFieldMetadata(field, fields[field] || null));
  } catch (err) {
    console.warn('Unable to load imaging state', err);
  } finally {
    hideBusy();
  }
}

async function persistImagingSetting(field, value) {
  const configKey = imageConfigKeyMap[field];
  if (!configKey) return;
  const numericValue = Number(value);
  if (!Number.isFinite(numericValue)) return;
  try {
    await sendToEndpoint({image: {[configKey]: numericValue}});
  } catch (err) {
    console.warn('Failed to persist imaging setting', field, err);
  }
}

async function sendImagingUpdate(field, value, element) {
  const params = new URLSearchParams({cmd: 'set'});
  params.append(field, value);
  element?.setAttribute('data-busy', '1');
  element?.classList.add('opacity-75');
  try {
    const res = await fetch('/x/json-imaging.cgi', {
      method: 'POST',
      headers: {'Content-Type': 'application/x-www-form-urlencoded'},
      body: params.toString(),
      cache: 'no-store'
    });
    if (!res.ok) throw new Error(`HTTP ${res.status}`);
    const text = await res.text();
    if (text) {
      const payload = JSON.parse(text);
      const fields = payload && payload.message && payload.message.fields;
      if (fields) {
        applyFieldMetadata(field, fields[field] || null);
      }
    }
    await persistImagingSetting(field, value);
  } catch (err) {
    console.error('Failed to update imaging value', err);
  } finally {
    element?.removeAttribute('data-busy');
    element?.classList.remove('opacity-75');
  }
}

// Setup event handlers for imaging fields (number inputs and modal sliders)
imagingFields.forEach(field => {
  const input = $(`#${field}`);
  const slider = $(`#${field}-slider`);

  // Handle text input changes
  if (input) {
    input.addEventListener('change', ev => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on input to reset to default
    input.addEventListener('dblclick', ev => {
      const min = Number(ev.target.dataset.min ?? 0);
      const max = Number(ev.target.dataset.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue)) ? Number(defaultValue) : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }

  // Handle modal slider input (live update)
  if (slider) {
    slider.addEventListener('input', ev => {
      updateImagingLabel(field, ev.target.value);
    });

    // Handle slider change (on release)
    slider.addEventListener('change', ev => {
      const value = parseInt(ev.target.value);
      if (!isNaN(value)) {
        sendImagingUpdate(field, value, ev.target);
      }
    });

    // Double-click on slider to reset to default
    slider.addEventListener('dblclick', ev => {
      const min = Number(ev.target.min ?? 0);
      const max = Number(ev.target.max ?? 255);
      const midpoint = Math.round((min + max) / 2);
      const defaultValue = ev.target.dataset.defaultValue;
      const targetValue = Number.isFinite(Number(defaultValue)) ? Number(defaultValue) : midpoint;
      ev.target.value = targetValue;
      updateImagingLabel(field, targetValue);
      sendImagingUpdate(field, targetValue, ev.target);
    });
  }
});

// Streamer controls
function coerceStreamValue(param, el) {
  if (el.type === 'checkbox') {
    return el.checked;
  }

  const raw = typeof el.value === 'string' ? el.value : '';
  const trimmed = raw.trim();
  if (trimmed === '') {
    return '';
  }

  // Treat any purely numeric string as a number so prudynt gets the correct type.
  if (/^-?\d+(?:\.\d+)?$/.test(trimmed)) {
    return trimmed.includes('.') ? Number.parseFloat(trimmed) : Number.parseInt(trimmed, 10);
  }

  return trimmed;
}

function saveStreamValue(streamId, param) {
  const el = $(`#stream${streamId}_${param}`);
  if (!el) return;
  const value = coerceStreamValue(param, el);
  const payload = {[`stream${streamId}`]: {[param]: value}, action: {restart_thread: ThreadRtsp | ThreadVideo}};
  sendToEndpoint(payload);
}

// Setup stream0 and stream1 controls
[0, 1].forEach(streamId => {
  stream_params.forEach(param => {
    const el = $(`#stream${streamId}_${param}`);
    if (el) {
      el.addEventListener('change', () => saveStreamValue(streamId, param));
      el.disabled = true;
    }

    // Also handle modal slider if it exists
    const slider = $(`#stream${streamId}_${param}-slider`);
    if (slider) {
      slider.addEventListener('input', ev => {
        // Update the text input while dragging
        if (el) el.value = ev.target.value;
        const sliderValue = $(`#stream${streamId}_${param}-slider-value`);
        if (sliderValue) sliderValue.textContent = ev.target.value;
      });
      slider.addEventListener('change', () => saveStreamValue(streamId, param));
      slider.disabled = true;
    }
  });
});

// OSD controls
function sendOsdUpdate(streamId, osdPayload) {
  // OSD changes require Video + OSD thread restart to take effect immediately
  const payload = {[`stream${streamId}`]: {osd: osdPayload}, action: {restart_thread: ThreadVideo | ThreadOSD}};
  sendToEndpoint(payload);
}

function setFont(streamId) {
  const fontSelect = $(`#osd${streamId}_fontname`);
  const fontSizeInput = $(`#osd${streamId}_fontsize`);
  const strokeSizeInput = $(`#osd${streamId}_strokesize`);
  if (!fontSelect || !fontSizeInput || !strokeSizeInput) return;

  const payload = {};
  const fontName = fontSelect.value;
  if (fontName)
    payload.font_path = `/usr/share/fonts/${fontName}`;

  const fontSize = Number(fontSizeInput.value);
  if (!Number.isNaN(fontSize)) {
    payload.font_size = fontSize;
  }

  const strokeSize = Number(strokeSizeInput.value);
  if (!Number.isNaN(strokeSize)) {
    payload.stroke_size = strokeSize;
  }

  if (Object.keys(payload).length === 0) return;
  console.log(ts(), 'setFont for stream', streamId, ':', payload);
  // Font changes require Video + OSD thread restart for immediate effect
  const fullPayload = {[`stream${streamId}`]: {osd: payload}, action: {restart_thread: ThreadVideo | ThreadOSD}};
  sendToEndpoint(fullPayload);
}

// Setup OSD controls for both stream0 and stream1
[0, 1].forEach(streamId => {
  // Configuration for OSD controls
  const osdControls = [
    { id: 'enabled', handler: (e) => sendOsdUpdate(streamId, {enabled: e.target.checked}) },
    { id: 'fontname', handler: () => setFont(streamId) },
    { id: 'fontsize', handler: () => setFont(streamId) },
    { id: 'strokesize', handler: () => setFont(streamId) },
    { id: 'logo_enabled', handler: (e) => sendOsdUpdate(streamId, {logo: {enabled: e.target.checked}}) },
    { id: 'logo_position', handler: (e) => sendOsdUpdate(streamId, {logo: {position: e.target.value}}) },
    { id: 'time_enabled', handler: (e) => sendOsdUpdate(streamId, {time: {enabled: e.target.checked}}) },
    { id: 'time_format', handler: (e) => sendOsdUpdate(streamId, {time: {format: e.target.value}}) },
    { id: 'time_position', handler: (e) => sendOsdUpdate(streamId, {time: {position: e.target.value}}) },
    { id: 'time_fillcolor', handler: (e) => sendOsdUpdate(streamId, {time: {fill_color: e.target.value + 'ff'}}) },
    { id: 'time_strokecolor', handler: (e) => sendOsdUpdate(streamId, {time: {stroke_color: e.target.value + 'ff'}}) },
    { id: 'uptime_enabled', handler: (e) => sendOsdUpdate(streamId, {uptime: {enabled: e.target.checked}}) },
    { id: 'uptime_position', handler: (e) => sendOsdUpdate(streamId, {uptime: {position: e.target.value}}) },
    { id: 'uptime_fillcolor', handler: (e) => sendOsdUpdate(streamId, {uptime: {fill_color: e.target.value + 'ff'}}) },
    { id: 'uptime_strokecolor', handler: (e) => sendOsdUpdate(streamId, {uptime: {stroke_color: e.target.value + 'ff'}}) },
    { id: 'usertext_enabled', handler: (e) => sendOsdUpdate(streamId, {usertext: {enabled: e.target.checked}}) },
    { id: 'usertext_format', handler: (e) => sendOsdUpdate(streamId, {usertext: {format: e.target.value}}) },
    { id: 'usertext_position', handler: (e) => sendOsdUpdate(streamId, {usertext: {position: e.target.value}}) },
    { id: 'usertext_fillcolor', handler: (e) => sendOsdUpdate(streamId, {usertext: {fill_color: e.target.value + 'ff'}}) },
    { id: 'usertext_strokecolor', handler: (e) => sendOsdUpdate(streamId, {usertext: {stroke_color: e.target.value + 'ff'}}) }
  ];

  osdControls.forEach(({id, handler}) => {
    const el = $(`#osd${streamId}_${id}`);
    if (el) {
      el.addEventListener('change', handler);
      el.disabled = true;
    }
  });
});

// Image controls (WB and AE)
function saveImageValue(param) {
  const el = $('#image_' + param);
  if (!el) return;

  let value;
  if (el.type === 'checkbox') {
    value = el.checked;
  } else if (el.type === 'select-one') {
    value = parseInt(el.value);
  } else {
    value = parseInt(el.value);
  }

  const payload = {image: {[param]: value}};
  console.log(ts(), 'Sending image param:', param, '=', value);
  sendToEndpoint(payload);
}

const imageParams = ['hflip', 'vflip', 'wb_bgain', 'wb_rgain', 'ae_compensation', 'core_wb_mode'];
imageParams.forEach(param => {
  const el = $('#image_' + param);
  if (el) {
    el.addEventListener('change', () => {
      console.log('Image param changed:', param);
      saveImageValue(param);
    });
    el.disabled = true;
  }
});

// Export configuration button
const exportConfigBtn = $('#export-config');
if (exportConfigBtn) {
  exportConfigBtn.addEventListener('click', () => {
    exportConfigBtn.disabled = true;

    // Open the CGI endpoint which will trigger download
    window.location.href = '/x/json-prudynt-config.cgi';

    // Re-enable button after a short delay
    setTimeout(() => {
      exportConfigBtn.disabled = false;
    }, 1000);
  });
}

// Save configuration button
const saveConfigBtn = $('#save-config');
if (saveConfigBtn) {
  saveConfigBtn.addEventListener('click', async () => {
        const confirmed = await confirm('Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.');
        if (!confirmed) return;

    try {
      saveConfigBtn.disabled = true;

      const payload = {action: {save_config: null}};
      const res = await fetch('/x/json-prudynt.cgi', {
        method: 'POST',
        headers: {'Content-Type': 'application/json'},
        body: JSON.stringify(payload)
      });

      if (!res.ok) throw new Error(`HTTP ${res.status}`);
      const data = await res.json();

      if (data.action && data.action.save_config === 'ok') {
        alert('Configuration saved successfully to /etc/prudynt.json');
      } else {
        throw new Error('Save failed');
      }
    } catch (err) {
      console.error('Failed to save config:', err);
      alert('Failed to save configuration: ' + err.message);
    } finally {
      saveConfigBtn.disabled = false;
    }
  });
}

fetchImagingState();

// Add reload button handler
const reloadBtn = $('#preview-reload');
if (reloadBtn) {
  reloadBtn.addEventListener('click', () => {
    Promise.all([loadConfig(), loadMotorParams()]).then(() => {
      console.log('Configuration and motor parameters reloaded');
    });
  });
}
