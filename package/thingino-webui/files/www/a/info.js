(function() {
  const tabsEl = $('#infoTabs');
  const outputsEl = $('#infoOutputs');
  const extrasEl = $('#infoExtras');;

  function parseInitialTab() {
    const search = window.location.search.replace(/^\?/, '');
    if (!search) return 'system';
    if (search.includes('=')) {
      const params = new URLSearchParams(search);
      return params.get('section') || params.get('name') || params.get('tab') || 'system';
    }
    return decodeURIComponent(search);
  }

  function updateUrl(tabId) {
    const base = window.location.pathname;
    const suffix = tabId ? `?${encodeURIComponent(tabId)}` : '';
    window.history.replaceState({}, '', `${base}${suffix}`);
  }

  function renderTabs(list, activeId) {
    tabsEl.innerHTML = '';
    (list || []).forEach(item => {
      const li = document.createElement('li');
      li.className = 'nav-item';
      const link = document.createElement('a');
      link.href = `?${encodeURIComponent(item.id)}`;
      link.className = `nav-link${item.id === activeId ? ' active' : ''}`;
      link.textContent = item.label || item.id;
      link.addEventListener('click', ev => {
        ev.preventDefault();
        if (item.id === activeId) return;
        loadSection(item.id);
      });
      li.appendChild(link);
      tabsEl.appendChild(li);
    });
  }

  function buildShareUrl(command) {
    try {
      const payload = btoa(command || '');
      return `/x/send.cgi?to=termbin&payload=${encodeURIComponent(payload)}`;
    } catch (err) {
      return '#';
    }
  }

  function decodeCommandOutput(entry) {
    if (!entry || (typeof entry !== 'object')) return '';
    const encoded = typeof entry.output_base64 === 'string' ? entry.output_base64.trim() : '';
    const fallback = typeof entry.output === 'string' ? entry.output : '';
    if (!encoded) {
      return fallback;
    }

    const decoded = decodeBase64String(encoded);
    return decoded || fallback || '[Unable to decode output]';
  }

  function decodeExtrasHtml(payload) {
    if (!payload || (typeof payload !== 'object')) return '';
    const encoded = typeof payload.extras_html_base64 === 'string' ? payload.extras_html_base64.trim() : '';
    if (!encoded) {
      return '';
    }

    return decodeBase64String(encoded) || '';
  }

  function renderOutputs(entries) {
    outputsEl.innerHTML = '';
    const list = Array.isArray(entries) ? entries : [];
    if (!list.length) {
      const empty = document.createElement('p');
      empty.className = 'text-body-secondary';
      empty.textContent = 'No output returned for this section.';
      outputsEl.appendChild(empty);
      return;
    }

    list.forEach(entry => {
      const wrapper = document.createElement('div');
      wrapper.className = 'mb-4';

      const heading = document.createElement('div');
      heading.className = 'd-flex justify-content-between align-items-center flex-wrap gap-2';

      const title = document.createElement('h6');
      title.className = 'mb-0 font-monospace';
      title.textContent = `# ${entry.command || 'command'}`;

      const share = document.createElement('a');
      share.className = 'btn btn-sm btn-outline-warning';
      share.href = buildShareUrl(entry.command || '');
      share.target = '_blank';
      share.rel = 'noopener noreferrer';
      share.textContent = 'Share via TermBin';

      heading.appendChild(title);
      heading.appendChild(share);

      const pre = document.createElement('pre');
      pre.className = 'terminal';
      pre.textContent = decodeCommandOutput(entry);

      wrapper.appendChild(heading);
      wrapper.appendChild(pre);
      outputsEl.appendChild(wrapper);
    });
  }

  async function loadSection(tabId) {
    const section = tabId || 'system';
    showBusy('Loading system information...');
    outputsEl.innerHTML = '';
    extrasEl.innerHTML = '';
    showAlert();

    try {
      const response = await fetch(`/x/info.cgi?${encodeURIComponent(section)}`, {
        headers: { 'Accept': 'application/json' }
      });
      const data = await response.json();
      if (!response.ok || (data && data.error)) {
        const message = data && data.error && data.error.message ? data.error.message : 'Failed to fetch logs.';
        throw new Error(message);
      }
      renderTabs(data.tabs || [], data.selected || section);
      renderOutputs(data.commands || []);
      extrasEl.innerHTML = decodeExtrasHtml(data) || '';
      updateUrl(data.selected || section);
    } catch (err) {
      showAlert('danger', err.message || 'Unable to load the requested section.');
    } finally {
      hideBusy();
    }
  }

  loadSection(parseInitialTab());
})();
