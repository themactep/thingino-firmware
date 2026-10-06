(function () {
  const outputsEl = $("#infoOutputs");
  const extrasEl = $("#infoExtras");
  const tabsEl = $("#infoTabs");

  const DEFAULT_SECTION = "status";

  const INFO_GROUPS = [
    {
      label: "Files",
      items: [
        { id: "crontab", label: "crontab" },
        { id: "onvif", label: "onvif.json" },
        { id: "thingino", label: "thingino.json" },
      ],
    },
    {
      label: "Logs",
      items: [
        { id: "dmesg", label: "dmesg" },
        { id: "logcat", label: "logcat" },
        { id: "logread", label: "logread" },
      ],
    },
    {
      label: "Info",
      items: [
        { id: "lsmod", label: "lsmod" },
        { id: "netstat", label: "netstat" },
        { id: "release", label: "os-release" },
        { id: "top", label: "top" },
        { id: "status", label: "status" },
      ],
    },
  ];

  const PREFIX_GROUPS = {
    "File:": "Files",
    "Log:": "Logs",
    "Info:": "Info",
  };

  function stripPrefix(label) {
    if (typeof label !== "string") return "";
    const match = label.match(/^(File|Log|Info):\s*/);
    return match ? label.slice(match[0].length) : label;
  }

  function groupForLabel(label) {
    if (typeof label !== "string") return null;
    const match = label.match(/^(File|Log|Info):/);
    return match ? PREFIX_GROUPS[match[0]] : null;
  }

  function sectionIdFromHref(href) {
    if (typeof href !== "string") return null;
    const index = href.indexOf("?");
    if (index === -1) return null;
    const query = href.slice(index + 1).replace(/^(section|tab|name)=/, "");
    try {
      return decodeURIComponent(query) || null;
    } catch (err) {
      return query || null;
    }
  }

  function findGroup(label) {
    return INFO_GROUPS.find(function (group) {
      return group.label === label;
    });
  }

  function insertPluginItem(group, item, position) {
    if (!group) return;
    const items = group.items;
    const duplicate = items.some(function (existing) {
      return existing.id === item.id;
    });
    if (duplicate) return;

    let idx;
    if (position === "prepend") {
      idx = 0;
    } else if (
      typeof position === "string" &&
      position.indexOf("after:") === 0
    ) {
      const target = stripPrefix(position.slice(6).trim());
      const found = items.findIndex(function (it) {
        return it.label === target;
      });
      idx = found === -1 ? items.length : found + 1;
    } else if (
      typeof position === "string" &&
      position.indexOf("before:") === 0
    ) {
      const target = stripPrefix(position.slice(7).trim());
      const found = items.findIndex(function (it) {
        return it.label === target;
      });
      idx = found === -1 ? items.length : found;
    } else if (
      typeof position === "string" &&
      position.indexOf("index:") === 0
    ) {
      idx = parseInt(position.slice(6), 10) || 0;
      idx = Math.max(0, Math.min(idx, items.length));
    } else {
      idx = items.length;
    }
    items.splice(idx, 0, item);
  }

  function mergePluginSections() {
    const uiConfig = window.thinginoUIConfig || {};
    const plugins = uiConfig.plugins || {};
    Object.keys(plugins).forEach(function (name) {
      const plugin = plugins[name];
      if (!plugin || !Array.isArray(plugin.nav)) return;
      plugin.nav.forEach(function (contribution) {
        if (!contribution || contribution.section !== "ddInfo") return;
        const items = Array.isArray(contribution.items)
          ? contribution.items
          : [];
        items.forEach(function (item) {
          if (!item || typeof item.href !== "string") return;
          if (!/^\/?info\.html\?/.test(item.href)) return;
          const id = sectionIdFromHref(item.href);
          if (!id) return;
          const rawLabel = typeof item.label === "string" ? item.label : id;
          const group = findGroup(groupForLabel(rawLabel));
          if (!group) return;
          insertPluginItem(
            group,
            { id: id, label: stripPrefix(rawLabel) || id },
            contribution.position,
          );
        });
      });
    });
  }

  function allSectionIds() {
    const ids = [];
    INFO_GROUPS.forEach(function (group) {
      group.items.forEach(function (item) {
        ids.push(item.id);
      });
    });
    return ids;
  }

  function sectionLabel(id) {
    let label = null;
    INFO_GROUPS.some(function (group) {
      const found = group.items.find(function (item) {
        return item.id === id;
      });
      if (found) {
        label = found.label;
        return true;
      }
      return false;
    });
    return label;
  }

  function markActivePill(id) {
    if (!tabsEl) return;
    tabsEl.querySelectorAll("[data-section]").forEach(function (button) {
      button.classList.toggle("active", button.dataset.section === id);
    });
  }

  function renderTabs() {
    if (!tabsEl) return;
    tabsEl.innerHTML = "";
    INFO_GROUPS.forEach(function (group) {
      if (!group.items.length) return;

      const wrapper = document.createElement("div");
      wrapper.className = "d-flex align-items-center flex-wrap gap-2 mb-1";

      const heading = document.createElement("div");
      heading.className = "text-uppercase text-secondary x-small";
      heading.textContent = group.label;
      wrapper.appendChild(heading);

      const pills = document.createElement("div");
      pills.className = "nav nav-pills flex-wrap gap-1";

      group.items.forEach(function (item) {
        const button = document.createElement("button");
        button.type = "button";
        button.className = "nav-link py-0 px-2 small";
        button.dataset.section = item.id;
        button.textContent = item.label;
        button.addEventListener("click", function () {
          selectSection(item.id);
        });
        pills.appendChild(button);
      });

      wrapper.appendChild(pills);
      tabsEl.appendChild(wrapper);
    });
  }

  function selectSection(id) {
    if (!id) return;
    markActivePill(id);
    if (window.history && typeof window.history.replaceState === "function") {
      window.history.replaceState(
        null,
        "",
        "/info.html?" + encodeURIComponent(id),
      );
    }
    loadSection(id);
  }

  function parseInitialTab() {
    const search = window.location.search.replace(/^\?/, "");
    if (!search) return DEFAULT_SECTION;

    let value;
    if (search.includes("=")) {
      const params = new URLSearchParams(search);
      value =
        params.get("section") ||
        params.get("name") ||
        params.get("tab") ||
        DEFAULT_SECTION;
    } else {
      try {
        value = decodeURIComponent(search);
      } catch (err) {
        value = DEFAULT_SECTION;
      }
    }

    return allSectionIds().indexOf(value) === -1 ? DEFAULT_SECTION : value;
  }

  function buildShareUrl(command) {
    try {
      const payload = btoa(command || "");
      return `/x/send.cgi?to=termbin&payload=${encodeURIComponent(payload)}`;
    } catch (err) {
      return "#";
    }
  }

  function decodeCommandOutput(entry) {
    if (!entry || typeof entry !== "object") return "";
    const encoded =
      typeof entry.output_base64 === "string" ? entry.output_base64.trim() : "";
    const fallback = typeof entry.output === "string" ? entry.output : "";
    if (!encoded) {
      return fallback;
    }

    const decoded = decodeBase64String(encoded);
    return decoded || fallback || "[Unable to decode output]";
  }

  function decodeExtrasHtml(payload) {
    if (!payload || typeof payload !== "object") return "";
    const encoded =
      typeof payload.extras_html_base64 === "string"
        ? payload.extras_html_base64.trim()
        : "";
    if (!encoded) {
      return "";
    }

    return decodeBase64String(encoded) || "";
  }

  function renderOutputs(entries) {
    outputsEl.innerHTML = "";
    const list = Array.isArray(entries) ? entries : [];
    if (!list.length) {
      const empty = document.createElement("p");
      empty.className = "text-body-secondary";
      empty.textContent = "No output returned for this section.";
      outputsEl.appendChild(empty);
      return;
    }

    list.forEach((entry) => {
      const wrapper = document.createElement("div");
      wrapper.className = "mb-4";

      const heading = document.createElement("div");
      heading.className =
        "d-flex justify-content-between align-items-center flex-wrap gap-2";

      const title = document.createElement("h6");
      title.className = "mb-0 font-monospace";
      title.textContent = `# ${entry.command || "command"}`;

      const share = document.createElement("a");
      share.className = "btn btn-sm btn-outline-warning";
      share.href = buildShareUrl(entry.command || "");
      share.target = "_blank";
      share.rel = "noopener noreferrer";
      share.textContent = "Share via TermBin";

      heading.appendChild(title);
      heading.appendChild(share);

      const pre = document.createElement("pre");
      pre.className = "terminal";
      pre.textContent = decodeCommandOutput(entry);

      wrapper.appendChild(heading);
      wrapper.appendChild(pre);
      outputsEl.appendChild(wrapper);
    });
  }

  async function loadSection(tabId) {
    const section = tabId || DEFAULT_SECTION;
    const label = sectionLabel(section) || section;
    showBusy("Loading " + label + "...");
    markActivePill(section);
    outputsEl.innerHTML = "";
    extrasEl.innerHTML = "";
    showAlert();

    try {
      const response = await fetch(
        `/x/info.cgi?${encodeURIComponent(section)}`,
        {
          headers: { Accept: "application/json" },
        },
      );
      const data = await response.json();
      if (!response.ok || (data && data.error)) {
        const message =
          data && data.error && data.error.message
            ? data.error.message
            : "Failed to fetch logs.";
        throw new Error(message);
      }
      renderOutputs(data.commands || []);
      extrasEl.innerHTML = decodeExtrasHtml(data) || "";
    } catch (err) {
      showAlert(
        "danger",
        err.message || "Unable to load the requested section.",
      );
    } finally {
      hideBusy();
    }
  }

  // Text editor elements
  const textEditorModalEl = $("#textEditorModal");
  const textEditorEl = $("#textEditor");
  const saveTextBtn = $("#saveTextBtn");
  const reloadTextBtn = $("#reloadTextBtn");
  const textEditorModalLabel = $("#textEditorModalLabel");
  const editorFileName = $("#editorFileName");
  const editorStatus = $("#editorStatus");
  const lineWrappingToggle = $("#lineWrapping");
  const downloadBackupBtn = $("#downloadBackupBtn");
  const autoBackupToggle = $("#autoBackup");

  // Text editor state
  const textEditorState = {
    currentFile: null,
    originalContent: null,
    isModified: false,
  };

  function encodePath(path) {
    return encodeURIComponent(path);
  }

  function downloadBackupFromMemory() {
    if (!textEditorState.currentFile || !textEditorState.originalContent)
      return;

    const filename = textEditorState.currentFile.split("/").pop();
    const timestamp = new Date()
      .toISOString()
      .slice(0, 19)
      .replace(/[:-]/g, "")
      .replace("T", "_");
    const backupFilename = `${filename}.backup_${timestamp}`;

    const blob = new Blob([textEditorState.originalContent], {
      type: "text/plain",
    });
    const url = window.URL.createObjectURL(blob);
    const link = document.createElement("a");
    link.href = url;
    link.download = backupFilename;
    link.style.display = "none";
    document.body.appendChild(link);
    link.click();
    document.body.removeChild(link);
    window.URL.revokeObjectURL(url);
  }

  async function loadTextFile(filePath) {
    editorStatus.textContent = "Loading...";
    textEditorEl.disabled = true;
    saveTextBtn.disabled = true;
    reloadTextBtn.disabled = true;
    textEditorEl.value = ""; // Clear previous content

    try {
      const response = await fetch(
        `/x/texteditor.cgi?file=${encodePath(filePath)}`,
      );
      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(
          data.error ? data.error.message : `HTTP ${response.status}`,
        );
      }

      textEditorState.currentFile = filePath;
      // Decode base64 content if provided
      let content = data.content || "";
      if (data.content_encoding === "base64") {
        content = decodeBase64String(content);
        if (!content && data.content) {
          throw new Error("Failed to decode file content");
        }
      }
      textEditorState.originalContent = content;
      textEditorState.isModified = false;

      textEditorEl.value = textEditorState.originalContent;
      textEditorEl.disabled = !data.writable;
      saveTextBtn.disabled = true; // Always disabled initially - no changes to save yet
      reloadTextBtn.disabled = false;

      editorFileName.textContent = filePath.split("/").pop();

      editorStatus.textContent = data.writable ? "Ready" : "Read-only";
      textEditorModalLabel.textContent = `Edit: ${filePath.split("/").pop()}`;
    } catch (error) {
      editorStatus.textContent = `Error: ${error.message}`;
      textEditorEl.value = "";
      textEditorEl.disabled = true;
      saveTextBtn.disabled = true;
      reloadTextBtn.disabled = true;
      showAlert("danger", `Failed to load file: ${error.message}`);
    }
  }

  async function saveTextFile() {
    if (!textEditorState.currentFile || !textEditorState.isModified) return;

    // Auto backup if enabled
    if (autoBackupToggle.checked) {
      downloadBackupFromMemory();
      // Small delay to ensure backup download starts before save
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    editorStatus.textContent = "Saving...";
    saveTextBtn.disabled = true;

    try {
      const response = await fetch(
        `/x/texteditor.cgi?file=${encodePath(textEditorState.currentFile)}`,
        {
          method: "POST",
          body: textEditorEl.value,
        },
      );

      const data = await response.json();

      if (!response.ok || data.error) {
        throw new Error(
          data.error ? data.error.message : `HTTP ${response.status}`,
        );
      }

      textEditorState.originalContent = textEditorEl.value;
      textEditorState.isModified = false;
      saveTextBtn.disabled = true;

      editorStatus.textContent = "Saved successfully";
      showAlert(
        "success",
        `File saved: ${textEditorState.currentFile.split("/").pop()}`,
      );
    } catch (error) {
      editorStatus.textContent = `Save failed: ${error.message}`;
      saveTextBtn.disabled = !textEditorState.isModified;
      showAlert("danger", `Failed to save file: ${error.message}`);
    }
  }

  // Text editor event handlers
  textEditorEl.addEventListener("input", () => {
    // Check if content has been modified
    textEditorState.isModified =
      textEditorEl.value !== textEditorState.originalContent;
    saveTextBtn.disabled = !textEditorState.isModified;
  });

  lineWrappingToggle.addEventListener("change", function () {
    textEditorEl.style.whiteSpace = this.checked ? "pre-wrap" : "pre";
    textEditorEl.style.overflowX = this.checked ? "hidden" : "auto";
  });

  saveTextBtn.addEventListener("click", saveTextFile);

  reloadTextBtn.addEventListener("click", async () => {
    if (textEditorState.isModified) {
      if (!(await confirm("Discard unsaved changes and reload?"))) return;
    }
    if (textEditorState.currentFile) {
      loadTextFile(textEditorState.currentFile);
    }
  });

  downloadBackupBtn.addEventListener("click", downloadBackupFromMemory);

  textEditorModalEl.addEventListener("hidden.bs.modal", async () => {
    if (textEditorState.isModified) {
      if (
        await confirm(
          "You have unsaved changes. Do you want to save before closing?",
        )
      ) {
        saveTextFile();
      }
    }
    // Reset editor state
    textEditorState.currentFile = null;
    textEditorState.originalContent = null;
    textEditorState.isModified = false;
    textEditorEl.value = "";
    editorStatus.textContent = "Ready";
  });

  // Keyboard shortcuts for text editor
  textEditorEl.addEventListener("keydown", (event) => {
    // Ctrl+S to save
    if (event.ctrlKey && event.key === "s") {
      event.preventDefault();
      if (!saveTextBtn.disabled) {
        saveTextFile();
      }
    }
    // Tab key handling - insert spaces instead of changing focus
    if (event.key === "Tab") {
      event.preventDefault();
      const start = textEditorEl.selectionStart;
      const end = textEditorEl.selectionEnd;
      textEditorEl.value =
        textEditorEl.value.substring(0, start) +
        "  " +
        textEditorEl.value.substring(end);
      textEditorEl.selectionStart = textEditorEl.selectionEnd = start + 2;
      // Update modification state
      textEditorState.isModified =
        textEditorEl.value !== textEditorState.originalContent;
      saveTextBtn.disabled = !textEditorState.isModified;
    }
  });

  window.editFile = function (filePath) {
    const textEditorModal = new bootstrap.Modal(textEditorModalEl);
    textEditorModal.show();
    loadTextFile(filePath);
  };

  mergePluginSections();
  renderTabs();
  loadSection(parseInitialTab());
})();
