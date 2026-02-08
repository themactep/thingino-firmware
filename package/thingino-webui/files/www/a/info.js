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

  // Text editor elements
  const textEditorModalEl = $('#textEditorModal');
  const textEditorEl = $('#textEditor');
  const saveTextBtn = $('#saveTextBtn');
  const reloadTextBtn = $('#reloadTextBtn');
  const textEditorModalLabel = $('#textEditorModalLabel');
  const editorFileName = $('#editorFileName');
  const editorStatus = $('#editorStatus');
  const lineWrappingToggle = $('#lineWrapping');
  const downloadBackupBtn = $('#downloadBackupBtn');
  const autoBackupToggle = $('#autoBackup');

  // Text editor state
  const textEditorState = {
    currentFile: null,
    originalContent: null,
    isModified: false
  };

  function encodePath(path) {
    return encodeURIComponent(path);
  }

  function downloadBackupFromMemory() {
    if (!textEditorState.currentFile || !textEditorState.originalContent) return;

    const filename = textEditorState.currentFile.split('/').pop();
    const timestamp = new Date().toISOString().slice(0, 19).replace(/[:-]/g, '').replace('T', '_');
    const backupFilename = `${filename}.backup_${timestamp}`;

    const blob = new Blob([textEditorState.originalContent], { type: 'text/plain' });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement('a');
    link.href = url;
    link.download = backupFilename;
    link.style.display = 'none';
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  }

  async function loadTextFile(filePath) {
    editorStatus.textContent = 'Loading...';
    textEditorEl.disabled = true;
    saveTextBtn.disabled = true;
    reloadTextBtn.disabled = true;
    textEditorEl.value = ''; // Clear previous content

    try {
      const response = await fetch(`/x/texteditor.cgi?file=${encodePath(filePath)}`);
      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(data.error ? data.error.message : `HTTP ${response.status}`);
      }

      textEditorState.currentFile = filePath;
      // Decode base64 content if provided
      let content = data.content || '';
      if (data.content_encoding === 'base64') {
        content = decodeBase64String(content);
        if (!content && data.content) {
          throw new Error('Failed to decode file content');
        }
      }
      textEditorState.originalContent = content;
      textEditorState.isModified = false;

      textEditorEl.value = textEditorState.originalContent;
      textEditorEl.disabled = !data.writable;
      saveTextBtn.disabled = true; // Always disabled initially - no changes to save yet
      reloadTextBtn.disabled = false;

      editorFileName.textContent = filePath.split('/').pop();

      editorStatus.textContent = data.writable ? 'Ready' : 'Read-only';
      textEditorModalLabel.textContent = `Edit: ${filePath.split('/').pop()}`;

    } catch (error) {
      editorStatus.textContent = `Error: ${error.message}`;
      textEditorEl.value = '';
      textEditorEl.disabled = true;
      saveTextBtn.disabled = true;
      reloadTextBtn.disabled = true;
      showAlert('danger', `Failed to load file: ${error.message}`);
    }
  }

  async function saveTextFile() {
    if (!textEditorState.currentFile || !textEditorState.isModified) return;

    // Auto backup if enabled
    if (autoBackupToggle.checked) {
      downloadBackupFromMemory();
      // Small delay to ensure backup download starts before save
      await new Promise(resolve => setTimeout(resolve, 100));
    }

    editorStatus.textContent = 'Saving...';
    saveTextBtn.disabled = true;

    try {
      const response = await fetch(`/x/texteditor.cgi?file=${encodePath(textEditorState.currentFile)}`, {
        method: 'POST',
        body: textEditorEl.value
      });

      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(data.error ? data.error.message : `HTTP ${response.status}`);
      }

      textEditorState.originalContent = textEditorEl.value;
      textEditorState.isModified = false;
      saveTextBtn.disabled = true;

      editorStatus.textContent = 'Saved successfully';
      showAlert('success', `File saved: ${textEditorState.currentFile.split('/').pop()}`);

    } catch (error) {
      editorStatus.textContent = `Save failed: ${error.message}`;
      saveTextBtn.disabled = !textEditorState.isModified;
      showAlert('danger', `Failed to save file: ${error.message}`);
    }
  }

  // Text editor event handlers
  textEditorEl.addEventListener('input', () => {
    // Check if content has been modified
    textEditorState.isModified = textEditorEl.value !== textEditorState.originalContent;
    saveTextBtn.disabled = !textEditorState.isModified;
  });

  lineWrappingToggle.addEventListener('change', function() {
    textEditorEl.style.whiteSpace = this.checked ? 'pre-wrap' : 'pre';
    textEditorEl.style.overflowX = this.checked ? 'hidden' : 'auto';
  });

  saveTextBtn.addEventListener('click', saveTextFile);

  reloadTextBtn.addEventListener('click', () => {
    if (textEditorState.isModified) {
      if (!confirm('Discard unsaved changes and reload?')) return;
    }
    if (textEditorState.currentFile) {
      loadTextFile(textEditorState.currentFile);
    }
  });

  downloadBackupBtn.addEventListener('click', downloadBackupFromMemory);

  textEditorModalEl.addEventListener('hidden.bs.modal', () => {
    if (textEditorState.isModified) {
      if (confirm('You have unsaved changes. Do you want to save before closing?')) {
        saveTextFile();
      }
    }
    // Reset editor state
    textEditorState.currentFile = null;
    textEditorState.originalContent = null;
    textEditorState.isModified = false;
    textEditorEl.value = '';
    editorStatus.textContent = 'Ready';
  });

  // Keyboard shortcuts for text editor
  textEditorEl.addEventListener('keydown', event => {
    // Ctrl+S to save
    if (event.ctrlKey && event.key === 's') {
      event.preventDefault();
      if (!saveTextBtn.disabled) {
        saveTextFile();
      }
    }
    // Tab key handling - insert spaces instead of changing focus
    if (event.key === 'Tab') {
      event.preventDefault();
      const start = textEditorEl.selectionStart;
      const end = textEditorEl.selectionEnd;
      textEditorEl.value = textEditorEl.value.substring(0, start) + '  ' + textEditorEl.value.substring(end);
      textEditorEl.selectionStart = textEditorEl.selectionEnd = start + 2;
      // Update modification state
      textEditorState.isModified = textEditorEl.value !== textEditorState.originalContent;
      saveTextBtn.disabled = !textEditorState.isModified;
    }
  });

  window.editFile = function(filePath) {
      const textEditorModal = new bootstrap.Modal(textEditorModalEl);
      textEditorModal.show();
      loadTextFile(filePath);
  }

  loadSection(parseInitialTab());
})();
