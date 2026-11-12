(function () {
  "use strict";

  if (
    window.thinginoRouter ||
    !window.history ||
    !window.fetch ||
    !window.DOMParser
  ) {
    return;
  }

  // Pages whose only page script, /a/<page>.js, binds to the page's own
  // content and leaves no window or document listener or timer behind, so
  // running it again against new content is the same as a page load.
  const PAGES = new Set([
    "config-admin",
    "config-network",
    "config-syslog",
    "config-time",
    "config-webui",
    "info",
    "info-diagnostic",
    "info-overlay",
    "info-usage",
    "tool-cameras",
    "tool-ping-trace",
    "tool-sdcard",
    "tool-send2",
    "tool-send2-email",
    "tool-send2-ftp",
    "tool-send2-gotify",
    "tool-send2-gphotos",
    "tool-send2-mqtt",
    "tool-send2-ntfy",
    "tool-send2-pushover",
    "tool-send2-storage",
    "tool-send2-telegram",
    "tool-send2-webhook",
    "tool-send2-xmpp",
  ]);

  const SHARED_SCRIPTS = new Set([
    "main.js",
    "runtime-config.js",
    "plugins.js",
    "control-bar.js",
    "navigation.js",
    "footer.js",
    "theme-init.js",
    "router.js",
  ]);

  // Children of <main> .container that belong to the shell, not the page.
  const KEEP =
    "[data-generated-controls], [data-app-controls], [data-shell], #network-restart-notice";

  const BODY_SHELL_TAGS = new Set(["NAV", "MAIN", "FOOTER", "SCRIPT"]);

  let generation = 0;
  let currentUrl = location.pathname + location.search;

  function pageOf(url) {
    if (url.origin !== location.origin) return null;
    const match = /^\/([a-z0-9-]+)\.html$/.exec(url.pathname);
    return match && PAGES.has(match[1]) ? match[1] : null;
  }

  function scriptName(src) {
    try {
      return new URL(src, location.href).pathname.replace(/^\/a\//, "");
    } catch (err) {
      return "";
    }
  }

  function isPageScript(src) {
    return (
      src.startsWith("/a/") &&
      !src.startsWith("/a/vendor/") &&
      !SHARED_SCRIPTS.has(scriptName(src))
    );
  }

  function pageScriptsOf(doc) {
    return [...doc.querySelectorAll("body script[src]")]
      .map((el) => el.getAttribute("src") || "")
      .filter(isPageScript);
  }

  function scriptsSafe(doc, page) {
    const inline = [...doc.querySelectorAll("body script:not([src])")].some(
      (el) => !el.type || /javascript|module/i.test(el.type),
    );
    const scripts = pageScriptsOf(doc);
    return (
      !inline && scripts.length === 1 && scriptName(scripts[0]) === page + ".js"
    );
  }

  function selfAndBelow(node, selector) {
    return [
      ...(node.matches(selector) ? [node] : []),
      ...node.querySelectorAll(selector),
    ];
  }

  function syncAttributes(el, from) {
    ["class", "style"].forEach((name) => {
      const value = from.getAttribute(name);
      if (value === null) el.removeAttribute(name);
      else el.setAttribute(name, value);
    });
  }

  function disposeContent(nodes) {
    if (!window.bootstrap) return;
    nodes.forEach((node) => {
      selfAndBelow(node, '[data-bs-toggle="tooltip"]').forEach((el) => {
        const tip = bootstrap.Tooltip.getInstance(el);
        if (tip) tip.dispose();
      });
      selfAndBelow(node, ".modal.show").forEach((el) => {
        const modal = bootstrap.Modal.getInstance(el);
        if (modal) modal.hide();
      });
    });
  }

  function closeMenus() {
    if (!window.bootstrap) return;
    document.querySelectorAll(".dropdown-menu.show").forEach((menu) => {
      const toggle = menu.parentElement
        ? menu.parentElement.querySelector('[data-bs-toggle="dropdown"]')
        : null;
      const dropdown = toggle ? bootstrap.Dropdown.getInstance(toggle) : null;
      if (dropdown) dropdown.hide();
    });
    document.querySelectorAll(".offcanvas.show").forEach((el) => {
      const offcanvas = bootstrap.Offcanvas.getInstance(el);
      if (offcanvas) offcanvas.hide();
    });
  }

  // control-bar.js marks its link to the current page only when it builds
  // the bar, which stays.
  function refreshControlBarCurrent() {
    document
      .querySelectorAll("[data-generated-controls] a[href]")
      .forEach((a) => {
        let path;
        try {
          path = new URL(a.href, location.href).pathname;
        } catch (err) {
          return;
        }
        if (path === location.pathname) {
          a.classList.add("active");
          a.setAttribute("aria-current", "page");
        } else if (a.getAttribute("aria-current") === "page") {
          a.classList.remove("active");
          a.removeAttribute("aria-current");
        }
      });
  }

  function runPageScript(src) {
    document.querySelectorAll("body script[src]").forEach((el) => {
      if (isPageScript(el.getAttribute("src") || "")) el.remove();
    });
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      script.src = src;
      script.onload = resolve;
      script.onerror = reject;
      document.body.appendChild(script);
    });
  }

  async function swap(url, push) {
    const gen = ++generation;
    const page = pageOf(url);
    let doc;
    try {
      const res = await fetch(url.href, {
        credentials: "same-origin",
        headers: { Accept: "text/html" },
      });
      if (!res.ok || res.redirected) throw new Error("HTTP " + res.status);
      doc = new DOMParser().parseFromString(await res.text(), "text/html");
    } catch (err) {
      location.assign(url.href);
      return;
    }
    if (gen !== generation) return;

    const next = doc.querySelector("main .container");
    const container = document.querySelector("main .container");
    const extras = [...doc.body.children].filter(
      (el) => !BODY_SHELL_TAGS.has(el.tagName),
    );
    const haveSheets = new Set(
      [...document.head.querySelectorAll('link[rel="stylesheet"]')].map((l) =>
        l.getAttribute("href"),
      ),
    );
    const newSheet = [
      ...doc.head.querySelectorAll('link[rel="stylesheet"]'),
    ].some((l) => !haveSheets.has(l.getAttribute("href")));
    if (
      !page ||
      !next ||
      !container ||
      !scriptsSafe(doc, page) ||
      newSheet ||
      extras.some((el) => !el.hasAttribute("data-page-extra"))
    ) {
      location.assign(url.href);
      return;
    }

    document.dispatchEvent(new CustomEvent("thingino:page-leave"));

    document.head
      .querySelectorAll("style[data-page-style]")
      .forEach((el) => el.remove());
    doc.head.querySelectorAll("style").forEach((el) => {
      const node = document.adoptNode(el);
      node.dataset.pageStyle = "";
      document.head.appendChild(node);
    });

    const old = [
      ...[...container.children].filter((el) => !el.matches(KEEP)),
      ...document.querySelectorAll("body > [data-page-extra]"),
    ];
    disposeContent(old);
    old.forEach((el) => el.remove());

    syncAttributes(container, next);
    const main = container.closest("main");
    const nextMain = next.closest("main");
    if (main && nextMain) syncAttributes(main, nextMain);

    const added = [];
    [...next.children].forEach((el) => {
      if (el.matches("[data-app-controls]")) return;
      const node = document.adoptNode(el);
      container.appendChild(node);
      added.push(node);
    });
    extras.forEach((el) => {
      const node = document.adoptNode(el);
      document.body.appendChild(node);
      added.push(node);
    });

    document.title = doc.title;
    document.body.id = doc.body.id;
    if (doc.body.dataset.navLabel) {
      document.body.dataset.navLabel = doc.body.dataset.navLabel;
    } else {
      delete document.body.dataset.navLabel;
    }
    closeMenus();
    if (push) history.pushState({ thinginoRoute: true }, "", url.href);
    currentUrl = location.pathname + location.search;
    window.scrollTo(0, 0);
    if (window.thinginoNav && typeof window.thinginoNav.refresh === "function")
      window.thinginoNav.refresh();
    refreshControlBarCurrent();

    // The page script reads location (info.html?<name>), so it runs after
    // the URL has changed.
    try {
      await runPageScript(pageScriptsOf(doc)[0]);
    } catch (err) {
      location.reload();
      return;
    }
    if (typeof window.thinginoInitContent === "function")
      added.forEach((node) => window.thinginoInitContent(node));
    document.dispatchEvent(
      new CustomEvent("thingino:page-swapped", { detail: { url: url.href } }),
    );
  }

  const loadedPage = pageOf(new URL(location.href));
  const active = Boolean(loadedPage) && scriptsSafe(document, loadedPage);
  window.thinginoRouter = {
    active,
    go(href) {
      const url = new URL(href, location.href);
      if (active && pageOf(url)) swap(url, true);
      else location.assign(url.href);
    },
  };
  if (!active) return;

  document.addEventListener("click", (ev) => {
    if (ev.defaultPrevented || ev.button !== 0) return;
    if (ev.metaKey || ev.ctrlKey || ev.shiftKey || ev.altKey) return;
    const link = ev.target.closest && ev.target.closest("a[href]");
    if (!link || link.target || link.hasAttribute("download")) return;
    if ((link.getAttribute("href") || "").startsWith("#")) return;
    let url;
    try {
      url = new URL(link.href, location.href);
    } catch (err) {
      return;
    }
    if (!pageOf(url)) return;
    if (url.hash && url.pathname + url.search === currentUrl) return;
    ev.preventDefault();
    swap(url, true);
  });

  window.addEventListener("popstate", () => {
    if (location.pathname + location.search === currentUrl) return;
    const url = new URL(location.href);
    if (pageOf(url)) swap(url, false);
    else location.reload();
  });

  history.replaceState({ thinginoRoute: true }, "", location.href);
  document.head.querySelectorAll("style").forEach((el) => {
    el.dataset.pageStyle = "";
  });
})();
