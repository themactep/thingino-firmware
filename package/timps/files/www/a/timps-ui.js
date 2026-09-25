// timps-ui.js - stream tabs, restart bar and live/restart badges shared by the video pages.
(function () {
  "use strict";

  var pending = [];
  var curStream = -1;
  var onRestarted = null;

  function toast(type, message, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, message, ms);
    else console.log("[timps-ui]", type + ":", message);
  }

  function initialStream() {
    var m = /[?&]s=([01])\b/.exec(location.search);
    if (m) return +m[1];
    try {
      var v = localStorage.getItem("timps-stream");
      if (v === "0" || v === "1") return +v;
    } catch (e) {}
    return 0;
  }

  // Wire the [data-stream-tab] buttons; onChange(i) runs on user switches.
  function initTabs(onChange) {
    var tabs = document.querySelectorAll("[data-stream-tab]");
    function set(i, fire) {
      curStream = i;
      Array.prototype.forEach.call(tabs, function (t) {
        var on = +t.getAttribute("data-stream-tab") === i;
        t.classList.toggle("active", on);
        t.setAttribute("aria-selected", String(on));
      });
      try { localStorage.setItem("timps-stream", String(i)); } catch (e) {}
      try {
        var u = new URL(location.href);
        u.searchParams.set("s", String(i));
        history.replaceState(null, "", u);
      } catch (e) {}
      var pv = document.getElementById("preview");
      if (pv) {
        pv.setAttribute("data-stream", "ch" + i);
        if (fire && window.restartStreamPreview) window.restartStreamPreview();
      }
      if (fire) {
        onChange(i);
        document.dispatchEvent(new CustomEvent("timps-stream", { detail: i }));
      }
    }
    Array.prototype.forEach.call(tabs, function (t) {
      t.addEventListener("click", function () { set(+t.getAttribute("data-stream-tab"), true); });
    });
    var cur = initialStream();
    set(cur, false);
    return cur;
  }

  function setTabSummary(i, text) {
    var el = document.querySelector('[data-stream-tab="' + i + '"] small');
    if (el) el.textContent = text;
  }

  function badge(live) {
    return '<span class="tv-badge ' + (live ? "live" : "rst") + '">' +
      (live ? "live" : "restart") + "</span>";
  }

  function bar() {
    var b = document.getElementById("tv-pending");
    if (b) return b;
    b = document.createElement("div");
    b.id = "tv-pending";
    b.className = "tv-pending";
    b.hidden = true;
    b.innerHTML =
      '<b>Waiting for a streamer restart:</b><span class="tv-keys"></span>' +
      '<button type="button" class="btn btn-sm btn-outline-secondary tv-later">Later</button>' +
      '<button type="button" class="btn btn-sm btn-warning tv-restart">' +
      '<i class="bi bi-arrow-clockwise me-1"></i>Restart streamer</button>';
    document.body.appendChild(b);
    b.querySelector(".tv-later").addEventListener("click", function () { b.hidden = true; });
    b.querySelector(".tv-restart").addEventListener("click", restart);
    return b;
  }

  function markPending(keys) {
    (keys || []).forEach(function (k) { if (pending.indexOf(k) < 0) pending.push(k); });
    if (!pending.length) return;
    var b = bar();
    b.querySelector(".tv-keys").textContent = pending.join(", ");
    b.hidden = false;
  }

  function waitBack(tries) {
    if (!window.timpsApi) return;
    window.timpsApi.get().then(function () {
      toast("success", "Streamer is back.", 3000);
      document.dispatchEvent(new Event("timps-back"));
      if (onRestarted) onRestarted();
    }, function () {
      if (tries > 0) setTimeout(function () { waitBack(tries - 1); }, 2000);
    });
  }

  function restart() {
    var b = bar();
    b.querySelector(".tv-restart").disabled = true;
    fetch("/x/restart-prudynt.cgi", { cache: "no-store", credentials: "same-origin" })
      .then(function (r) {
        if (!r.ok) throw new Error("HTTP " + r.status);
        pending = [];
        b.hidden = true;
        toast("info", "Restarting the streamer…", 4000);
        setTimeout(function () { waitBack(15); }, 4000);
      })
      .catch(function (err) { toast("danger", "Restart failed: " + err.message); })
      .then(function () { b.querySelector(".tv-restart").disabled = false; });
  }

  // [data-page-tab=name] buttons switch [data-page-pane=name]; #name deep-links
  function initPageTabs() {
    var tabs = document.querySelectorAll("[data-page-tab]");
    if (!tabs.length) return;
    function show(name) {
      var ok = document.querySelector('[data-page-pane="' + name + '"]');
      if (!ok) name = tabs[0].getAttribute("data-page-tab");
      Array.prototype.forEach.call(tabs, function (t) {
        var on = t.getAttribute("data-page-tab") === name;
        t.classList.toggle("active", on);
        t.setAttribute("aria-selected", String(on));
      });
      Array.prototype.forEach.call(document.querySelectorAll("[data-page-pane]"), function (p) {
        p.hidden = p.getAttribute("data-page-pane") !== name;
      });
      document.body.setAttribute("data-pane", name);
    }
    Array.prototype.forEach.call(tabs, function (t) {
      t.addEventListener("click", function () {
        var n = t.getAttribute("data-page-tab");
        try { history.replaceState(null, "", "#" + n); } catch (e) {}
        show(n);
      });
    });
    window.addEventListener("hashchange", function () { show(location.hash.slice(1)); });
    show(location.hash.slice(1));
  }
  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", initPageTabs, { once: true });
  else initPageTabs();

  // file card backed by /x/timps-upload.cgi?kind=K; markup uses data-up=kind|info|file|reset|hint
  function uploadCard(root, kind, pendingKey, onInfo) {
    if (!root) return;
    var q = function (n) { return root.querySelector('[data-up="' + n + '"]'); };
    function show(j, changed) {
      var k = q("kind");
      k.textContent = j.custom ? "custom" : "stock";
      k.className = "tv-badge " + (j.custom ? "rst" : "live");
      q("info").textContent = j.file.replace(/.*\//, "") + " · " + Math.round(j.size / 1024) + " KB · md5 " + j.md5.slice(0, 8);
      q("info").title = j.file + "\nmd5 " + j.md5;
      q("reset").hidden = !(j.custom && j.stock);
      if (onInfo) onInfo(j, changed);
    }
    function call(method, extra, body) {
      q("hint").textContent = method === "GET" ? "" : "working…";
      return fetch("/x/timps-upload.cgi?kind=" + kind + (extra || ""), {
        method: method, body: body, credentials: "same-origin", cache: "no-store",
        headers: body ? { "Content-Type": "application/octet-stream" } : undefined,
      }).then(function (r) {
        return r.json().then(function (j) {
          if (!r.ok) throw new Error(j.error || "HTTP " + r.status);
          return j;
        });
      }).then(function (j) {
        q("hint").textContent = "";
        if (method !== "GET") markPending([pendingKey]);
        show(j, method !== "GET");
      }, function (err) {
        q("hint").textContent = "";
        if (method === "GET") q("info").textContent = "unavailable: " + err.message;
        else toast("danger", pendingKey + ": " + err.message);
      });
    }
    call("GET");
    q("file").addEventListener("change", function () {
      var f = this.files[0];
      this.value = "";
      if (f) call("POST", "", f);
    });
    q("reset").addEventListener("click", function () { call("POST", "&reset", ""); });
  }

  window.timpsUi = {
    uploadCard: uploadCard,
    initTabs: initTabs,
    stream: function () { return curStream >= 0 ? curStream : initialStream(); },
    setTabSummary: setTabSummary,
    badge: badge,
    markPending: markPending,
    onRestarted: function (fn) { onRestarted = fn; },
    toast: toast,
  };
})();
