(function() {  const statusText = $('#statusText');
  const outputEl = $('#output');
  const actionTitle = $('#actionTitle');
  const actionSummary = $('#actionSummary');
  const params = new URLSearchParams(window.location.search);
  const actionId = params.get('action') || '';

  const ACTIONS = {
    wipeoverlay: {
      title: 'Wipe overlay partition',
      description: 'Erase all files stored in the overlay partition. Most customizations will be lost.'
    },
    fullreset: {
      title: 'Reset firmware to defaults',
      description: 'Factory reset the firmware and overlay partition. All settings and files will be removed.'
    }
  };

  const meta = ACTIONS[actionId];
  if (!meta) {
    statusText.textContent = 'Select an action from the Reset page to continue.';
    showAlert('warning', 'No reset action selected. Use the Reset page to choose what to wipe.');
    return;
  }

  actionTitle.textContent = meta.title;
  actionSummary.textContent = meta.description;

  async function requestCommand() {
    statusText.innerHTML = '<span class="spinner-border spinner-border-sm me-2" role="status" aria-hidden="true"></span>Preparing reset command...';
    try {
      const response = await fetch('/x/firmware-reset.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify({ action: actionId })
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error && payload.error.message ? payload.error.message : 'Failed to prepare reset command.';
        throw new Error(message);
      }
      const command = payload.command || payload.cmd || '';
      if (!command) {
        throw new Error('Reset command response did not include a command.');
      }
      const rebootFlag = payload.reboot === false ? false : true;
      outputEl.classList.remove('d-none');
      outputEl.dataset.cmd = command;
      outputEl.dataset.reboot = rebootFlag ? 'true' : 'false';
      statusText.textContent = 'Executing command...';
      const detail = { cmd: command, reboot: rebootFlag };
      outputEl.dispatchEvent(new CustomEvent('thingino:start-command', { detail }));
    } catch (err) {
      statusText.textContent = 'Reset aborted.';
      showAlert('danger', err.message || 'Unable to start the requested reset action.');
    }
  }

  requestCommand();
})();
