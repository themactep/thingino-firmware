const API_URL = '/x/json-config-zerotier.cgi';

let networks = {}; // Store network configs: { nwid: { name, on_boot } }
let ztStatus = { supported: false, running: false, online: false };
let connectionStartTime = null; // Track when connection was initiated
let isConnecting = false; // Track if we're actively trying to connect
let isDisconnecting = false; // Track if we're actively trying to disconnect

function showMessage(message, variant = 'info') {
  if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
    window.thinginoFooter.showMessage(message, variant);
    return;
  }
  console.log(`[${variant}] ${message}`);
}

// Load all data
async function loadData() {
  try {
    const response = await fetch(API_URL);
    if (!response.ok) throw new Error('Failed to load configuration');
    const data = await response.json();

    if (data.error) throw new Error(data.error.message || 'Not connected');

    // Parse config - single network for now
    const newNetworks = {};
    if (data.config && data.config.nwid) {
      newNetworks[data.config.nwid] = {
        name: data.config.network_name || data.config.nwid,
        on_boot: data.config.enabled === true
      };
    }

    const newStatus = data.status || { supported: false };

    networks = newNetworks;
    ztStatus = newStatus;

    updateUI();
  } catch (error) {
    console.error('Error loading data:', error);
    showMessage('Error loading configuration: ' + error.message, 'danger');
  }
}

// Connect to a network
async function connectNetwork(nwid) {
  try {
    isConnecting = true;
    connectionStartTime = Date.now();
    const response = await fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'start' })
    });

    if (!response.ok) throw new Error('Failed to connect');
    const data = await response.json();
    if (data.error) throw new Error(data.error.message);

    showMessage('Connecting to network...', 'info');

    // Start polling for connection status
    pollConnectionStatus();
  } catch (error) {
    isConnecting = false;
    connectionStartTime = null;
    showMessage('Error: ' + error.message, 'danger');
    loadData(); // Refresh UI to reset button state
  }
}

// Disconnect from network
async function disconnectNetwork(nwid) {
  try {
    isDisconnecting = true;
    connectionStartTime = null;
    const response = await fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'stop' })
    });

    if (!response.ok) throw new Error('Failed to disconnect');
    const data = await response.json();
    if (data.error) throw new Error(data.error.message);

    showMessage('Disconnected from network', 'warning');
    await loadData();
    isDisconnecting = false;
  } catch (error) {
    isDisconnecting = false;
    showMessage('Error: ' + error.message, 'danger');
    loadData(); // Refresh UI to reset button state
  }
}

// Poll for connection status until connected or timeout
let pollInterval = null;
function pollConnectionStatus() {
  if (pollInterval) clearInterval(pollInterval);

  pollInterval = setInterval(async () => {
    await loadData();

    // Check if connected successfully
    if (ztStatus.networkStatus === 'OK') {
      clearInterval(pollInterval);
      pollInterval = null;
      connectionStartTime = null;
      isConnecting = false;
      showMessage('Connected successfully!', 'success');
      return;
    }

    // Check for timeout (30 seconds)
    if (connectionStartTime && (Date.now() - connectionStartTime > 30000)) {
      clearInterval(pollInterval);
      pollInterval = null;
      connectionStartTime = null;
      isConnecting = false;
      await loadData();
      return;
    }
  }, 2000); // Poll every 2 seconds
}

// Remove network from config
async function removeNetwork(nwid) {
  const confirmed = await confirm('Remove this network? This will disconnect and delete the configuration.');
  if (!confirmed) {
    return;
  }

  try {
    const response = await fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ action: 'leave' })
    });

    if (!response.ok) throw new Error('Failed to remove network');
    const data = await response.json();
    if (data.error) throw new Error(data.error.message);

    showMessage('Network removed', 'success');

    // Clear networks and reload immediately
    networks = {};
    updateUI();

    // Reload from backend to ensure sync
    setTimeout(() => loadData(), 500);
  } catch (error) {
    showMessage('Error: ' + error.message, 'danger');
  }
}

// Toggle autostart for network
async function toggleAutostart(nwid, on_boot) {
  try {
    const networkName = networks[nwid]?.name || nwid;

    const response = await fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        enabled: on_boot,
        nwid: nwid,
        network_name: networkName
      })
    });

    if (!response.ok) throw new Error('Failed to update');
    const data = await response.json();
    if (data.error) throw new Error(data.error.message);

    networks[nwid].on_boot = on_boot;
    showMessage(`Auto-start ${on_boot ? 'enabled' : 'disabled'}`, 'success');
    await loadData();
  } catch (error) {
    showMessage('Error: ' + error.message, 'danger');
    loadData();
  }
}

