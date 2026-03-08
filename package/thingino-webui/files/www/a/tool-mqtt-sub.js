(function () {
  'use strict';

  const PRESETS = [
    { label: 'Reboot camera',              cmd: 'reboot' },
    { label: 'Take snapshot',              cmd: 'snapshot' },
    { label: 'Enable IR cut',              cmd: 'echo ir_on > /proc/jz/isp/ircut' },
    { label: 'Disable IR cut',             cmd: 'echo ir_off > /proc/jz/isp/ircut' },
    { label: 'Log to syslog',              cmd: 'logger -t mqtt "Topic: $MQTT_TOPIC Payload: $MQTT_PAYLOAD"' },
    { label: 'Conditional reboot (pay=1)', cmd: '[ "$MQTT_PAYLOAD" = "1" ] && reboot' },
  ];

  const endpoint = '/x/json-config-mqtt-sub.cgi';
  const form = $('#mqttSubForm');
  const tbody = $('#mqtt-sub-tbody');
  const emptyMsg = $('#mqtt-sub-empty');
  const addBtn = $('#mqtt-sub-add');
  const reloadBtn = $('#mqtt-sub-reload');
  const saveBtn = $('#mqtt-sub-save');

  function updateEmptyState() {
    const hasSubs = tbody.querySelectorAll('tr').length > 0;
    emptyMsg.classList.toggle('d-none', hasSubs);
  }

  function buildPresetMenu() {
    const ul = document.createElement('ul');
    ul.className = 'dropdown-menu dropdown-menu-end';
    PRESETS.forEach(function (p) {
      const li = document.createElement('li');
      const a = document.createElement('a');
      a.className = 'dropdown-item sub-preset';
      a.href = '#';
      a.textContent = p.label;
      a.dataset.cmd = p.cmd;
      li.appendChild(a);
      ul.appendChild(li);
    });
    return ul;
  }

  function addSubscriptionRow(data) {
    data = data || {};
    const tr = document.createElement('tr');

    // Enabled toggle
    const tdEnabled = document.createElement('td');
    const chk = document.createElement('input');
    chk.type = 'checkbox';
    chk.className = 'form-check-input sub-enabled';
    chk.checked = data.enabled !== false;
    chk.title = 'Enabled';
    tdEnabled.appendChild(chk);

    // Topic
    const tdTopic = document.createElement('td');
    const inputTopic = document.createElement('input');
    inputTopic.type = 'text';
    inputTopic.className = 'form-control form-control-sm sub-topic';
    inputTopic.placeholder = 'camera/cmd/reboot';
    inputTopic.title = 'Supports wildcards: + (one level), # (remaining)';
    inputTopic.value = data.topic || '';
    tdTopic.appendChild(inputTopic);

    // QoS
    const tdQos = document.createElement('td');
    const sel = document.createElement('select');
    sel.className = 'form-select form-select-sm sub-qos';
    [['0', '0 – At most once'], ['1', '1 – At least once'], ['2', '2 – Exactly once']].forEach(function (o) {
      const opt = document.createElement('option');
      opt.value = o[0];
      opt.textContent = o[1];
      sel.appendChild(opt);
    });
    sel.value = String(data.qos != null ? data.qos : 0);
    tdQos.appendChild(sel);

    // Action + presets dropdown
    const tdAction = document.createElement('td');
    const inputGroup = document.createElement('div');
    inputGroup.className = 'input-group input-group-sm';

    const inputAction = document.createElement('input');
    inputAction.type = 'text';
    inputAction.className = 'form-control form-control-sm sub-action font-monospace';
    inputAction.placeholder = 'e.g. reboot';
    inputAction.value = data.action || '';

    const presetToggle = document.createElement('button');
    presetToggle.type = 'button';
    presetToggle.className = 'btn btn-outline-secondary dropdown-toggle dropdown-toggle-split';
    presetToggle.dataset.bsToggle = 'dropdown';
    presetToggle.title = 'Presets';

    const presetMenu = buildPresetMenu();
    presetMenu.querySelectorAll('.sub-preset').forEach(function (a) {
      a.addEventListener('click', function (e) {
        e.preventDefault();
        inputAction.value = this.dataset.cmd;
      });
    });

    inputGroup.appendChild(inputAction);
    inputGroup.appendChild(presetToggle);
    inputGroup.appendChild(presetMenu);
    tdAction.appendChild(inputGroup);

    // Remove button
    const tdRemove = document.createElement('td');
    const btnRemove = document.createElement('button');
    btnRemove.type = 'button';
    btnRemove.className = 'btn btn-outline-danger btn-sm';
    btnRemove.textContent = '✕';
    btnRemove.addEventListener('click', function () {
      tr.remove();
      updateEmptyState();
    });
    tdRemove.appendChild(btnRemove);

    tr.appendChild(tdEnabled);
    tr.appendChild(tdTopic);
    tr.appendChild(tdQos);
    tr.appendChild(tdAction);
    tr.appendChild(tdRemove);
    tbody.appendChild(tr);
    updateEmptyState();
    return tr;
  }

  function collectSubscriptions() {
    return Array.from(tbody.querySelectorAll('tr')).map(function (tr) {
      return {
        topic: tr.querySelector('.sub-topic').value.trim(),
        qos: parseInt(tr.querySelector('.sub-qos').value, 10) || 0,
        enabled: tr.querySelector('.sub-enabled').checked,
        action: tr.querySelector('.sub-action').value.trim()
      };
    });
  }

  function validateBroker() {
    const enabled = $('#mqtt_sub_enabled').checked;
    const hostInput = $('#mqtt_sub_host');
    if (enabled && !hostInput.value.trim()) {
      hostInput.classList.add('is-invalid');
      return false;
    }
    hostInput.classList.remove('is-invalid');
    return true;
  }

  function setFormBusy(state) {
    [saveBtn, reloadBtn, addBtn].forEach(function (el) { if (el) el.disabled = state; });
    tbody.querySelectorAll('input, select, button').forEach(function (el) { el.disabled = state; });
    state ? showBusy('Working...') : hideBusy();
  }

  async function loadConfig(opts) {
    opts = opts || {};
    if (!opts.silent) setFormBusy(true);
    try {
      const resp = await fetch(endpoint, { headers: { Accept: 'application/json' } });
      if (!resp.ok) throw new Error('Failed to load MQTT subscription settings');
      const data = await resp.json();

      $('#mqtt_sub_enabled').checked = data.enabled === true;
      $('#mqtt_sub_host').value = data.host || '';
      $('#mqtt_sub_port').value = data.port || 1883;
      $('#mqtt_sub_username').value = data.username || '';
      $('#mqtt_sub_password').value = data.password || '';
      $('#mqtt_sub_use_ssl').checked = data.use_ssl === true;

      tbody.innerHTML = '';
      (Array.isArray(data.subscriptions) ? data.subscriptions : []).forEach(addSubscriptionRow);
      updateEmptyState();
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load MQTT subscription settings.');
    } finally {
      if (!opts.silent) setFormBusy(false);
    }
  }

  async function saveConfig(payload) {
    setFormBusy(true);
    try {
      const resp = await fetch(endpoint, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json' },
        body: JSON.stringify(payload)
      });
      const result = await resp.json();
      if (!resp.ok || (result && result.error)) {
        throw new Error((result.error && result.error.message) || 'Failed to save settings');
      }
      if (window.thinginoFooter && typeof window.thinginoFooter.showMessage === 'function') {
        window.thinginoFooter.showMessage('MQTT subscription settings saved.', 'success');
      } else {
        showAlert('success', 'MQTT subscription settings saved.', 3000);
      }
      form.classList.remove('was-validated');
      await loadConfig({ silent: true });
    } catch (err) {
      showAlert('danger', err.message || 'Failed to save MQTT subscription settings.');
    } finally {
      setFormBusy(false);
    }
  }

  form.addEventListener('submit', function (ev) {
    ev.preventDefault();
    if (!form.checkValidity() || !validateBroker()) {
      form.classList.add('was-validated');
      return;
    }
    saveConfig({
      enabled: $('#mqtt_sub_enabled').checked,
      host: $('#mqtt_sub_host').value.trim(),
      port: parseInt($('#mqtt_sub_port').value, 10) || 1883,
      username: $('#mqtt_sub_username').value.trim(),
      password: $('#mqtt_sub_password').value.trim(),
      use_ssl: $('#mqtt_sub_use_ssl').checked,
      subscriptions: collectSubscriptions()
    });
  });

  addBtn.addEventListener('click', function () { addSubscriptionRow(); });

  reloadBtn.addEventListener('click', async function () {
    try {
      reloadBtn.disabled = true;
      await loadConfig();
      showAlert('info', 'MQTT subscription settings reloaded.', 3000);
    } finally {
      reloadBtn.disabled = false;
    }
  });

  loadConfig();
})();

