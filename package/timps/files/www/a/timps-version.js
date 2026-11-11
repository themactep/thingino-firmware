(function () {
  "use strict";
  if (!window.timpsApi) return;

  function footerRightCol() {
    var footer = document.querySelector('footer[data-generated-footer="true"]');
    return footer ? footer.querySelector(".text-sm-end") : null;
  }

  function render(v) {
    var rightCol = footerRightCol();
    if (rightCol) {
      var el = document.createElement("div");
      el.className = "small";
      el.textContent = "timps " + v;
      el.title = "timps build version";
      rightCol.appendChild(el);
      return;
    }
    var badge = document.createElement("div");
    badge.textContent = v;
    badge.title = "timps build version";
    badge.style.cssText =
      "position:fixed;right:6px;bottom:3px;font-size:.7rem;opacity:.35;" +
      "font-family:monospace;pointer-events:none;z-index:1;user-select:none;";
    document.body.appendChild(badge);
  }

  function tryRender() {
    window.timpsApi.get().then(function (j) {
      var v = j && j.version;
      if (!v) return;
      render(v);
    }).catch(function () {});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", tryRender, { once: true });
  } else {
    tryRender();
  }
})();
