(function() {
  const form = $('#diagnostic-form');
  const submitBtn = $('#generate-btn');
  const uploadBtn = $('#upload-btn');
  const downloadBtn = $('#download-btn');
  const directUploadCheckbox = $('#direct-upload');
  const resultWrapper = $('#diagnostic-result');
  const linkRow = $('#diagnostic-link-row');
  const resultLink = $('#diagnostic-link');
  const resultOutput = $('#diagnostic-output');
  const copyBtn = $('#diagnostic-copy-icon');
  let lastLink = '';
  let diagnosticData = '';

  const extractLinkFromText = (text) => {
    if (typeof text !== 'string') return '';
    const match = text.match(/https?:\/\/[^\s]+/i);
    if (!match) return '';
    return match[0].replace(/[)\],.;]+$/, '');
  };

  const showAlert = (type, message) => {
    if (!message) return;
    dispatchAlert(type, message);
  };

  function dispatchAlert(type, message) {
    if (typeof window.showAlert === 'function') {
      window.showAlert(type, message);
    } else if (message) {
      console[type === 'danger' ? 'error' : 'log'](message);
    }
  }

  const toggleBusyState = (isBusy) => {
    submitBtn.disabled = isBusy;
    if (isBusy) {
      submitBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Generating...';
      showBusy('Generating diagnostic log...');
    } else {
      submitBtn.innerHTML = 'Generate diagnostic log';
      hideBusy();
    }
  };

  const renderResult = (payload) => {
    // Handle direct upload response with link
    if (payload.link) {
      lastLink = payload.link;
      if (resultLink) resultLink.href = lastLink;
      if (resultLink) resultLink.textContent = lastLink;
      if (linkRow) linkRow.classList.remove('d-none');
      if (resultOutput) resultOutput.classList.add('d-none');
      if (uploadBtn) uploadBtn.classList.add('d-none');
      if (downloadBtn) downloadBtn.classList.add('d-none');
      showAlert('success', 'Diagnostic log uploaded successfully.');
      if (resultWrapper) resultWrapper.classList.remove('d-none');
      return;
    }

    // Handle base64 encoded output following the same pattern as info.js
    let rawOutput = '';
    const encoded = typeof payload.output_b64 === 'string' ? payload.output_b64.trim() : '';
    const fallback = typeof payload.output === 'string' ? payload.output : '';

    if (encoded) {
      const decoded = decodeBase64String(encoded);
      rawOutput = decoded || fallback || '[Unable to decode diagnostic output]';
    } else {
      rawOutput = fallback;
    }

    rawOutput = rawOutput.trim();
    diagnosticData = rawOutput;

    // Show diagnostic content or display success message
    if (rawOutput) {
      if (resultOutput) {
        resultOutput.textContent = rawOutput;
        resultOutput.classList.remove('d-none');
      }
      if (uploadBtn) uploadBtn.classList.remove('d-none');
      if (downloadBtn) downloadBtn.classList.remove('d-none');
      showAlert('success', 'Diagnostic log generated successfully.');
    } else {
      if (resultOutput) {
        resultOutput.textContent = '';
        resultOutput.classList.add('d-none');
      }
      if (uploadBtn) uploadBtn.classList.add('d-none');
      if (downloadBtn) downloadBtn.classList.add('d-none');
      showAlert('success', 'Diagnostic log generated.');
    }

    // Hide the upload success section initially
    if (linkRow) linkRow.classList.add('d-none');

    // Show the result wrapper
    if (resultWrapper) resultWrapper.classList.remove('d-none');
  };

  copyBtn.addEventListener('click', async () => {
    if (!lastLink) return;
    const clipboard = window.thinginoClipboard;
    if (!clipboard || typeof clipboard.copy !== 'function') {
      showAlert('danger', 'Clipboard support is not available in this browser.');
      setTimeout(() => showAlert('', ''), 4000);
      return;
    }
    try {
      await clipboard.copy(lastLink);
      linkRow.classList.add('copied');
      copyBtn.classList.add('copied');
      resultLink.classList.add('copied');
    } catch (err) {
      showAlert('danger', 'Unable to copy the link.');
      setTimeout(() => showAlert('', ''), 4000);
    }
  });

  copyBtn.addEventListener('animationend', () => {
    linkRow.classList.remove('copied');
    copyBtn.classList.remove('copied');
    resultLink.classList.remove('copied');
  });

  form.addEventListener('submit', async (event) => {
    event.preventDefault();
    showAlert('', '');

    // Clear previous results
    if (resultWrapper) resultWrapper.classList.add('d-none');
    if (resultOutput) {
      resultOutput.textContent = '';
      resultOutput.classList.add('d-none');
    }
    if (linkRow) linkRow.classList.add('d-none');
    if (uploadBtn) uploadBtn.classList.add('d-none');
    if (downloadBtn) downloadBtn.classList.add('d-none');
    diagnosticData = '';
    lastLink = '';

    toggleBusyState(true);
    try {
      const params = new URLSearchParams();

      if (directUploadCheckbox && directUploadCheckbox.checked) {
        params.set('direct_upload', 'true'); // Upload directly and return URL
      } else {
        params.set('generate_only', 'true'); // Generate locally without upload
      }

      const response = await fetch('/x/info-diagnostic.cgi', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        cache: 'no-store',
        body: params.toString()
      });
      const data = await response.json();
      if (!response.ok || data.error) {
        const message = data?.error?.message || `Failed to generate diagnostics (HTTP ${response.status})`;
        throw new Error(message);
      }
      renderResult(data);
    } catch (err) {
      showAlert('danger', err.message || 'Failed to generate diagnostic log.');
    } finally {
      toggleBusyState(false);
    }
  });

  // Upload to server button handler
  uploadBtn.addEventListener('click', async () => {
    if (!diagnosticData) {
      showAlert('warning', 'No diagnostic data to upload.');
      return;
    }

    uploadBtn.disabled = true;
    uploadBtn.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status"></span>Uploading...';

    try {
      const params = new URLSearchParams();
      params.set('upload_data', diagnosticData);
      const response = await fetch('/x/info-diagnostic.cgi', {
        method: 'POST',
        headers: {'Content-Type': 'application/x-www-form-urlencoded'},
        cache: 'no-store',
        body: params.toString()
      });
      const data = await response.json();
      if (!response.ok || data.error) {
        const message = data?.error?.message || `Upload failed (HTTP ${response.status})`;
        throw new Error(message);
      }
      const link = data.link;
      if (link) {
        lastLink = link;
        if (resultLink) resultLink.href = lastLink;
        if (resultLink) resultLink.textContent = lastLink;
        if (linkRow) linkRow.classList.remove('d-none');
        showAlert('success', 'Diagnostic log uploaded successfully.');
      } else {
        throw new Error('Upload successful but no link received.');
      }
    } catch (err) {
      showAlert('danger', err.message || 'Upload failed.');
    } finally {
      uploadBtn.disabled = false;
      uploadBtn.innerHTML = '<i class="bi bi-cloud-upload me-1"></i>Upload to Server';
    }
  });

  // Download button handler
  downloadBtn.addEventListener('click', () => {
    if (!diagnosticData) {
      showAlert('danger', 'No diagnostic data to download.');
      return;
    }

    try {
      const timestamp = new Date().toISOString().replace(/[:.]/g, '-').substring(0, 19);
      const filename = `thingino-diag-${timestamp}.log`;

      const blob = new Blob([diagnosticData], { type: 'text/plain' });
      const url = URL.createObjectURL(blob);

      const a = document.createElement('a');
      a.href = url;
      a.download = filename;
      document.body.appendChild(a);
      a.click();

      document.body.removeChild(a);
      URL.revokeObjectURL(url);

      showAlert('success', `Diagnostic log downloaded as ${filename}`);
    } catch (err) {
      showAlert('danger', 'Failed to download diagnostic log.');
    }
  });
})();