// Add new network
async function addNetwork() {
  const nwidInput = $('#new-network-id');
  const autostartInput = $('#new-network-autostart');

  const nwid = nwidInput.value.trim();

  if (!nwid) {
    showMessage('Please enter a network ID', 'danger');
    return;
  }

  if (nwid.length !== 16 || !/^[0-9a-fA-F]{16}$/.test(nwid)) {
    showMessage('Network ID must be exactly 16 hexadecimal characters', 'danger');
    return;
  }

  // Check if network already exists
  if (networks[nwid]) {
    showMessage('This network is already in your list', 'warning');
    return;
  }

  try {
    const response = await fetch(API_URL, {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({
        nwid: nwid,
        name: nwid,
        on_boot: autostartInput.checked
      })
    });

    if (!response.ok) throw new Error('Failed to save network');
    const data = await response.json();
    if (data.error) throw new Error(data.error.message);

    showMessage('Network added successfully', 'success');

    // Reset form
    nwidInput.value = '';
    autostartInput.checked = false;

    await loadData();
    return true; // Indicate success
  } catch (error) {
    showMessage('Error: ' + error.message, 'danger');
    return false; // Indicate failure
  }
}

// Render networks list
function renderNetworks() {
  const listContainer = $('#networks-list');

  if (Object.keys(networks).length === 0) {
    return;
  }

  let html = '';

  for (const [nwid, config] of Object.entries(networks)) {
    // Check if this network is connected (running, online, and status shows OK/etc)
    const isConnected = ztStatus.running && ztStatus.online && ztStatus.networkStatus;
    const liveNetworkName = ztStatus.networkName || config.name;
    const networkStatus = ztStatus.networkStatus || '';
    const ip = ztStatus.ip || '';

    // Build display title: "NWID (Name)" or just "NWID"
    const displayTitle = liveNetworkName && liveNetworkName !== nwid
      ? `${nwid} (${liveNetworkName})`
      : nwid;

    // Auto-clear flags if state changed or timed out
    if (isDisconnecting && !ztStatus.running) {
      isDisconnecting = false;
    }
    if (isConnecting) {
      // Clear if successfully connected
      if (ztStatus.networkStatus === 'OK') {
        isConnecting = false;
      }
      // Or if we're waiting for authorization (network joined but not authorized)
      else if (ztStatus.networkStatus === 'ACCESS_DENIED' || ztStatus.networkStatus === 'REQUESTING_CONFIGURATION') {
        isConnecting = false;
      }
      // Or if timed out
      else if (connectionStartTime && (Date.now() - connectionStartTime > 30000)) {
        isConnecting = false;
      }
    }

    let statusText = '';

    // Check for timeout (30 seconds)
    const hasTimedOut = connectionStartTime && (Date.now() - connectionStartTime > 30000);

    if (isConnected && networkStatus === 'OK') {
      connectionStartTime = null; // Reset timeout on success
      statusText = ip ? `IP: ${ip}` : '';
    } else if (isConnected && (networkStatus === 'ACCESS_DENIED' || networkStatus === 'REQUESTING_CONFIGURATION')) {
      statusText = `<a href="https://central.zerotier.com/network/${nwid}" target="_blank" rel="noopener">Authorize in ZeroTier Central</a>`;
    } else if (ztStatus.running && ztStatus.online && !networkStatus) {
      // Service is running and online but no network status yet (still joining)
      statusText = 'Establishing connection';
    } else if (ztStatus.running && !ztStatus.online) {
      // Service running but not online yet (connecting to ZeroTier servers)
      statusText = 'Initializing service';
    } else if (hasTimedOut) {
      connectionStartTime = null;
      statusText = 'Network may not exist or be unreachable. <a href="javascript:void(0)" class="retry-connection" data-nwid="' + nwid + '">Retry</a>';
    } else if (isConnected) {
      statusText = 'Initializing';
    } else {
      connectionStartTime = null;
      statusText = '';
    }

    html += `
      <h4>${displayTitle}</h4>
      <small>${statusText ? `${statusText}` : 'Not connected'}</small>
      <p class="form-check form-switch mb-3">
        <input class="form-check-input autostart-toggle" type="checkbox" id="autostart-${nwid}" data-nwid="${nwid}" ${config.on_boot ? 'checked' : ''}>
        <label class="form-check-label" for="autostart-${nwid}">Auto-start on boot</label>
      </p>
      <button type="button" class="btn ${isConnected ? 'btn-warning' : 'btn-primary'} network-toggle-btn" data-nwid="${nwid}" ${(isConnecting || isDisconnecting) ? 'disabled' : ''} style="min-width: 145px;">
        <span class="button-text">${
          isDisconnecting ? 'Disconnecting...' :
            isConnecting ? (ztStatus.running && ztStatus.online ? 'Joining network...' : (ztStatus.running ? 'Initializing...' : 'Connecting...')) :
              (isConnected ? 'Disconnect' : 'Connect')}</span>
       <span class="spinner-border spinner-border-sm ms-2 ${(isConnecting || isDisconnecting) ? '' : 'd-none'}" role="status"></span>
      </button>
      ${!isConnected && !isConnecting ? `<button type="button" class="btn btn-danger remove-network" data-nwid="${nwid}"><i class="bi bi-trash"></i> Remove Network</button>` : ''}
    `;
  }

  listContainer.innerHTML = html;

  // Attach event listeners
  document.querySelectorAll('.network-toggle-btn').forEach(btn => {
    btn.addEventListener('click', async (e) => {
      const button = e.currentTarget;
      const nwid = button.dataset.nwid;
      const buttonText = button.querySelector('.button-text');
      const spinner = button.querySelector('.spinner-border');
      const isCurrentlyConnected = buttonText.textContent === 'Disconnect';

      // Show spinner and disable button
      button.disabled = true;
      spinner.classList.remove('d-none');

      try {
        if (isCurrentlyConnected) {
          await disconnectNetwork(nwid);
        } else {
          await connectNetwork(nwid);
        }
      } catch (error) {
        // Error already shown in connect/disconnect functions
        // Re-enable button on error
        button.disabled = false;
        spinner.classList.add('d-none');
      }
      // Note: Button will be re-enabled when loadData() updates UI
    });
  });

  document.querySelectorAll('.autostart-toggle').forEach(toggle => {
    toggle.addEventListener('change', async (e) => {
      const nwid = e.target.dataset.nwid;
      await toggleAutostart(nwid, e.target.checked);
    });
  });

  document.querySelectorAll('.remove-network').forEach(btn => {
    btn.addEventListener('click', (e) => {
      const nwid = e.target.closest('button').dataset.nwid;
      removeNetwork(nwid);
    });
  });

  // Retry connection links
  document.querySelectorAll('.retry-connection').forEach(link => {
    link.addEventListener('click', async (e) => {
      e.preventDefault();
      const nwid = e.target.dataset.nwid;
      await disconnectNetwork(nwid);
      setTimeout(() => connectNetwork(nwid), 1000);
    });
  });

  // Fix inconsistent state links
  document.querySelectorAll('.fix-inconsistent').forEach(link => {
    link.addEventListener('click', async (e) => {
      e.preventDefault();
      const nwid = e.target.dataset.nwid;
      await disconnectNetwork(nwid);
      setTimeout(() => connectNetwork(nwid), 1000);
    });
  });
}

