(function() {
  const breadcrumbsEl = $('#breadcrumbs');
  const tableBody = document.querySelector('#fileTable tbody');
  const emptyState = $('#emptyState');
  const refreshBtn = $('#btnRefresh');
  const parentBtn = $('#btnParent');
  const playerModalEl = $('#playerModal');
  const playerEl = $('#player');
  const downloadBtn = $('#playerModalDownload');
  const modalLabel = $('#playerModalLabel');

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

  // File actions modal elements
  const fileActionsModalEl = $('#fileActionsModal');
  const fileActionName = $('#fileActionName');
  const fileActionPath = $('#fileActionPath');
  const fileActionIcon = $('#fileActionIcon');
  const fileActionDownload = $('#fileActionDownload');
  const fileActionView = $('#fileActionView');
  const fileActionEdit = $('#fileActionEdit');

  // Image preview modal elements
  const imagePreviewModalEl = $('#imagePreviewModal');
  const imagePreviewImg = $('#imagePreviewImg');
  const imagePreviewPath = $('#imagePreviewPath');
  const imagePreviewDownload = $('#imagePreviewDownload');

  // Text editor state
  const textEditorState = {
    currentFile: null,
    originalContent: null,
    isModified: false
  };

  const urlParams = new URLSearchParams(window.location.search);
  const initialPath = urlParams.get('cd') || '/';
  const DirectoryWatchIntervalMs = 15 * 1000; // 15 sec
  const state = {
    currentPath: initialPath,
    parentPath: '/',
    ready: false,
    loading: false,
    lastSignature: '',
    watchTimer: null
  };

  function encodePath(path) {
    return encodeURIComponent(path);
  }

  // Check if file is likely editable as text
  function isTextFile(filename) {
    const textExtensions = [
      'txt', 'log', 'conf', 'config', 'cfg', 'ini', 'json', 'xml', 'html', 'htm', 'css', 'js',
      'sh', 'py', 'pl', 'rb', 'c', 'cpp', 'h', 'hpp', 'java', 'md', 'rst', 'csv', 'sql', 'yaml', 'yml'
    ];
    const ext = filename.toLowerCase().split('.').pop();
    return textExtensions.includes(ext) || !filename.includes('.');
  }

  // Check if file is an image that can be viewed in browser
  function isImageFile(filename) {
    const imageExtensions = ['jpg', 'jpeg', 'png', 'gif', 'bmp', 'webp', 'svg'];
    const ext = filename.toLowerCase().split('.').pop();
    return imageExtensions.includes(ext);
  }

  // Check if file is a video that can be played in browser
  function isVideoFile(filename) {
    const videoExtensions = ['mp4', 'avi', 'mov', 'mkv', 'webm'];
    const ext = filename.toLowerCase().split('.').pop();
    return videoExtensions.includes(ext);
  }

  // Show image in preview modal
  function showImagePreview(fileName, filePath) {
    const imageUrl = `/x/tool-file-manager.cgi?dl=${encodePath(filePath)}`;

    // Set image source and info
    imagePreviewImg.src = imageUrl;
    imagePreviewImg.alt = fileName;
    imagePreviewPath.textContent = filePath;
    imagePreviewDownload.href = imageUrl;
    imagePreviewDownload.download = fileName;

    // Update modal title
    $('#imagePreviewModalLabel').textContent = `Image Preview: ${fileName}`;

    // Show the modal
    new bootstrap.Modal(imagePreviewModalEl).show();
  }

  // Show video in player modal
  function showVideoPlayer(fileName, filePath) {
    // Update modal content
    modalLabel.textContent = `Video: ${fileName}`;
    downloadBtn.href = `/x/tool-file-manager.cgi?dl=${encodePath(filePath)}`;
    downloadBtn.download = fileName;
    playerEl.src = `/x/tool-file-manager.cgi?play=${encodePath(filePath)}`;

    // Show the modal
    new bootstrap.Modal(playerModalEl).show();

    // Start playback
    playerEl.play().catch(() => {});
  }

  function updateHistory(path, replace = false) {
    const params = new URLSearchParams();
    if (path && path !== '/') {
      params.set('cd', path);
    }
    const nextUrl = params.toString() ? `${window.location.pathname}?${params}` : window.location.pathname;
    if (replace) {
      window.history.replaceState({ path }, '', nextUrl);
    } else {
      window.history.pushState({ path }, '', nextUrl);
    }
  }

  function renderBreadcrumbs(list) {
    breadcrumbsEl.innerHTML = '';
    const crumbs = Array.isArray(list) && list.length ? list : [{ label: 'Home', path: '/' }];
    crumbs.forEach((crumb, index) => {
      const li = document.createElement('li');
      li.className = 'breadcrumb-item';
      const isLast = index === crumbs.length - 1;
      if (isLast) {
        li.classList.add('active');
        li.textContent = crumb.label || 'Current';
      } else {
        const link = document.createElement('a');
        link.href = crumb.path === '/' ? '/tool-file-manager.html' : `?cd=${encodePath(crumb.path || '/')}`;
        link.dataset.path = crumb.path || '/';
        link.textContent = crumb.label || crumb.path || '/';
        link.addEventListener('click', handleDirLink);
        li.appendChild(link);
      }
      breadcrumbsEl.appendChild(li);
    });
  }

  function handleDirLink(event) {
    event.preventDefault();
    const nextPath = event.currentTarget.dataset.path || '/';
    loadDirectory(nextPath, { pushHistory: true });
  }

  function renderEntries(entries) {
    tableBody.innerHTML = '';
    if (!entries || !entries.length) {
      emptyState.classList.remove('d-none');
      return;
    }
    emptyState.classList.add('d-none');

    entries.forEach(entry => {
      const tr = document.createElement('tr');

      const nameCell = document.createElement('td');
      const linkSuffix = entry.is_link && entry.link_target ? ` -> ${entry.link_target}` : '';

      if (entry.is_dir) {
        const link = document.createElement('a');
        link.href = `?cd=${encodePath(entry.path)}`;
        link.dataset.path = entry.path;
        link.textContent = `${entry.name || entry.path}/`;
        link.addEventListener('click', handleDirLink);
        nameCell.appendChild(link);
        if (linkSuffix) {
          const target = document.createElement('span');
          target.className = 'text-secondary small ms-2';
          target.textContent = linkSuffix;
          nameCell.appendChild(target);
        }
      } else {
        const dl = document.createElement('a');
        dl.href = `/x/tool-file-manager.cgi?dl=${encodePath(entry.path)}`;
        dl.download = entry.name || '';
        dl.textContent = entry.name || entry.path;
        dl.className = 'file-download';
        dl.dataset.downloadName = entry.name || entry.path || '';
        dl.dataset.downloadPath = entry.path || '';
        nameCell.appendChild(dl);
        if (linkSuffix) {
          const target = document.createElement('span');
          target.className = 'text-secondary small ms-2';
          target.textContent = linkSuffix;
          nameCell.appendChild(target);
        }
      }
      tr.appendChild(nameCell);

      const sizeCell = document.createElement('td');
      sizeCell.className = 'text-end';
      sizeCell.textContent = entry.size || '0';
      tr.appendChild(sizeCell);

      const permCell = document.createElement('td');
      permCell.textContent = entry.perm || '';
      tr.appendChild(permCell);

      const dateCell = document.createElement('td');
      dateCell.textContent = entry.time || '';
      tr.appendChild(dateCell);

      tableBody.appendChild(tr);
    });
  }

  function computeEntriesSignature(entries = []) {
    if (!entries.length) return 'empty';
    return entries
      .map(entry => [
        entry.path || entry.name || '',
        entry.size || '0',
        entry.perm || '',
        entry.time || '',
        entry.is_dir ? 'd' : 'f'
      ].join(':'))
      .join('|');
  }

  function shouldSkipSilentLoad(options = {}) {
    return options.silent && (state.loading || document.hidden);
  }

  async function loadDirectory(targetPath, { pushHistory = false, replaceHistory = false, silent = false } = {}) {
    const normalized = targetPath || '/';
    if (shouldSkipSilentLoad({ silent })) return;
    if (!silent) {
      showBusy('Loading directory...');
      showAlert('', '');
    }
    state.loading = true;

    try {
      const response = await fetch(`/x/tool-file-manager.cgi?cd=${encodePath(normalized)}`, {
        headers: { 'Accept': 'application/json' }
      });
      const payload = await response.json();
      if (!response.ok || (payload && payload.error)) {
        const message = payload && payload.error ? payload.error.message : `Request failed with status ${response.status}`;
        throw new Error(message || 'Unable to load directory');
      }

      const entries = payload.entries || [];
      const resolvedPath = (payload && payload.directory) || normalized;
      const signature = computeEntriesSignature(entries);
      const pathChanged = resolvedPath !== state.currentPath;
      const hasChanged = signature !== state.lastSignature || pathChanged;

      if (!silent || hasChanged) {
        renderBreadcrumbs(payload.breadcrumbs || []);
        renderEntries(entries);
        state.currentPath = resolvedPath;
        state.parentPath = payload.parent || '/';
        parentBtn.disabled = !state.parentPath || state.parentPath === state.currentPath;

        if (replaceHistory) {
          updateHistory(resolvedPath, true);
        } else if (pushHistory) {
          updateHistory(resolvedPath, false);
        }
      } else {
        state.currentPath = resolvedPath;
        state.parentPath = payload.parent || '/';
      }

      state.lastSignature = signature;
      kickDirectoryWatcher();
    } catch (error) {
      if (!silent) {
        showAlert('danger', error.message || 'Unable to load directory');
      } else if (window.console) {
        console.warn('Background directory refresh skipped:', error.message || error);
      }
    } finally {
      if (!silent) hideBusy();
      state.loading = false;
    }
  }

  refreshBtn.addEventListener('click', () => loadDirectory(state.currentPath));
  parentBtn.addEventListener('click', () => loadDirectory(state.parentPath || '/', { pushHistory: true }));
  function triggerDownload(link) {
    const url = link.href;
    const filename = link.dataset.downloadName || 'download';

    fetch(url)
      .then(response => response.blob())
      .then(blob => {
        const tempUrl = window.URL.createObjectURL(blob);
        const tempLink = document.createElement('a');
        tempLink.href = tempUrl;
        tempLink.download = filename;
        tempLink.style.display = 'none';
        document.body.appendChild(tempLink);
        tempLink.click();
        document.body.removeChild(tempLink);
        window.URL.revokeObjectURL(tempUrl);
      })
      .catch(err => {
        console.error('Download failed:', err);
        window.location.href = url;
      });
  }

  tableBody.addEventListener('click', async event => {
    const link = event.target.closest('a.file-download');
    if (!link) return;
    event.preventDefault();

    const fileName = link.dataset.downloadName || link.textContent || 'this file';
    const filePath = link.dataset.downloadPath || '';

    // For image files, go directly to preview modal
    if (isImageFile(fileName)) {
      showImagePreview(fileName, filePath);
      return;
    }

    // For video files, go directly to player modal
    if (isVideoFile(fileName)) {
      showVideoPlayer(fileName, filePath);
      return;
    }

    // For non-image, non-video files, show file actions modal
    fileActionName.textContent = fileName;
    fileActionPath.textContent = filePath;

    // Set appropriate icon based on file type
    const ext = fileName.toLowerCase().split('.').pop();
    let iconClass = 'bi-file-earmark';
    if (['txt', 'log', 'md', 'json', 'xml', 'html', 'css', 'js'].includes(ext)) {
      iconClass = 'bi-file-text';
    } else if (['pdf'].includes(ext)) {
      iconClass = 'bi-file-pdf';
    } else if (['zip', 'tar', 'gz', 'rar'].includes(ext)) {
      iconClass = 'bi-file-zip';
    }
    fileActionIcon.className = `bi ${iconClass} fs-2 text-primary me-3`;

    // Show/hide edit button for text files
    if (isTextFile(fileName)) {
      fileActionEdit.classList.remove('d-none');
      fileActionEdit.dataset.editFile = filePath;
    } else {
      fileActionEdit.classList.add('d-none');
    }

    // Hide view button since images/videos are handled above
    fileActionView.classList.add('d-none');

    // Set up download action
    fileActionDownload.onclick = () => {
      const fileActionsModal = bootstrap.Modal.getInstance(fileActionsModalEl);
      if (fileActionsModal) {
        fileActionsModal.hide();
      }
      // Trigger download after modal closes to avoid focus issues
      setTimeout(() => {
        triggerDownload(link);
      }, 200);
    };

    // Show the modal
    new bootstrap.Modal(fileActionsModalEl).show();
  });

  playerModalEl.addEventListener('show.bs.modal', event => {
    const trigger = event.relatedTarget;
    if (!trigger) return;
    const filePath = trigger.dataset.play || '';
    modalLabel.textContent = filePath || 'Video preview';
    downloadBtn.href = `/x/tool-file-manager.cgi?dl=${encodePath(filePath)}`;
    playerEl.src = `/x/tool-file-manager.cgi?play=${encodePath(filePath)}`;
    playerEl.play().catch(() => {});
  });

  playerModalEl.addEventListener('hidden.bs.modal', () => {
    playerEl.pause();
    playerEl.removeAttribute('src');
    playerEl.load();
  });

  window.addEventListener('popstate', event => {
    const nextPath = event.state && event.state.path ? event.state.path : '/';
    loadDirectory(nextPath);
  });

  function runDirectoryWatch() {
    if (document.hidden) return;
    loadDirectory(state.currentPath, { replaceHistory: true, silent: true });
  }

  function kickDirectoryWatcher() {
    if (state.watchTimer) {
      clearInterval(state.watchTimer);
    }
    state.watchTimer = window.setInterval(runDirectoryWatch, DirectoryWatchIntervalMs);
  }

  document.addEventListener('visibilitychange', () => {
    if (!document.hidden) {
      runDirectoryWatch();
    }
  });

  // Text editor functionality
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

      // Refresh file listing to show updated file size/time
      setTimeout(() => {
        loadDirectory(state.currentPath, { silent: true });
      }, 500);

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

  textEditorModalEl.addEventListener('show.bs.modal', event => {
    const trigger = event.relatedTarget;
    if (!trigger) return;
    const filePath = trigger.dataset.editFile || '';
    if (filePath) {
      loadTextFile(filePath);
    }
  });

  // File actions modal edit button handler
  fileActionEdit.addEventListener('click', (e) => {
    e.preventDefault();
    const filePath = fileActionEdit.dataset.editFile || '';
    if (filePath) {
      // Get the bootstrap modal instance
      const fileActionsModal = bootstrap.Modal.getInstance(fileActionsModalEl) || new bootstrap.Modal(fileActionsModalEl);

      // Hide the current modal and then show the text editor
      fileActionsModal.hide();

      // Use a small delay to ensure the modal is fully hidden before opening the next one
      setTimeout(() => {
        const textEditorModal = new bootstrap.Modal(textEditorModalEl);
        textEditorModal.show();
        loadTextFile(filePath);
      }, 150);
    }
  });

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

  loadDirectory(state.currentPath, { replaceHistory: true }).then(() => {
    kickDirectoryWatcher();
  });
})();
