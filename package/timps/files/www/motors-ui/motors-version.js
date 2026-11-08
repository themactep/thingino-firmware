(function () {
  "use strict";

  function footerRightCol() {
    var footer = document.querySelector('footer[data-generated-footer="true"]');
    return footer ? footer.querySelector(".text-sm-end") : null;
  }

  function tryRender() {
    var rightCol = footerRightCol();
    if (!rightCol) return;

    fetch("/x/json-motor.cgi?d=j", { cache: "no-store" })
      .then(function (res) {
        if (!res.ok) throw new Error("HTTP " + res.status);
        return res.json();
      })
      .then(function (j) {
        var v = j && j.message && j.message.version;
        if (!v) return;
        var el = document.createElement("div");
        el.className = "small";
        el.textContent = "motors " + v;
        el.title = "motors-daemon build version";
        rightCol.appendChild(el);
      })
      .catch(function () {});
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", tryRender, { once: true });
  } else {
    tryRender();
  }
})();
