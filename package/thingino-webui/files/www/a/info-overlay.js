(function() {  const usageLabel = $('#overlayUsageLabel');
  const progressBar = $('#overlayProgressBar');
  const listingEl = $('#overlayListing');
  const refreshBtn = $('#refreshOverlay');
  const summary = $('#overlaySummary');
  const stateClasses = ['bg-primary', 'bg-danger', 'bg-warning', 'bg-success', 'bg-info'];



  function decodeListing(payload) {
    if (!payload || (typeof payload !== 'object')) return '';
    const encoded = typeof payload.listing_base64 === 'string' ? payload.listing_base64.trim() : '';
    if (!encoded) {
      return typeof payload.listing === 'string' ? payload.listing : '';
    }
    return decodeBase64String(encoded) || (typeof payload.listing === 'string' ? payload.listing : '');
  }

  function setUsage(data) {
    const usage = data && data.usage ? data.usage : {};
    const label = usage.label || '--';
    const percent = typeof usage.percent === 'number' ? usage.percent : 0;
    const state = usage.state || 'primary';

    usageLabel.textContent = label;
    progressBar.style.width = `${Math.max(0, Math.min(100, percent))}%`;
    progressBar.setAttribute('aria-valuenow', percent);
    progressBar.classList.remove(...stateClasses);
    progressBar.classList.add(`bg-${state}`);

    summary.classList.toggle('alert-danger', state === 'danger');
    summary.classList.toggle('alert-primary', state !== 'danger');
  }

  function setListing(text) {
    listingEl.textContent = text || 'No files reported.';
  }

  async function loadOverlay() {
    showBusy('Loading overlay information...');
    showAlert();
    try {
      const response = await fetch('/x/info-overlay.cgi', { headers: { 'Accept': 'application/json' } });
      const data = await response.json();
      if (!response.ok || (data && data.error)) {
        const message = data && data.error && data.error.message ? data.error.message : 'Failed to load overlay usage.';
        throw new Error(message);
      }
      setUsage(data);
      setListing(decodeListing(data) || 'No files reported.');
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load overlay stats.');
      listingEl.textContent = 'Unable to load directory listing.';
    } finally {
      hideBusy();
    }
  }

  refreshBtn.addEventListener('click', ev => {
    ev.preventDefault();
    loadOverlay();
  });

  loadOverlay();
})();
