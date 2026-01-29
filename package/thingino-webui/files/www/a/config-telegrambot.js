(function() {
  'use strict';

  const form = $('#telegrambotForm');
  const enabledInput = $('#enabled');
  const tokenInput = $('#token');
  const usersInput = $('#users');
  const submitButton = $('#telegrambot_submit');
  const reloadButton = $('#telegrambot-reload');
  const restartButton = $('#telegrambot-restart');
  const addCommandBtn = $('#add-command');
  const commandsTbody = $('#commands-tbody');
  const debugOutput = $('#debug-output');

  let originalConfig = null;

  function showOverlayMessage(message, variant = 'info') {
    if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
      window.thinginoFooter.showMessage(message, variant);
      return;
    }
    const fallbackType = variant === 'danger' ? 'danger' : 'info';
    showAlert(fallbackType, message);
  }

  function toggleBusy(state, label) {
    submitButton.disabled = state;
    enabledInput.disabled = state;
    tokenInput.disabled = state;
    usersInput.disabled = state;
    if (state) {
      showBusy(label || 'Working...');
    } else {
      hideBusy();
    }
  }

  function addCommandRow(cmd) {
    const tr = document.createElement('tr');

    // Create cells
    const tdHandle = document.createElement('td');
    const tdDesc = document.createElement('td');
    const tdExec = document.createElement('td');
    const tdButton = document.createElement('td');

    // Create inputs with proper value assignment
    const inputHandle = document.createElement('input');
    inputHandle.className = 'form-control form-control-sm cmd-h';
    inputHandle.placeholder = 'start';
    inputHandle.value = cmd?.handle || '';

    const inputDesc = document.createElement('input');
    inputDesc.className = 'form-control form-control-sm cmd-d';
    inputDesc.placeholder = 'Description';
    inputDesc.value = cmd?.description || '';

    const inputExec = document.createElement('input');
    inputExec.className = 'form-control form-control-sm cmd-e';
    inputExec.placeholder = '/usr/bin/thing';
    inputExec.value = cmd?.exec || '';

    const button = document.createElement('button');
    button.type = 'button';
    button.className = 'btn btn-outline-danger btn-sm';
    button.textContent = '✕';
    button.addEventListener('click', () => tr.remove());

    // Assemble the row
    tdHandle.appendChild(inputHandle);
    tdDesc.appendChild(inputDesc);
    tdExec.appendChild(inputExec);
    tdButton.appendChild(button);

    tr.appendChild(tdHandle);
    tr.appendChild(tdDesc);
    tr.appendChild(tdExec);
    tr.appendChild(tdButton);

    commandsTbody.appendChild(tr);
  }

  function splitUsers(s) {
    return (s || '').trim().split(/\s+/).filter(Boolean);
  }

  async function loadConfig(options = {}) {
    const preserveBusy = options.preserveBusy === true;
    if (!preserveBusy) {
      toggleBusy(true, 'Loading Telegram bot settings...');
    }

    try {
      const response = await fetch('/x/json-telegrambot.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) throw new Error('Failed to load configuration');
      const data = await response.json();

      originalConfig = data;

      tokenInput.value = data.token || '';
      const users = Array.isArray(data.allowed_usernames)
        ? data.allowed_usernames.join(' ')
        : (data.users || '');
      usersInput.value = users;

      try {
        const statusResponse = await fetch('/x/ctl-telegrambot.cgi?status=1');
        const status = await statusResponse.json();
        enabledInput.checked = (status.enabled_boot === true) || (status.enabled_runtime === true);
      } catch (e) {
        enabledInput.checked = (data.enabled_boot === true) || (data.enabled === true) || (data.enabled === 'true');
      }

      commandsTbody.innerHTML = '';
      const commands = Array.isArray(data.commands) ? data.commands : [];
      commands.forEach(addCommandRow);

      if (debugOutput) {
        debugOutput.textContent = JSON.stringify(data, null, 2);
      }
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load Telegram bot configuration.');
    } finally {
      if (!preserveBusy) {
        toggleBusy(false);
      }
    }
  }

  async function saveConfig() {
    toggleBusy(true, 'Saving Telegram bot settings...');

    try {
      const token = tokenInput.value.trim();
      const users = splitUsers(usersInput.value);
      const enabled = enabledInput.checked;
      const commands = Array.from(commandsTbody.querySelectorAll('tr')).map(tr => ({
        handle: tr.querySelector('.cmd-h').value.trim(),
        description: tr.querySelector('.cmd-d').value.trim(),
        exec: tr.querySelector('.cmd-e').value.trim()
      })).filter(c => c.handle && c.exec);

      const payload = JSON.parse(JSON.stringify(originalConfig || {}));
      payload.token = token;
      payload.allowed_usernames = users;
      payload.commands = commands;
      delete payload.enabled;

      const response = await fetch('/x/json-telegrambot.cgi', {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });

      if (!response.ok) throw new Error('HTTP ' + response.status);

      try {
        await fetch('/x/ctl-telegrambot.cgi?enabled=' + (enabled ? 1 : 0));
      } catch (e) {
        console.warn('Failed to set enabled state:', e);
      }

      showAlert('', '');
      showOverlayMessage('Telegram bot configuration saved.', 'success');
      await loadConfig({ preserveBusy: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save Telegram bot configuration.');
    } finally {
      toggleBusy(false);
    }
  }

  form.addEventListener('submit', function(ev) {
    ev.preventDefault();
    saveConfig();
  });

  addCommandBtn.addEventListener('click', () => addCommandRow());

  if (reloadButton) {
    reloadButton.addEventListener('click', async () => {
      try {
        reloadButton.disabled = true;
        await loadConfig();
        showAlert('info', 'Telegram bot settings reloaded from camera.', 3000);
      } catch (err) {
        showAlert('danger', 'Failed to reload settings.');
      } finally {
        reloadButton.disabled = false;
      }
    });
  }

  if (restartButton) {
    restartButton.addEventListener('click', async () => {
      try {
        restartButton.disabled = true;
        showBusy('Restarting Telegram bot service...');
        const response = await fetch('/x/ctl-telegrambot.cgi?restart=1');
        if (!response.ok) throw new Error('HTTP ' + response.status);
        showOverlayMessage('Telegram bot service restarted.', 'success');
      } catch (err) {
        showAlert('danger', 'Failed to restart Telegram bot service.');
      } finally {
        hideBusy();
        restartButton.disabled = false;
      }
    });
  }

  loadConfig();
})();
