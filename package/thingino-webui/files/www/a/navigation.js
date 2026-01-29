(function () {
  'use strict';

  const uiConfig = window.thinginoUIConfig || {};
  const globalConfig = uiConfig.nav || window.thinginoNavConfig || window.navConfig || {};

  function buildDefaultMenu() {
    const hasMotors = uiConfig.device && uiConfig.device.motors === true;
    const settingsItems = [
      { label: 'Admin profile', href: '/config-admin.html' },
      { label: 'GPIO pins', href: '/config-gpio.html' }
    ];

    if (hasMotors) {
      settingsItems.push({ label: 'Pan/Tilt motors', href: '/config-motors.html' });
    }

    settingsItems.push(
      { label: 'Network', href: '/config-network.html' },
      { label: 'Audio', href: '/config-audio.html' },
      { label: 'Privacy screen', href: '/config-privacy.html' },
      { label: 'Photosensing', href: '/config-photosensing.html' },
      { label: 'RTSP/ONVIF access', href: '/config-rtsp.html' },
      { label: 'Remote logging', href: '/config-syslog.html' },
      { label: 'Telegram Bot', href: '/config-telegrambot.html' },
      { label: 'Time', href: '/config-time.html' },
      { label: 'Web Interface', href: '/config-webui.html' },
      { label: 'WireGuard VPN', href: '/config-wireguard.html' },
      { label: 'ZeroTier VPN', href: '/config-zerotier.html' },
      { type: 'divider' },
      { label: 'Reset...', href: '/reset.html' }
    );

    return [
      {
        type: 'dropdown',
        id: 'ddInfo',
        label: 'Information',
        items: [
          { label: 'Commands and logs', href: '/info.html' },
          { label: 'Overlay partition', href: '/info-overlay.html' },
          { label: 'System usage', href: '/info-usage.html' },
          { label: 'Diagnostic info', href: '/info-diagnostic.html' },
          { type: 'divider' },
          { label: 'Prudynt log', href: '/info.html?prudynt' },
          { label: 'Restart Prudynt', href: '#', id: 'restart-prudynt-nav', className: 'text-danger confirm', trackActive: false }
        ]
      },
      {
        type: 'dropdown',
        id: 'ddSettings',
        label: 'Settings',
        items: settingsItems
      },
      {
        type: 'dropdown',
        id: 'ddTools',
        label: 'Tools',
        items: [
          { label: 'File manager', href: '/tool-file-manager.html' },
          { label: 'Network test', href: '/tool-ping-trace.html' },
          { label: 'SD card', href: '/tool-sdcard.html' },
          { label: 'Send to services', href: '/tool-send2.html' },
          { label: 'Flash operations', href: '/tool-upgrade.html' },
          { type: 'divider' },
          { label: 'Reboot camera', href: '/x/reboot.cgi', className: 'text-danger confirm' }
        ]
      },
      {
        type: 'dropdown',
        id: 'ddServices',
        label: 'Services',
        items: [
          { label: 'Timelapse Recorder', href: '/tool-timelapse.html' },
          { label: 'Video Recorder', href: '/tool-record.html' }
        ]
      },
      {
        type: 'dropdown',
        id: 'ddStreamer',
        label: 'Streamer',
        items: [
          { label: 'Image Quality', href: '/streamer-image.html' },
          { label: 'RTSP Main stream', href: '/streamer-main.html' },
          { label: 'Main stream OSD', href: '/streamer-osd0.html' },
          { label: 'RTSP Substream', href: '/streamer-substream.html' },
          { label: 'Substream OSD', href: '/streamer-osd1.html' },
          { label: 'Sensor IQ File', href: '/streamer-sensor.html' }
        ]
      },
      { type: 'link', label: 'Preview', href: '/preview.html' },
      {
        type: 'dropdown',
        id: 'ddHelp',
        label: 'Help',
        menuClass: 'dropdown-menu dropdown-menu-lg-end',
        items: [
          { label: 'About thingino', href: 'https://thingino.com/', target: '_blank', rel: 'noreferrer noopener', trackActive: false },
          { label: 'Thingino Wiki', href: 'https://github.com/themactep/thingino-firmware/wiki', target: '_blank', rel: 'noreferrer noopener', trackActive: false }
        ]
      }
    ];
  }

  const menuData = Array.isArray(globalConfig.items) && globalConfig.items.length ? globalConfig.items : buildDefaultMenu();

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
      // ignore and fall back to raw string
    }
    if (!path) return '/';
    path = path.split('?')[0].split('#')[0];
    if (path.length > 1 && path.endsWith('/')) {
      return path.replace(/\/+$/, '');
    }
    return path || '/';
  }

  function deriveBrandLabel(title) {
    if (typeof globalConfig.brandLabel === 'string' && globalConfig.brandLabel.trim()) {
      return globalConfig.brandLabel.trim();
    }
    if (document.body && document.body.dataset && document.body.dataset.navLabel) {
      return document.body.dataset.navLabel;
    }
    if (!title) return 'thingino';
    const parts = title.split(/·|-|—/).map(part => part.trim()).filter(Boolean);
    if (parts.length >= 2) {
      return parts[1];
    }
    if (parts.length === 1) {
      return parts[0];
    }
    return 'thingino';
  }

  function createAnchor(item, defaultClass) {
    const anchor = document.createElement('a');
    const classes = [defaultClass];
    if (item.className) {
      classes.push(item.className);
    }
    anchor.className = classes.join(' ');
    anchor.href = item.href;
    anchor.textContent = item.label;
    if (item.target) anchor.target = item.target;
    if (item.rel) anchor.rel = item.rel;
    if (item.title) anchor.title = item.title;
    const shouldTrack = item.trackActive !== false && typeof item.href === 'string' && item.href.startsWith('/');
    if (shouldTrack) {
      anchor.dataset.navPath = normalizePath(item.href);
    }
    return anchor;
  }

  function createDropdown(section) {
    const li = document.createElement('li');
    li.className = 'nav-item dropdown';

    const toggle = document.createElement('a');
    toggle.className = 'nav-link dropdown-toggle';
    toggle.href = '#';
    toggle.id = section.id;
    toggle.role = 'button';
    toggle.setAttribute('data-bs-toggle', 'dropdown');
    toggle.setAttribute('aria-expanded', 'false');
    toggle.textContent = section.label;

    const menu = document.createElement('ul');
    menu.className = section.menuClass || 'dropdown-menu';
    if (section.id) {
      menu.setAttribute('aria-labelledby', section.id);
    }

    (section.items || []).forEach(item => {
      const itemLi = document.createElement('li');
      if (item.type === 'divider') {
        const divider = document.createElement('hr');
        divider.className = item.className || 'dropdown-divider';
        itemLi.appendChild(divider);
      } else {
        const anchor = createAnchor(item, 'dropdown-item');
        itemLi.appendChild(anchor);
      }
      menu.appendChild(itemLi);
    });

    li.appendChild(toggle);
    li.appendChild(menu);
    return li;
  }

  function createLinkItem(item) {
    const li = document.createElement('li');
    li.className = 'nav-item';
    li.appendChild(createAnchor(item, 'nav-link'));
    return li;
  }

  function buildNav(menuItems) {
    const nav = document.createElement('nav');
    nav.className = 'navbar navbar-expand-lg navbar-dark bg-dark sticky-top';
    nav.setAttribute('data-generated-nav', 'true');

    const container = document.createElement('div');
    container.className = 'container';

    const brand = document.createElement('a');
    brand.className = 'navbar-brand d-flex align-items-center gap-3';
    brand.href = typeof globalConfig.brandHref === 'string' ? globalConfig.brandHref : '/';

    const brandLogo = document.createElement('img');
    brandLogo.alt = globalConfig.brandLogoAlt || 'Thingino logo';
    brandLogo.width = 150;
    brandLogo.src = globalConfig.brandLogo || '/a/logo.svg';
    brand.appendChild(brandLogo);

    const brandText = document.createElement('span');
    brandText.textContent = deriveBrandLabel(document.title || '');
    brand.appendChild(brandText);

    const toggler = document.createElement('button');
    toggler.className = 'navbar-toggler';
    toggler.type = 'button';
    toggler.setAttribute('data-bs-toggle', 'offcanvas');
    toggler.setAttribute('data-bs-target', '#navOffcanvas');
    toggler.setAttribute('aria-controls', 'navOffcanvas');
    toggler.setAttribute('aria-label', 'Toggle navigation');
    toggler.innerHTML = '<span class="navbar-toggler-icon"></span>';

    const collapse = document.createElement('div');
    collapse.className = 'collapse navbar-collapse justify-content-end d-none d-lg-flex';
    collapse.id = 'nbMain';

    const list = document.createElement('ul');
    list.className = 'navbar-nav';

    menuItems.forEach(item => {
      if (item.type === 'dropdown') {
        list.appendChild(createDropdown(item));
      } else {
        list.appendChild(createLinkItem(item));
      }
    });

    collapse.appendChild(list);

    // Offcanvas menu (visible on small screens)
    const offcanvas = document.createElement('div');
    offcanvas.className = 'offcanvas offcanvas-end d-lg-none';
    offcanvas.id = 'navOffcanvas';
    offcanvas.tabIndex = -1;
    offcanvas.setAttribute('aria-labelledby', 'navOffcanvasLabel');

    const offcanvasHeader = document.createElement('div');
    offcanvasHeader.className = 'offcanvas-header';

    const offcanvasTitle = document.createElement('h5');
    offcanvasTitle.className = 'offcanvas-title';
    offcanvasTitle.id = 'navOffcanvasLabel';
    offcanvasTitle.textContent = 'Menu';

    const closeBtn = document.createElement('button');
    closeBtn.type = 'button';
    closeBtn.className = 'btn-close';
    closeBtn.setAttribute('data-bs-dismiss', 'offcanvas');
    closeBtn.setAttribute('aria-label', 'Close');

    offcanvasHeader.appendChild(offcanvasTitle);
    offcanvasHeader.appendChild(closeBtn);

    const offcanvasBody = document.createElement('div');
    offcanvasBody.className = 'offcanvas-body';

    const offcanvasList = createOffcanvasList(menuItems);
    offcanvasBody.appendChild(offcanvasList);

    offcanvas.appendChild(offcanvasHeader);
    offcanvas.appendChild(offcanvasBody);

    container.appendChild(brand);
    container.appendChild(toggler);
    container.appendChild(collapse);
    container.appendChild(offcanvas);
    nav.appendChild(container);
    return nav;
  }

  function createOffcanvasList(menuItems) {
    const list = document.createElement('ul');
    list.className = 'list-unstyled';

    // Reorder items for offcanvas: Preview link first, then others
    const reorderedItems = [];
    const otherItems = [];

    menuItems.forEach(item => {
      if (item.type === 'link' && item.label === 'Preview') {
        reorderedItems.push(item);
      } else {
        otherItems.push(item);
      }
    });

    // Combine with Preview first
    const finalItems = [...reorderedItems, ...otherItems];

    finalItems.forEach(item => {
      if (item.type === 'dropdown') {
        const section = document.createElement('li');
        section.className = 'mb-3';

        const heading = document.createElement('h6');
        heading.className = 'text-uppercase text-secondary mb-2';
        heading.textContent = item.label;
        section.appendChild(heading);

        const subList = document.createElement('ul');
        subList.className = 'list-unstyled ms-3';

        item.items.forEach(subItem => {
          if (subItem.type === 'divider') {
            const divider = document.createElement('li');
            divider.innerHTML = '<hr class="my-2">';
            subList.appendChild(divider);
          } else {
            const li = document.createElement('li');
            li.className = 'mb-1';
            const anchor = createAnchor(subItem, 'd-block py-1 text-decoration-none');
            if (subItem.id) anchor.id = subItem.id + '-offcanvas';

            // Handle navigation after offcanvas closes
            anchor.addEventListener('click', function(e) {
              const href = this.getAttribute('href');
              if (href && href !== '#') {
                e.preventDefault();
                const offcanvasEl = $('#navOffcanvas');
                if (offcanvasEl && window.bootstrap) {
                  const offcanvasInstance = bootstrap.Offcanvas.getInstance(offcanvasEl) || new bootstrap.Offcanvas(offcanvasEl);
                  offcanvasEl.addEventListener('hidden.bs.offcanvas', function() {
                    window.location.href = href;
                  }, { once: true });
                  offcanvasInstance.hide();
                } else {
                  window.location.href = href;
                }
              }
            });

            li.appendChild(anchor);
            subList.appendChild(li);
          }
        });

        section.appendChild(subList);
        list.appendChild(section);
      } else {
        const li = document.createElement('li');
        li.className = 'mb-2';
        const anchor = createAnchor(item, 'd-block fw-bold text-decoration-none p-3');

        // Handle navigation after offcanvas closes
        anchor.addEventListener('click', function(e) {
          const href = this.getAttribute('href');
          if (href && href !== '#') {
            e.preventDefault();
            const offcanvasEl = $('#navOffcanvas');
            if (offcanvasEl && window.bootstrap) {
              const offcanvasInstance = bootstrap.Offcanvas.getInstance(offcanvasEl) || new bootstrap.Offcanvas(offcanvasEl);
              offcanvasEl.addEventListener('hidden.bs.offcanvas', function() {
                window.location.href = href;
              }, { once: true });
              offcanvasInstance.hide();
            } else {
              window.location.href = href;
            }
          }
        });

        li.appendChild(anchor);
        list.appendChild(li);
      }
    });

    return list;
  }

  function highlightActive(nav, currentPath) {
    const normalizedCurrent = normalizePath(currentPath || window.location.pathname);
    const anchors = nav.querySelectorAll('a[data-nav-path]');
    anchors.forEach(anchor => {
      if (anchor.dataset.navPath === normalizedCurrent) {
        anchor.classList.add('active');
        const dropdown = anchor.closest('.dropdown');
        if (dropdown) {
          const toggle = dropdown.querySelector('.nav-link.dropdown-toggle');
          if (toggle) toggle.classList.add('active');
        }
      }
    });
  }

  function rebuildControlBarIfReady() {
    if (window.thinginoControlBar && typeof window.thinginoControlBar.rebuild === 'function') {
      window.thinginoControlBar.rebuild();
    }
  }

  function bindControlBarLoad(scriptEl) {
    if (!scriptEl || scriptEl.dataset.controlBarBound === 'true') return;
    scriptEl.addEventListener('load', rebuildControlBarIfReady, { once: true });
    scriptEl.dataset.controlBarBound = 'true';
  }

  function ensureControlBarScript() {
    if (!document.querySelector('[data-app-controls]')) return;
    if (window.thinginoControlBar && typeof window.thinginoControlBar.rebuild === 'function') {
      window.thinginoControlBar.rebuild();
      return;
    }
    const existingScript = document.querySelector('script[data-control-bar-autoload], script[src*="/a/control-bar.js"]');
    if (existingScript) {
      bindControlBarLoad(existingScript);
      return;
    }
    const script = document.createElement('script');
    script.src = globalConfig.controlBarSrc || '/a/control-bar.js';
    script.defer = true;
    script.dataset.controlBarAutoload = 'true';
    bindControlBarLoad(script);
    (document.head || document.body || document.documentElement).appendChild(script);
  }

  function attachPrudyntHandlers(nav) {
    const restartPrudyntLink = nav.querySelector('#restart-prudynt-nav');
    const restartPrudyntOffcanvas = nav.querySelector('#restart-prudynt-nav-offcanvas');

    const restartHandler = function(e) {
      // Let the confirmation system handle the dialog first
      if (this.classList && this.classList.contains('confirm') && this.dataset.confirmBypass !== '1') {
        return; // Let the confirmation system handle this click
      }

      e.preventDefault();
      if (window.thinginoFooter && typeof window.thinginoFooter.restartPrudynt === 'function') {
        window.thinginoFooter.restartPrudynt();
      } else {
        console.warn('thinginoFooter.restartPrudynt not available yet');
      }
    };

    if (restartPrudyntLink) {
      restartPrudyntLink.addEventListener('click', restartHandler);
    }
    if (restartPrudyntOffcanvas) {
      restartPrudyntOffcanvas.addEventListener('click', restartHandler);
    }
  }

  function mountNavigation() {
    const nav = buildNav(menuData);
    const placeholder = document.querySelector('[data-app-nav]');
    const existing = document.querySelector('nav[data-generated-nav="true"]');
    if (placeholder && placeholder.parentNode) {
      placeholder.parentNode.replaceChild(nav, placeholder);
    } else if (existing && existing.parentNode) {
      existing.parentNode.replaceChild(nav, existing);
    } else if (document.body) {
      document.body.insertAdjacentElement('afterbegin', nav);
    }
    highlightActive(nav, globalConfig.activePath);
    attachPrudyntHandlers(nav);
    ensureControlBarScript();
  }

  ready(mountNavigation);

  window.thinginoNav = {
    rebuild: mountNavigation,
    menu: menuData
  };
})();
