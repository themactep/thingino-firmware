(function() {
  'use strict';

  const endpoint = '/x/json-prudynt.cgi';
  const streamIds = [0, 1];
  const standardFields = ['enabled', 'text', 'layer', 'opacity', 'position', 'rotation', 'font_size', 'stroke_size', 'image_path', 'image_width', 'image_height'];
  const numericFields = new Set(['layer', 'opacity', 'rotation', 'font_size', 'stroke_size', 'image_width', 'image_height']);
  const allowEmptyFields = new Set(['image_path', 'text']);
  const FontSizeScale = 256;
  const colorFieldMap = [
    { key: 'fill_color', colorId: 'fill_color', alphaId: 'fill_alpha' },
    { key: 'stroke_color', colorId: 'stroke_color', alphaId: 'stroke_alpha' }
  ];

  const alertArea = $('#privacy-alerts');
  const contentWrap = $('#privacy-content');
  const reloadButton = $('#privacy-reload');
  const saveButton = $('#privacy-save');
  const form = $('#privacy-form');

  function toggleInitialLoading(active) {
    if (!contentWrap) return;
    if (active) {
      showBusy('Loading privacy settings...');
      contentWrap.classList.add('d-none');
    } else {
      hideBusy();
      contentWrap.classList.remove('d-none');
    }
  }

  function setReloadBusy(state) {
    if (!reloadButton) return;
    reloadButton.disabled = !!state;
    reloadButton.classList.toggle('disabled', !!state);
  }

  async function persistPrudyntConfig() {
    const confirmed = await confirm('Save the current configuration to /etc/prudynt.json?\n\nThis will overwrite the saved configuration file on the camera.');
    if (!confirmed) return false;
    if (saveButton) saveButton.disabled = true;
    try {
      const payload = { action: { save_config: null } };
      const response = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      if (!response.ok) throw new Error(`HTTP ${response.status}`);
      const data = await response.json();
      if (!data?.action || data.action.save_config !== 'ok') {
        throw new Error('Save failed');
      }
      showAlert('success', 'Configuration saved to /etc/prudynt.json.');
      return true;
    } catch (err) {
      showAlert('danger', `Failed to save privacy settings: ${err.message || err}`);
      return false;
    } finally {
      if (saveButton) saveButton.disabled = false;
    }
  }

  function disablePrivacyControls() {
    streamIds.forEach(streamId => {
      [...standardFields, 'fill_color', 'stroke_color', 'fill_alpha', 'stroke_alpha'].forEach(field => {
        const el = $(`#privacy${streamId}_${field}`);
        if (el) el.disabled = true;
      });
    });
  }

  function createRequestTemplate() {
    const template = {};
    standardFields.forEach(field => {
      template[field] = null;
    });
    colorFieldMap.forEach(field => {
      template[field.key] = null;
    });
    return template;
  }

  function buildRequestPayload() {
    const template0 = createRequestTemplate();
    const template1 = createRequestTemplate();
    return {
      stream0: { osd: { privacy: template0 } },
      stream1: { osd: { privacy: template1 } }
    };
  }

  async function requestPrudynt(payload) {
    const body = typeof payload === 'string' ? payload : JSON.stringify(payload);
    const response = await fetch(endpoint, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body
    });
    if (!response.ok) throw new Error(`HTTP ${response.status}`);
    const text = await response.text();
    if (!text) return {};
    try {
      return JSON.parse(text);
    } catch (err) {
      throw new Error('Invalid JSON from prudynt');
    }
  }

  function normalizeColor(value) {
    if (typeof value !== 'string') return null;
    const trimmed = value.trim();
    if (!/^#[0-9a-fA-F]{6}$/.test(trimmed)) return null;
    return trimmed.toUpperCase();
  }

  function clampAlpha(value) {
    const num = Number(value);
    if (!Number.isFinite(num)) return null;
    return Math.min(255, Math.max(0, Math.round(num)));
  }

  function buildHexColor(color, alpha) {
    const safeColor = normalizeColor(color) || '#000000';
    const safeAlpha = clampAlpha(alpha);
    const alphaHex = Number.isInteger(safeAlpha) ? safeAlpha.toString(16).padStart(2, '0').toUpperCase() : 'FF';
    return safeColor + alphaHex;
  }

  function splitHexColor(hex8) {
    if (typeof hex8 !== 'string' || !/^#[0-9a-fA-F]{8}$/.test(hex8.trim())) {
      return { color: '#000000', alpha: 255 };
    }
    const normalized = hex8.trim().toUpperCase();
    return {
      color: normalized.substring(0, 7),
      alpha: parseInt(normalized.substring(7, 9), 16)
    };
  }

  function applyColorField(streamId, key, value) {
    const mapEntry = colorFieldMap.find(entry => entry.key === key);
    if (!mapEntry) return;
    const { colorId, alphaId } = mapEntry;
    const colorEl = $(`#privacy${streamId}_${colorId}`);
    const alphaEl = $(`#privacy${streamId}_${alphaId}`);
    if (!colorEl || !alphaEl) return;
    const { color, alpha } = splitHexColor(value || '');
    colorEl.disabled = false;
    alphaEl.disabled = false;
    colorEl.value = color;
    alphaEl.value = Number.isFinite(alpha) ? alpha : 255;
  }

  function setPrivacyField(streamId, field, value) {
    const el = $(`#privacy${streamId}_${field}`);
    if (!el) return;
    el.disabled = false;
    let resolved = value;
    if (field === 'font_size') {
      const num = Number(value);
      resolved = Number.isFinite(num) ? Math.max(0, Math.round(num / FontSizeScale)) : '';
    }
    if (el.type === 'checkbox') {
      el.checked = Boolean(resolved);
    } else if (resolved === null || typeof resolved === 'undefined') {
      el.value = '';
    } else {
      el.value = resolved;
    }
  }

  function applyPrivacyConfig(streamId, privacy = {}) {
    if (!privacy) return;
    standardFields.forEach(field => {
      if (Object.prototype.hasOwnProperty.call(privacy, field)) {
        setPrivacyField(streamId, field, privacy[field]);
      }
    });
    colorFieldMap.forEach(field => {
      if (Object.prototype.hasOwnProperty.call(privacy, field.key)) {
        applyColorField(streamId, field.key, privacy[field.key]);
      }
    });
  }

  async function loadPrivacyConfig(options = {}) {
    const { silent = false } = options;
    let success = false;
    if (!silent) {
      toggleInitialLoading(true);
    } else {
      setReloadBusy(true);
    }
    try {
      const data = await requestPrudynt(buildRequestPayload());
      const stream0 = data?.stream0?.osd?.privacy;
      const stream1 = data?.stream1?.osd?.privacy;
      applyPrivacyConfig(0, stream0);
      applyPrivacyConfig(1, stream1);
      success = true;
      return true;
    } catch (err) {
      showAlert('danger', `Unable to load privacy settings: ${err.message || err}`);
      return false;
    } finally {
      if (!silent) {
        toggleInitialLoading(false);
      } else {
        setReloadBusy(false);
        if (success) {
          showAlert('info', 'Privacy settings reloaded from camera.', 3000);
        }
      }
    }
  }

  async function sendPrivacyUpdate(streamId, payload) {
    try {
      const body = {
        [`stream${streamId}`]: { osd: { privacy: payload } },
        action: { restart_thread: ThreadVideo | ThreadOSD }
      };
      const data = await requestPrudynt(body);
      const updated = data?.[`stream${streamId}`]?.osd?.privacy;
      if (updated) {
        applyPrivacyConfig(streamId, updated);
      }
    } catch (err) {
      showAlert('danger', `Failed to update stream ${streamId} privacy: ${err.message || err}`);
    }
  }

  function formatFieldName(field) {
    return field.replace(/_/g, ' ');
  }

  function getFieldValue(el, field) {
    if (!el) return null;
    if (el.type === 'checkbox') {
      return el.checked;
    }
    const allowEmpty = el.dataset.allowEmpty === 'true' || allowEmptyFields.has(field);
    const value = el.value;
    if (value === '') {
      return allowEmpty ? '' : null;
    }
    if (numericFields.has(field)) {
      const num = Number(value);
      if (!Number.isFinite(num)) return null;
      return num;
    }
    return value;
  }

  function handleStandardChange(streamId, field) {
    const el = $(`#privacy${streamId}_${field}`);
    if (!el) return;
    const value = getFieldValue(el, field);
    if (value === null) {
      showAlert('warning', `Enter a valid value for ${formatFieldName(field)} (stream ${streamId}).`);
      return;
    }
    let payloadValue = value;
    if (field === 'font_size') {
      payloadValue = Math.max(0, Math.round(value * FontSizeScale));
    }
    sendPrivacyUpdate(streamId, { [field]: payloadValue });
  }

  function handleColorChange(streamId, key) {
    const mapEntry = colorFieldMap.find(entry => entry.key === key);
    if (!mapEntry) return;
    const colorEl = $(`#privacy${streamId}_${mapEntry.colorId}`);
    const alphaEl = $(`#privacy${streamId}_${mapEntry.alphaId}`);
    if (!colorEl || !alphaEl) return;
    const safeColor = normalizeColor(colorEl.value);
    const safeAlpha = clampAlpha(alphaEl.value);
    if (!safeColor || !Number.isInteger(safeAlpha)) {
      showAlert('warning', `Select a valid color and alpha for ${formatFieldName(key)} (stream ${streamId}).`);
      return;
    }
    const combined = buildHexColor(safeColor, safeAlpha);
    sendPrivacyUpdate(streamId, { [key]: combined });
  }

  function bindPrivacyControls() {
    streamIds.forEach(streamId => {
      standardFields.forEach(field => {
        const el = $(`#privacy${streamId}_${field}`);
        if (!el) return;
        el.addEventListener('change', () => handleStandardChange(streamId, field));
      });
      colorFieldMap.forEach(mapEntry => {
        const colorEl = $(`#privacy${streamId}_${mapEntry.colorId}`);
        const alphaEl = $(`#privacy${streamId}_${mapEntry.alphaId}`);
        if (colorEl) {
          colorEl.addEventListener('change', () => handleColorChange(streamId, mapEntry.key));
        }
        if (alphaEl) {
          alphaEl.addEventListener('change', () => handleColorChange(streamId, mapEntry.key));
        }
      });
    });
  }

  async function handleFormSubmit(event) {
    event.preventDefault();
    await persistPrudyntConfig();
  }

  function initPrivacyPage() {
    if (form) {
      form.addEventListener('submit', handleFormSubmit);
    }
    if (reloadButton) {
      reloadButton.addEventListener('click', () => loadPrivacyConfig({ silent: true }));
    }
    disablePrivacyControls();
    bindPrivacyControls();
    loadPrivacyConfig();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initPrivacyPage, { once: true });
  } else {
    initPrivacyPage();
  }
})();
