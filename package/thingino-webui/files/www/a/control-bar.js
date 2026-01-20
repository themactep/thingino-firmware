(function () {
  'use strict';

  const uiConfig = window.thinginoUIConfig || {};
  const globalConfig = uiConfig.controlBar || window.thinginoControlBarConfig || {};

  function ready(fn) {
    if (document.readyState === 'loading') {
      document.addEventListener('DOMContentLoaded', fn, { once: true });
    } else {
      fn();
    }
  }

  function normalizePath(input) {
    if (!input) return '/';
    let path = input;
    try {
      const url = new URL(input, window.location.origin);
      path = url.pathname;
    } catch (err) {
      // ignore parsing issues and fall back to input
    }
    if (!path) return '/';
    const trimmed = path.split('?')[0].split('#')[0];
    if (trimmed.length > 1 && trimmed.endsWith('/')) {
      return trimmed.replace(/\/+$/, '');
    }
    return trimmed || '/';
  }

  function isCurrentPath(targetPath) {
    if (!targetPath) return false;
    const current = normalizePath(globalConfig.activePath || window.location.pathname);
    const target = normalizePath(targetPath);
    return current === target;
  }

  function createIcon(iconClass, title) {
    const icon = document.createElement('i');
    icon.className = iconClass;
    if (title) icon.title = title;
    return icon;
  }

  function appendLabelWithIcon(el, iconClass, title, label) {
    if (iconClass) {
      const icon = createIcon(iconClass, title);
      el.appendChild(icon);
      el.appendChild(document.createTextNode(' '));
    }
    if (label) {
      el.appendChild(document.createTextNode(label));
    }
  }

  function createButton(options) {
    const button = document.createElement('button');
    button.type = 'button';
    button.className = options.className || 'btn btn-secondary';
    if (options.id) button.id = options.id;
    if (options.title) button.title = options.title;
    if (options.dataset) {
      Object.keys(options.dataset).forEach(key => {
        button.dataset[key] = options.dataset[key];
      });
    }
    if (options.attributes) {
      Object.keys(options.attributes).forEach(key => {
        button.setAttribute(key, options.attributes[key]);
      });
    }
    appendLabelWithIcon(button, options.icon, options.iconTitle || options.title, options.label);
    return button;
  }

  function createRecorderGroup() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    // Main stream recorder button (channel 0)
    const ch0Button = createButton({
      id: 'recorder-ch0',
      title: 'Main stream recorder',
      icon: 'bi bi-camera-reels',
      label: 'Rec ch0',
      dataset: { channel: '0' }
    });

    // Substream recorder button (channel 1)
    const ch1Button = createButton({
      id: 'recorder-ch1',
      title: 'Substream recorder',
      icon: 'bi bi-camera-reels',
      label: 'Rec ch1',
      dataset: { channel: '1' }
    });

    // Timelapse button
    const timelapseButton = createButton({
      id: 'timelapse',
      title: 'Timelapse',
      icon: 'bi bi-camera',
      label: 'Timelapse'
    });

    // Dropdown toggle
    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Recorder options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle recorder menu';
    toggle.appendChild(srOnly);

    // Dropdown menu
    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';

    // Recording configuration link
    const recordItem = document.createElement('li');
    const recordLink = document.createElement('a');
    recordLink.className = 'dropdown-item';
    recordLink.href = '/tool-record.html';
    recordLink.title = 'Recording configuration';
    if (isCurrentPath('/tool-record.html')) {
      recordLink.classList.add('active');
      recordLink.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(recordLink, 'bi bi-gear', 'Recording configuration', 'Recording settings');
    recordItem.appendChild(recordLink);
    menu.appendChild(recordItem);

    // Timelapse configuration link
    const timelapseItem = document.createElement('li');
    const timelapseLink = document.createElement('a');
    timelapseLink.className = 'dropdown-item';
    timelapseLink.href = '/tool-timelapse.html';
    timelapseLink.title = 'Timelapse configuration';
    if (isCurrentPath('/tool-timelapse.html')) {
      timelapseLink.classList.add('active');
      timelapseLink.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(timelapseLink, 'bi bi-stopwatch', 'Timelapse configuration', 'Timelapse settings');
    timelapseItem.appendChild(timelapseLink);
    menu.appendChild(timelapseItem);

    group.appendChild(ch0Button);
    group.appendChild(ch1Button);
    group.appendChild(timelapseButton);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createRecorderButton(channel) {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      id: `recorder-ch${channel}`,
      title: channel === 0 ? 'Main stream recorder' : 'Substream recorder',
      icon: 'bi bi-record',
      label: 'Recording',
      dataset: { channel: channel.toString() }
    });

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Recorder options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle recorder menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/tool-record.html';
    link.title = 'Recording configuration';
    if (isCurrentPath('/tool-record.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Recording configuration', 'Recording settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createSendButton() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      title: 'Send snapshot',
      icon: 'bi bi-send',
      label: 'Send...',
      attributes: {
        'data-bs-toggle': 'modal',
        'data-bs-target': '#sendModal'
      }
    });

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Send-to options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle send menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/tool-send2.html';
    link.title = 'Send-to configuration';
    if (isCurrentPath('/tool-send2.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Send-to configuration', 'Send-to settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createMotionGuardButton() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      id: 'motion',
      title: 'Motion Guard',
      icon: 'bi bi-person-walking',
      label: 'Motion'
    });

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Motion options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle motion menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/tool-send2.html';
    link.title = 'Motion Guard configuration';
    if (isCurrentPath('/tool-send2.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Motion Guard configuration', 'Motion settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createPrivacyModeButton() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      id: 'privacy',
      title: 'Privacy mode',
      icon: 'bi bi-eye-slash',
      label: 'Privacy'
    });

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Privacy options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle privacy menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/config-privacy.html';
    link.title = 'Privacy screen configuration';
    if (isCurrentPath('/config-privacy.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Privacy screen configuration', 'Privacy settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createAudioControlGroup() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    // Microphone button
    const micButton = createButton({
      id: 'microphone',
      title: 'Microphone',
      icon: 'bi bi-mic',
      label: 'Mic'
    });

    // Speaker button
    const spkButton = createButton({
      id: 'speaker',
      title: 'Speaker',
      icon: 'bi bi-volume-up',
      label: 'Speaker'
    });

    // Dropdown toggle
    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Audio options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle audio menu';
    toggle.appendChild(srOnly);

    // Dropdown menu
    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/config-audio.html';
    link.title = 'Audio configuration';
    if (isCurrentPath('/config-audio.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Audio configuration', 'Audio settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(micButton);
    group.appendChild(spkButton);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createAudioControlButton(options) {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton(options);

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Audio options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle audio menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/config-audio.html';
    link.title = 'Audio configuration';
    if (isCurrentPath('/config-audio.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'Audio configuration', 'Audio settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createDropdownMenu() {
    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';

    const items = [
      { type: 'button', id: 'auto', icon: 'bi bi-magic', label: 'Auto mode', title: 'Auto mode' },
      { type: 'button', id: 'day', icon: 'bi bi-sun', label: 'Day mode', title: 'Day mode' },
      { type: 'button', id: 'night', icon: 'bi bi-moon', label: 'Night mode', title: 'Night mode' },
      { type: 'divider' },
      { type: 'button', id: 'color', icon: 'bi bi-palette', label: 'Color', title: 'Color mode' },
      { type: 'button', id: 'ircut', icon: 'bi bi-transparency', label: 'IR filter', title: 'IR filter' },
      { type: 'button', id: 'ir850', icon: 'bi bi-lightbulb', label: 'IR LED 850 nm', title: 'IR LED 850 nm' },
      { type: 'button', id: 'ir940', icon: 'bi bi-lightbulb', label: 'IR LED 940 nm', title: 'IR LED 940 nm' },
      { type: 'button', id: 'white', icon: 'bi bi-lightbulb', label: 'White LED', title: 'White LED' },
      { type: 'divider' },
      {
        type: 'link',
        href: '/tool-sensor-data.html',
        icon: 'bi bi-graph-up',
        label: 'Sensor Data Collector',
        title: 'Sensor Data Collector'
      }
    ];

    items.forEach(item => {
      const li = document.createElement('li');
      if (item.type === 'divider') {
        const divider = document.createElement('hr');
        divider.className = 'dropdown-divider';
        li.appendChild(divider);
      } else if (item.type === 'link') {
        const anchor = document.createElement('a');
        anchor.className = 'dropdown-item';
        anchor.href = item.href;
        if (item.title) anchor.title = item.title;
        const isActive = isCurrentPath(item.href);
        if (isActive) {
          anchor.classList.add('active');
          anchor.setAttribute('aria-current', 'page');
        }
        appendLabelWithIcon(anchor, item.icon, item.title, item.label);
        li.appendChild(anchor);
      } else {
        const btn = createButton({
          id: item.id,
          title: item.title,
          icon: item.icon,
          iconTitle: item.title,
          label: item.label,
          className: 'dropdown-item btn btn-secondary'
        });
        li.appendChild(btn);
      }
      menu.appendChild(li);
    });

    return menu;
  }

  function createWireGuardButton() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      id: 'wireguard',
      title: 'WireGuard VPN',
      icon: 'bi bi-shield-lock',
      label: 'VPN'
    });

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'VPN options',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });
    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle VPN menu';
    toggle.appendChild(srOnly);

    const menu = document.createElement('ul');
    menu.className = 'dropdown-menu';
    const item = document.createElement('li');
    const link = document.createElement('a');
    link.className = 'dropdown-item';
    link.href = '/config-wireguard.html';
    link.title = 'WireGuard configuration';
    if (isCurrentPath('/config-wireguard.html')) {
      link.classList.add('active');
      link.setAttribute('aria-current', 'page');
    }
    appendLabelWithIcon(link, 'bi bi-gear', 'WireGuard configuration', 'VPN settings');
    item.appendChild(link);
    menu.appendChild(item);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(menu);
    return group;
  }

  function createDayNightGroup() {
    const group = document.createElement('div');
    group.className = 'btn-group';
    group.setAttribute('role', 'group');

    const button = createButton({
      id: 'daynight',
      title: 'Night mode',
      icon: 'bi bi-sun',
      iconTitle: 'Day mode',
      label: ''
    });

    const text = document.createElement('span');
    text.id = 'daynight-text';
    text.textContent = '----';
    button.appendChild(document.createTextNode(' '));
    button.appendChild(text);

    const toggle = createButton({
      className: 'btn btn-secondary dropdown-toggle dropdown-toggle-split',
      title: 'Toggle dropdown',
      attributes: {
        'data-bs-toggle': 'dropdown',
        'aria-expanded': 'false'
      },
      label: ''
    });

    const gain = document.createElement('span');
    gain.id = 'daynight-gain';
    gain.className = 'dnd-gain x-small me-1';
    gain.title = 'Gain';
    gain.textContent = '---';
    toggle.appendChild(gain);

    const srOnly = document.createElement('span');
    srOnly.className = 'visually-hidden';
    srOnly.textContent = 'Toggle Dropdown';
    toggle.appendChild(srOnly);

    group.appendChild(button);
    group.appendChild(toggle);
    group.appendChild(createDropdownMenu());
    return group;
  }

  function buildButtonBar() {
    const bar = document.createElement('div');
    bar.id = 'button-bar';
    bar.className = 'd-flex align-items-stretch gap-1 mb-2 flex-wrap';

    const motionBtn = createMotionGuardButton();
    motionBtn.classList.add('flex-fill');
    bar.appendChild(motionBtn);

    const privacyBtn = createPrivacyModeButton();
    privacyBtn.classList.add('flex-fill');
    bar.appendChild(privacyBtn);

    const wireguardBtn = createWireGuardButton();
    wireguardBtn.classList.add('flex-fill');
    bar.appendChild(wireguardBtn);

    const sendBtn = createSendButton();
    sendBtn.classList.add('flex-fill');
    bar.appendChild(sendBtn);

    const daynightBtn = createDayNightGroup();
    daynightBtn.classList.add('flex-fill');
    bar.appendChild(daynightBtn);

    const audioBtn = createAudioControlGroup();
    audioBtn.classList.add('flex-fill');
    bar.appendChild(audioBtn);

    const recorderBtn = createRecorderGroup();
    recorderBtn.classList.add('flex-fill');
    bar.appendChild(recorderBtn);

    return bar;
  }

  function buildTimeColumn(className) {
    const col = document.createElement('div');
    col.className = className;
    const link = document.createElement('a');
    link.href = '/config-time.html';
    link.id = 'time-now';
    link.className = 'link-underline link-underline-opacity-0 link-underline-opacity-75-hover';
    col.appendChild(link);
    return col;
  }

  function buildControlRow(placeholder) {
    const defaults = {
      wrapperClass: globalConfig.wrapperClass || '',
      timeRowClass: globalConfig.timeRowClass || 'row my-2 x-small align-items-center',
      timeColClass: globalConfig.clockColClass || 'col-12 text-lg-end',
      buttonRowClass: globalConfig.rowClass || 'row my-2 x-small align-items-center',
      buttonColClass: globalConfig.btnColClass || 'col-12'
    };

    const wrapper = document.createElement('div');
    const wrapperClass = placeholder.dataset.wrapperClass || defaults.wrapperClass;
    if (wrapperClass) wrapper.className = wrapperClass;
    wrapper.setAttribute('data-generated-controls', 'true');

    const timeRow = document.createElement('div');
    timeRow.className = placeholder.dataset.clockRow || placeholder.dataset.timeRow || defaults.timeRowClass;
    timeRow.appendChild(buildTimeColumn(placeholder.dataset.clockCol || defaults.timeColClass));

    const buttonRow = document.createElement('div');
    buttonRow.className = placeholder.dataset.rowClass || defaults.buttonRowClass;
    const buttonCol = document.createElement('div');
    buttonCol.className = placeholder.dataset.btnCol || defaults.buttonColClass;
    buttonCol.appendChild(buildButtonBar());
    buttonRow.appendChild(buttonCol);

    wrapper.appendChild(timeRow);
    wrapper.appendChild(buttonRow);
    return wrapper;
  }


  function mountControlBars() {
    const placeholders = document.querySelectorAll('[data-app-controls]');
    if (!placeholders.length) return;
    placeholders.forEach(placeholder => {
      if (!placeholder.parentNode) return;
      const row = buildControlRow(placeholder);
      placeholder.parentNode.replaceChild(row, placeholder);
    });
  }

  ready(mountControlBars);

  window.thinginoControlBar = {
    rebuild: mountControlBars
  };
})();