// Update UI
function updateUI() {
  if (!ztStatus.supported) {
    $('#zt-not-supported').classList.remove('d-none');
    return;
  }

  renderNetworks();

  // Show/hide add network button based on whether a network exists
  const addNetwork = $('#add-network');
  if (addNetwork) {
    if (Object.keys(networks).length === 0) {
      addNetwork.classList.remove('d-none');
    } else {
      addNetwork.classList.add('d-none');
    }
  }
}

// Initialize
document.addEventListener('DOMContentLoaded', () => {
  loadData();

  // Add network button - open modal
  const btnAddNetwork = $('#btn-add-network');
  if (btnAddNetwork) {
    btnAddNetwork.addEventListener('click', () => {
      const modal = new bootstrap.Modal(document.getElementById('addNetworkModal'));
      modal.show();
    });
  }

  // Save network
  $('#btn-save-network').addEventListener('click', async () => {
    const success = await addNetwork();
    // Close modal only on success
    if (success) {
      const modalEl = document.getElementById('addNetworkModal');
      const modal = bootstrap.Modal.getInstance(modalEl);
      if (modal) {
        modal.hide();
      }
    }
  });

  // Reload button
  const btnReload = $('#zerotier-reload');
  if (btnReload) {
    btnReload.addEventListener('click', async () => {
      try {
        btnReload.disabled = true;
        if (window.showBusy) showBusy('Reloading...');
        await loadData();
        showMessage('Configuration reloaded from camera', 'info');
      } catch (err) {
        showMessage('Failed to reload configuration', 'danger');
      } finally {
        btnReload.disabled = false;
        if (window.hideBusy) hideBusy();
      }
    });
  }

  // Auto-refresh every 5 seconds when connected (but not while actively polling)
  setInterval(() => {
    if (ztStatus.running && !pollInterval) {
      loadData();
    }
  }, 5000);
});
