(function() {
  const API_URL = '/x/tool-ping-trace.cgi';
  const form = $('#networkForm');
  const actionSelect = $('#action');
  const actionHelp = $('#actionHelp');
  const targetInput = $('#target');
  const interfaceSelect = $('#interface');
  const packetSizeInput = $('#packetSize');
  const countInput = $('#count');
  const runButton = $('#runTest');
  const clearButton = $('#btnClear');
  const copyButton = $('#btnCopy');  const statusText = $('#streamStatus');
  const commandHeading = $('#commandHeading');
  const outputEl = $('#output');

  let buttonDefaultHtml = runButton.innerHTML;
  let metadata = null;
  let running = false;
  const actionDescriptions = new Map();

  function setRunningState(state) {
    running = state;
    runButton.disabled = state;
    runButton.innerHTML = state
      ? '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Running...'
      : buttonDefaultHtml;
  }

  function updateStatus(text, tone = 'secondary') {
    statusText.className = `text-${tone} mb-0`;
    statusText.textContent = text;
  }

  function clearOutput() {
    outputEl.textContent = '';
    outputEl.dataset.cmd = '';
    outputEl.dataset.stream = '';
    outputEl.dataset.encoded = '';
    copyButton.disabled = true;
    commandHeading.textContent = 'Diagnostics output';
  }

  function populateInterfaces(list) {
    interfaceSelect.innerHTML = '';
    (list || ['auto']).forEach(value => {
      const option = document.createElement('option');
      option.value = value;
      option.textContent = value;
      interfaceSelect.appendChild(option);
    });
    interfaceSelect.value = (metadata && metadata.defaults && metadata.defaults.interface) || 'auto';
  }

  function populateActions(actions = []) {
    actionDescriptions.clear();
    actionSelect.innerHTML = '';
    actions.forEach(action => {
      actionDescriptions.set(action.id, action.description || '');
      const option = document.createElement('option');
      option.value = action.id;
      option.textContent = action.label;
      actionSelect.appendChild(option);
    });
    const defaultAction = (metadata && metadata.defaults && metadata.defaults.action) || (actions[0] && actions[0].id) || 'ping';
    actionSelect.value = defaultAction;
    updateActionHelp();
  }

  function updateActionHelp() {
    const actionId = actionSelect.value;
    const description = actionDescriptions.get(actionId) || 'Run a diagnostic test.';
    actionHelp.textContent = description;
  }

  async function loadMetadata() {
    updateStatus('Loading metadata…', 'secondary');
    try {
      const response = await fetch(API_URL, { cache: 'no-store' });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error && payload.error.message ? payload.error.message : 'Unable to load metadata.';
        throw new Error(message);
      }
      metadata = payload;
      populateActions(payload.actions || []);
      populateInterfaces(payload.interfaces || ['auto']);
      const defaults = payload.defaults || {};
      packetSizeInput.value = defaults.packet_size || packetSizeInput.value || packetSizeInput.min;
      countInput.value = defaults.count || countInput.value || countInput.min;
      const limits = payload.limits || {};
      if (limits.packet_size) {
        packetSizeInput.min = limits.packet_size.min;
        packetSizeInput.max = limits.packet_size.max;
      }
      if (limits.count) {
        countInput.min = limits.count.min;
        countInput.max = limits.count.max;
      }
      updateStatus('Metadata loaded. Ready to run tests.', 'success');
    } catch (err) {
      updateStatus('Metadata unavailable. Some features may not work.', 'danger');
      showAlert('danger', err.message || 'Failed to load metadata for this tool.');
    }
  }

  async function submitForm(ev) {
    ev.preventDefault();
    if (running) return;
    clearOutput();
    setRunningState(true);
    updateStatus('Preparing command…', 'info');

    const params = new URLSearchParams({
      action: actionSelect.value,
      target: targetInput.value.trim(),
      interface: interfaceSelect.value || 'auto',
      packet_size: packetSizeInput.value,
      count: countInput.value
    });

    try {
      const response = await fetch(API_URL, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: params.toString()
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error && payload.error.message ? payload.error.message : 'Unable to start the requested test.';
        throw new Error(message);
      }
      const command = payload.command || payload.cmd;
      const stream = payload.stream;
      const encoded = payload.encoded;
      if (!command) {
        throw new Error('Response did not include a command to run.');
      }
      commandHeading.textContent = `# ${command}`;
      updateStatus('Starting command…', 'info');
      outputEl.dataset.cmd = command;
      outputEl.dataset.stream = stream || '';
      outputEl.dataset.encoded = encoded || '';
      outputEl.dispatchEvent(new CustomEvent('thingino:start-command', {
        detail: { cmd: command, stream, encoded }
      }));
    } catch (err) {
      setRunningState(false);
      updateStatus('Unable to run test.', 'danger');
      showAlert('danger', err.message || 'Network Test request failed.');
    }
  }

  function copyOutput() {
    const clipboard = window.thinginoClipboard;
    if (!clipboard || typeof clipboard.copy !== 'function') {
      showAlert('warning', 'Clipboard copy is not supported in this browser.');
      return;
    }
    if (!outputEl.textContent.trim()) return;
    clipboard.copy(outputEl.textContent)
      .then(() => {
        copyButton.innerHTML = '<i class="bi bi-clipboard-check me-1"></i>Copied';
        copyButton.classList.replace('btn-outline-secondary', 'btn-success');
        setTimeout(() => {
          copyButton.innerHTML = '<i class="bi bi-clipboard me-1"></i>Copy';
          copyButton.classList.replace('btn-success', 'btn-outline-secondary');
        }, 1500);
      })
      .catch(() => {
        showAlert('warning', 'Unable to copy output to clipboard on this browser.');
      });
  }

  actionSelect.addEventListener('change', updateActionHelp);
  form.addEventListener('submit', submitForm);
  clearButton.addEventListener('click', () => {
    clearOutput();
    updateStatus('Output cleared. Ready for a new test.', 'secondary');
    clearAlerts();
  });
  copyButton.addEventListener('click', copyOutput);

  outputEl.addEventListener('thingino:command-start', ev => {
    const cmd = (ev.detail && ev.detail.cmd) || outputEl.dataset.cmd || '';
    commandHeading.textContent = cmd ? `# ${cmd}` : 'Diagnostics output';
    copyButton.disabled = true;
    updateStatus('Running test and streaming output…', 'info');
  });

  outputEl.addEventListener('thingino:command-finished', () => {
    setRunningState(false);
    copyButton.disabled = !outputEl.textContent.trim();
    updateStatus('Command finished.', 'success');
  });

  loadMetadata();
})();
