(function () {
  'use strict';

  const uiConfig = window.thinginoUIConfig || {};
  const globalConfig = uiConfig.footer || window.thinginoFooterConfig || {};
  let overlayTimerId = null;
  let logModalElements = null;

  function ensureMessageOverlay() {
    let el = $('#global-message-overlay');
    if (!el) {
      el = document.createElement('div');
      el.id = 'global-message-overlay';
      el.className = globalConfig.restartMessageClass || 'global-message-overlay';
      el.setAttribute('role', 'status');
      el.setAttribute('aria-live', 'polite');
      el.setAttribute('aria-atomic', 'true');
      document.body.appendChild(el);
    }
    return el;
  }

  function showGlobalMessage(message, variant = 'info') {
    const el = ensureMessageOverlay();
    el.textContent = message;
    el.dataset.variant = variant;
    el.classList.add('show');
    clearTimeout(overlayTimerId);
    const durationCfg = Number(globalConfig.restartMessageDuration);
    const duration = Number.isFinite(durationCfg) ? durationCfg : 4000;
    overlayTimerId = window.setTimeout(() => {
      el.classList.remove('show');
    }, Math.max(0, duration));
  }

  function wait(ms) {
    return new Promise(resolve => setTimeout(resolve, ms));
  }

  function resetShareControls(elements = null) {
    const ctx = elements || logModalElements;
    if (!ctx) return;
    const { shareBtn, shareLink } = ctx;
    if (shareBtn) {
      shareBtn.disabled = true;
      shareBtn.classList.remove('pe-none');
      shareBtn.classList.add('d-none');
      if (shareBtn.dataset.originalLabel) {
        shareBtn.innerHTML = shareBtn.dataset.originalLabel;
      }
    }
    if (shareLink) {
      shareLink.classList.add('d-none');
      shareLink.removeAttribute('href');
      shareLink.textContent = '';
    }
  }

  async function handleRestartClick(event) {
    event.preventDefault();
    const btn = event.currentTarget;
    const confirmMessage = globalConfig.restartConfirmMessage || 'Restart prudynt service?\n\nThe video stream will be interrupted for a few seconds.';
    const confirmed = await confirm(confirmMessage);
    if (!confirmed) return;

    try {
      if (btn) {
        btn.disabled = true;
        const originalLabel = btn.dataset.originalLabel || btn.innerHTML || btn.textContent;
        btn.dataset.originalLabel = originalLabel;
        btn.classList.add('pe-none');
        btn.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span><span>' + (globalConfig.restartLoadingLabel || 'Restarting…') + '</span>';
      }
      const endpoint = globalConfig.restartEndpoint || '/x/restart-prudynt.cgi';
      const method = globalConfig.restartMethod || 'GET';
      const res = await fetch(endpoint, { method });
      if (!res.ok) throw new Error('HTTP ' + res.status);

      const waitOverride = Number(globalConfig.restartWaitMs);
      const waitMs = Number.isFinite(waitOverride) ? waitOverride : 3000;
      if (waitMs > 0) await wait(waitMs);

      showGlobalMessage(globalConfig.restartSuccessMessage || 'Prudynt restarted successfully', 'success');

      if (globalConfig.restartReload === false) {
        if (btn) {
          btn.disabled = false;
          btn.classList.remove('pe-none');
          btn.innerHTML = originalLabel;
        }
      } else {
        const reloadDelayCfg = Number(globalConfig.restartReloadDelay);
        const reloadDelay = Number.isFinite(reloadDelayCfg) ? reloadDelayCfg : 800;
        window.setTimeout(() => {
          window.location.reload();
        }, Math.max(0, reloadDelay));
      }
    } catch (err) {
      console.error('Failed to restart prudynt:', err);
      const baseMessage = globalConfig.restartErrorMessage || 'Failed to restart prudynt';
      showGlobalMessage(baseMessage + ': ' + err.message, 'danger');
      if (btn) {
        btn.disabled = false;
        btn.classList.remove('pe-none');
        if (btn.dataset.originalLabel) {
          btn.innerHTML = btn.dataset.originalLabel;
        }
      }
    }
  }

  function ready(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn, { once: true });
    } else {
      fn();
    }
  }

  function createElement(tag, className, text) {
    const el = document.createElement(tag);
    if (className) el.className = className;
    if (text) el.textContent = text;
    return el;
  }

  function buildFooter() {
    const footer = document.createElement('footer');
    footer.className = globalConfig.className || 'x-small text-secondary border-top';
    footer.setAttribute('data-generated-footer', 'true');

    const container = createElement('div', 'container pt-3');
    const row = createElement('div', 'row');

    const leftCol = createElement('div', 'col col-sm-5 mb-2');

    const host = createElement('div');
    host.id = 'footer-host';
    host.textContent = globalConfig.hostName || 'unknown';

    const uptime = createElement('div');
    uptime.id = 'uptime';

    const themeWrap = document.createElement('div');
    const themeToggle = document.createElement('a');
    themeToggle.href = '#';
    themeToggle.id = 'theme-toggle';
    themeToggle.title = globalConfig.themeToggleTitle || 'Toggle theme';
    themeToggle.textContent = globalConfig.themeToggleLabel || 'Toggle theme';
    themeWrap.appendChild(themeToggle);

    const actionStack = document.createElement('div');
    actionStack.id = 'footer-action-stack';
    actionStack.className = 'mt-3 d-flex flex-column gap-2';

    leftCol.appendChild(host);
    leftCol.appendChild(uptime);
    leftCol.appendChild(themeWrap);

    const rightCol = createElement('div', 'col col-sm-7 mb-2 text-sm-end');

    const powerText = createElement('div');
    const poweredLink = document.createElement('a');
    poweredLink.href = 'https://thingino.com/';
    poweredLink.textContent = 'Thingino';
    powerText.append('Powered by ');
    powerText.appendChild(poweredLink);

    const buildInfo = createElement('div', 'small', globalConfig.buildInfo);

    rightCol.appendChild(powerText);
    rightCol.appendChild(buildInfo);

    row.appendChild(leftCol);
    row.appendChild(rightCol);
    container.appendChild(row);
    footer.appendChild(container);
    return footer;
  }

  function hostLabelText(hostname) {
    const template = globalConfig.hostTemplate || 'Connected as ${host}';
    return template.replace('${host}', hostname);
  }

  function updateHostLabel() {
    const footerHost = $('#footer-host');
    if (!footerHost) return;
    const hostname = globalConfig.host || window.location.hostname || window.location.host || 'camera.local';
    footerHost.textContent = hostLabelText(hostname);
  }

  function mountFooter() {
    const footer = buildFooter();
    const placeholder = document.querySelector('[data-app-footer]');
    if (placeholder && placeholder.parentNode) {
      placeholder.parentNode.replaceChild(footer, placeholder);
    } else if (!document.querySelector('footer[data-generated-footer="true"]')) {
      document.body.appendChild(footer);
    }
    updateHostLabel();
  }

  ready(mountFooter);

  window.thinginoFooter = {
    rebuild: mountFooter,
    updateHost: updateHostLabel,
    showMessage: showGlobalMessage,
    restartPrudynt: function() {
      handleRestartClick({ preventDefault: function() {}, currentTarget: null });
    }
  };
})();
