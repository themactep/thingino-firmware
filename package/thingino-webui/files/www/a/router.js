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

  // The pages that can be swapped in place come from the build: each one is
  // listed by the package that owns it (a "router" block in a plugin's
  // webui.json, or the core list of the webui package), and the plugin
  // assembly writes the list here only after checking every page on it. A
  // listed page has one page script, /a/<page>.js, wrapped in an IIFE, which
  // binds to the page's own content and leaves no window or document listener
  // or timer behind, so running it again against new content is the same as
  // a page load.
  const uiConfig = window.thinginoUIConfig || {};
  const PAGES = new Set(
    Array.isArray(uiConfig.routerPages) ? uiConfig.routerPages : [],
  );

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

  // Scripts the plugin assembly adds to every page are part of the shell.
  Object.values(uiConfig.plugins || {}).forEach((plugin) => {
    [...(plugin.scripts || []), ...(plugin.previewScripts || [])].forEach(
      (src) => SHARED_SCRIPTS.add(scriptName(src)),
    );
  });

  // Children of <main> .container that belong to the shell, not the page.
  const KEEP =
    "[data-generated-controls], [data-app-controls], [data-shell], #network-restart-notice";

  const BODY_SHELL_TAGS = new Set(["NAV", "MAIN", "FOOTER", "SCRIPT"]);

  let generation = 0;
  let swapping = 0;
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

  function isCode(el) {
    return !el.type || /javascript|module/i.test(el.type);
  }

  // The build checks the same things; a page changed on the camera, or one
  // from a newer image than this shell, is caught here.
  function scriptsSafe(doc, page) {
    const inline = [...doc.querySelectorAll("script:not([src])")].some(isCode);
    const headOk = [...doc.querySelectorAll("head script[src]")].every((el) => {
      const src = el.getAttribute("src") || "";
      return src.startsWith("/a/") && SHARED_SCRIPTS.has(scriptName(src));
    });
    const scripts = pageScriptsOf(doc);
    return (
      !inline &&
      headOk &&
      scripts.length === 1 &&
      scriptName(scripts[0]) === page + ".js"
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

  // A page script that throws while it loads leaves a half-built page. The
  // error is caught for the time of the load, and the caller falls back to a
  // full load of the page.
  function runPageScript(src) {
    document.querySelectorAll("body script[src]").forEach((el) => {
      if (isPageScript(el.getAttribute("src") || "")) el.remove();
    });
    return new Promise((resolve, reject) => {
      const script = document.createElement("script");
      let failure = null;
      const onError = (ev) => {
        if (!ev.filename || scriptName(ev.filename) === scriptName(src)) {
          failure = ev.error || new Error(ev.message || "page script error");
        }
      };
      window.addEventListener("error", onError);
      script.src = src;
      script.onload = () => {
        window.removeEventListener("error", onError);
        if (failure) reject(failure);
        else resolve();
      };
      script.onerror = () => {
        window.removeEventListener("error", onError);
        reject(new Error("page script did not load"));
      };
      document.body.appendChild(script);
    });
  }

  // Each history entry keeps its own scroll position, as a full page load
  // does: the browser's restoration is off while the router is in charge.
  function saveScroll() {
    // Not while the entry and the content differ: during a swap, and between
    // Back or Forward and the swap that follows it.
    if (swapping || location.pathname + location.search !== currentUrl) return;
    history.replaceState(
      {
        ...(history.state || {}),
        thinginoRoute: true,
        scrollY: window.scrollY,
      },
      "",
    );
  }

  function hashTarget(url) {
    if (!url.hash || url.hash === "#") return null;
    try {
      return document.getElementById(decodeURIComponent(url.hash.slice(1)));
    } catch (err) {
      return null;
    }
  }

  // Back and Forward return to where the entry was left; a link goes to its
  // #target, or to the top.
  // "instant": the pages scroll smoothly (scroll-behavior on :root), and a
  // page load does not animate to its position.
  function scrollToY(top) {
    window.scrollTo({ top, left: 0, behavior: "instant" });
  }

  function placeScroll(url, scrollY) {
    const target = hashTarget(url);
    if (typeof scrollY === "number") scrollToY(scrollY);
    else if (target) target.scrollIntoView({ behavior: "instant" });
    else scrollToY(0);
  }

  // A full load puts the keyboard and a screen reader at the start of the new
  // page. After a swap the focus would stay on the link that was followed, so
  // it moves to the page's heading, which a screen reader then announces.
  function focusContent(url) {
    const heading = [
      ...document.querySelectorAll("main h1, main h2, main h3"),
    ].find((h) => !h.closest(".modal") && h.getClientRects().length > 0);
    const el = hashTarget(url) || heading || document.querySelector("main");
    if (!el) return;
    if (!el.hasAttribute("tabindex")) el.setAttribute("tabindex", "-1");
    el.focus({ preventScroll: true });
  }

  async function swap(url, push, scrollY) {
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

    if (push) saveScroll();
    swapping++;
    try {
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
      if (push) {
        history.pushState({ thinginoRoute: true, scrollY: 0 }, "", url.href);
      }
      currentUrl = location.pathname + location.search;
      placeScroll(url, scrollY);
      if (
        window.thinginoNav &&
        typeof window.thinginoNav.refresh === "function"
      )
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
      if (gen !== generation) return;
      if (typeof window.thinginoInitContent === "function")
        added.forEach((node) => window.thinginoInitContent(node));
      // Again, now that the page script has filled the page in.
      placeScroll(url, scrollY);
      focusContent(url);
      document.dispatchEvent(
        new CustomEvent("thingino:page-swapped", {
          detail: { url: url.href },
        }),
      );
    } finally {
      swapping--;
    }
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
    let url;
    try {
      url = new URL(link.href, location.href);
    } catch (err) {
      return;
    }
    const samePage = url.pathname + url.search === currentUrl;
    if (
      (link.getAttribute("href") || "").startsWith("#") ||
      (url.hash && samePage)
    ) {
      // A #target of this page is the browser's to follow; the entry it
      // leaves keeps its position.
      if (url.hash) saveScroll();
      return;
    }
    if (!pageOf(url)) return;
    ev.preventDefault();
    // A link to the page that is showing loads it again and adds no entry,
    // as the browser does.
    swap(url, !samePage);
  });

  let scrollTimer = 0;
  window.addEventListener("popstate", (ev) => {
    clearTimeout(scrollTimer);
    const url = new URL(location.href);
    const saved =
      ev.state && typeof ev.state.scrollY === "number"
        ? ev.state.scrollY
        : null;
    if (location.pathname + location.search === currentUrl) {
      // Another entry of this page (a #target was followed): its position
      // is restored here too, the browser's restoration being off.
      placeScroll(url, saved === null ? undefined : saved);
      return;
    }
    if (pageOf(url)) swap(url, false, saved === null ? 0 : saved);
    else location.reload();
  });

  window.addEventListener(
    "scroll",
    () => {
      clearTimeout(scrollTimer);
      scrollTimer = setTimeout(saveScroll, 150);
    },
    { passive: true },
  );

  // A full load of an entry this router left (a reload, or Back from a page
  // outside the list) finds its position in the entry.
  const landed = history.state;
  if ("scrollRestoration" in history) history.scrollRestoration = "manual";
  if (landed && typeof landed.scrollY === "number") {
    scrollToY(landed.scrollY);
  }
  history.replaceState(
    { ...(landed || {}), thinginoRoute: true, scrollY: window.scrollY },
    "",
    location.href,
  );
  document.head.querySelectorAll("style").forEach((el) => {
    el.dataset.pageStyle = "";
  });
})();
