(function() {
  'use strict';

  const endpoint = '/x/json-system-usage.cgi';
  const refreshButton = $('#usage-refresh');
  const spinner = $('#usage-spinner');
  const content = $('#usage-content');
  const errorAlert = $('#usage-error');
  const alertArea = $('#usage-alert');

  function showSpinner(active) {
    if (!spinner) return;
    spinner.classList.toggle('d-none', !active);
  }

  function showContent(active) {
    if (!content) return;
    content.classList.toggle('d-none', !active);
  }

  function showError(message) {
    if (!errorAlert) return;
    if (!message) {
      errorAlert.classList.add('d-none');
      errorAlert.textContent = '';
      return;
    }
    errorAlert.textContent = message;
    errorAlert.classList.remove('d-none');
  }

  function showToast(variant, message) {
    if (!alertArea || !message) return;
    const alert = document.createElement('div');
    alert.className = `alert alert-${variant} alert-dismissible fade show`;
    alert.setAttribute('role', 'alert');
    alert.textContent = message;
    const dismissBtn = document.createElement('button');
    dismissBtn.type = 'button';
    dismissBtn.className = 'btn-close';
    dismissBtn.setAttribute('aria-label', 'Close');
    dismissBtn.addEventListener('click', () => alert.remove());
    alert.appendChild(dismissBtn);
    alertArea.appendChild(alert);
    setTimeout(() => {
      alert.classList.remove('show');
      setTimeout(() => alert.remove(), 200);
    }, 3500);
  }

  function updateUsageSummary(id, text) {
    const el = $('#' + id);
    if (!el) return;
    el.textContent = text;
  }

  function formatUsageSummary(section) {
    if (!section) return 'No data available';
    const total = Number(section.total) || 0;
    const free = Number(section.free);
    const used = Number(section.used);
    if (!total) return 'No data available';
    const resolvedFree = Number.isFinite(free) ? Math.max(0, free) : Math.max(0, total - (Number.isFinite(used) ? used : 0));
    const resolvedUsed = Math.max(0, total - resolvedFree);
    const percent = total ? Math.round((resolvedUsed / total) * 100) : 0;
    return resolvedFree + ' KiB free (' + percent + '% used)';
  }

  function updateUsageProgress(selector, value, total, label) {
    if (typeof window.setProgressBar !== 'function') return;
    window.setProgressBar(selector, value, total, label);
  }

  function updateLegend(id, items) {
    const el = $('#' + id);
    if (!el) return;
    el.innerHTML = '';
    
    items.forEach(item => {
      const legendItem = document.createElement('span');
      legendItem.className = 'd-flex align-items-center gap-1';
      
      const colorBox = document.createElement('span');
      colorBox.style.display = 'inline-block';
      colorBox.style.width = '12px';
      colorBox.style.height = '12px';
      colorBox.style.backgroundColor = item.color;
      colorBox.style.borderRadius = '2px';
      
      const total = item.total || 1;
      const percentage = total > 0 ? Math.round((item.value / total) * 100) : 0;
      
      const text = document.createElement('span');
      text.textContent = `${item.label}: ${item.value} KiB (${percentage}%)`;
      
      legendItem.appendChild(colorBox);
      legendItem.appendChild(text);
      el.appendChild(legendItem);
    });
  }

  function updateUsageView(data = {}) {
    const memory = data.memory || {};
    const overlay = data.overlay || {};
    const extras = data.extras || {};

    // Calculate memory components
    const memTotal = memory.total || 0;
    const memFree = memory.free || 0;
    const memActive = memory.active || 0;
    const memBuffers = memory.buffers || 0;
    const memCached = memory.cached || 0;
    
    // Calculate "other" memory (shared, slab, etc)
    const memUsed = memTotal - memFree;
    const memAccountedFor = memActive + memBuffers + memCached;
    const memOther = Math.max(0, memUsed - memAccountedFor);
    
    // Update headers with total amounts
    const memoryTitle = $('#usageMemorySection h6');
    if (memoryTitle) memoryTitle.textContent = `Memory (${memTotal} KiB)`;
    
    const overlayTitle = $('#usageOverlaySection h6');
    if (overlayTitle) overlayTitle.textContent = `Overlay partition (${overlay.total || 0} KiB)`;
    
    const extrasTitle = $('#usageExtrasSection h6');
    if (extrasTitle) extrasTitle.textContent = `Extras storage (${extras.total || 0} KiB)`;
    
    updateUsageProgress('#pb-memory-active', memActive, memTotal, 'Memory Active');
    updateUsageProgress('#pb-memory-buffers', memBuffers, memTotal, 'Memory Buffers');
    updateUsageProgress('#pb-memory-cached', memCached, memTotal, 'Memory Cached');
    updateUsageProgress('#pb-memory-other', memOther, memTotal, 'Memory Other');
    
    updateLegend('memory-legend', [
      { color: '#ff6b6b', label: 'Active', value: memActive, total: memTotal },
      { color: '#ffb347', label: 'Buffers', value: memBuffers, total: memTotal },
      { color: '#4ecdc4', label: 'Cached', value: memCached, total: memTotal },
      { color: '#95a5a6', label: 'Other', value: memOther, total: memTotal }
    ]);
    
    updateUsageSummary('usage-memory-summary', formatUsageSummary({
      total: memTotal,
      free: memFree,
      used: memUsed
    }));

    updateUsageProgress('#pb-overlay-used', overlay.used || 0, overlay.total || 1, 'Overlay Usage');
    updateLegend('overlay-legend', [
      { color: '#b084f7', label: 'Used', value: overlay.used || 0, total: overlay.total || 1 }
    ]);
    updateUsageSummary('usage-overlay-summary', formatUsageSummary(overlay));

    updateUsageProgress('#pb-extras-used', extras.used || 0, extras.total || 1, 'Extras Usage');
    updateLegend('extras-legend', [
      { color: '#4a90e2', label: 'Used', value: extras.used || 0, total: extras.total || 1 }
    ]);
    updateUsageSummary('usage-extras-summary', formatUsageSummary(extras));

    const updatedAt = $('#usage-updated-at');
    if (updatedAt) {
      updatedAt.textContent = 'Updated ' + new Date().toLocaleString();
    }
  }

  async function fetchUsageData() {
    const response = await fetch(endpoint, { headers: { 'Accept': 'application/json' } });
    if (!response.ok) {
      throw new Error('Request failed with status ' + response.status);
    }
    const payload = await response.json();
    const data = payload && payload.data;
    if (!data || typeof data !== 'object') {
      throw new Error('Usage response missing data.');
    }
    return data;
  }

  async function loadUsage(options = {}) {
    const { silent = false } = options;
    if (!silent) {
      showError('');
      showContent(false);
      showSpinner(true);
    } else if (refreshButton) {
      refreshButton.disabled = true;
    }

    try {
      const data = await fetchUsageData();
      updateUsageView(data);
      showSpinner(false);
      showContent(true);
      if (silent) {
        showToast('success', 'System usage refreshed.');
      }
    } catch (err) {
      showContent(false);
      showSpinner(false);
      showError(err && err.message ? err.message : 'Unable to load usage data.');
    } finally {
      if (silent && refreshButton) {
        refreshButton.disabled = false;
      }
    }
  }

  function initUsagePage() {
    if (refreshButton) {
      refreshButton.addEventListener('click', () => loadUsage({ silent: true }));
    }
    loadUsage();
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', initUsagePage, { once: true });
  } else {
    initUsagePage();
  }
})();
