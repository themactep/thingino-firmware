/**
 * SEI Rotation — applies CSS rotation to preview <img> elements
 * via SSE connection to /x/json-osd-sei.cgi.
 */
(function () {
  "use strict";
  var SSE_URL = "/x/json-osd-sei.cgi";
  var IMG_IDS = ["preview"];
  var source = null;
  var applied = false;

  function rotateImg(img, rot) {
    if (rot) img.style.transform = "rotate(" + rot + "deg)";
    var frame = document.getElementById("frame");
    if (frame) {
      if (rot === 90 || rot === 270) {
        var pad = img.clientWidth - img.clientHeight;
        if (pad > 0) {
          frame.style.paddingBottom = pad / 2 + "px";
          frame.style.paddingTop = pad / 2 + "px";
        }
      } else {
        frame.style.paddingBottom = "";
        frame.style.paddingTop = "";
      }
    }
  }

  function applyRotation(d) {
    if (!d || !d.rotation) return;
    var rot = d.rotation;
    for (var i = 0; i < IMG_IDS.length; i++) {
      var img = document.getElementById(IMG_IDS[i]);
      if (img) rotateImg(img, rot);
    }
    applied = true;
    // Close SSE — we only need the first rotation event.
    if (source) {
      source.close();
      source = null;
    }
  }

  function start() {
    // preview.html handles rotation itself; skip to avoid double connections.
    if (window.location.pathname === "/preview.html") return;
    if (!document.getElementById("preview")) return;
    if (source) return;

    source = new EventSource(SSE_URL);
    source.onmessage = function (e) {
      try {
        applyRotation(JSON.parse(e.data));
      } catch (_) {}
    };
    source.onerror = function () {
      if (source) {
        source.close();
        source = null;
      }
      // Retry after a delay.
      setTimeout(function () {
        if (!applied) start();
      }, 2000);
    };
  }

  // Re-apply on preview src change (preview.js replaces the img).
  var observer = new MutationObserver(function () {
    if (applied) {
      setTimeout(function () {
        applied = false;
        start();
      }, 200);
    }
  });
  function watch() {
    for (var i = 0; i < IMG_IDS.length; i++) {
      var img = document.getElementById(IMG_IDS[i]);
      if (img && img.parentNode) {
        observer.observe(img.parentNode, { childList: true });
      }
    }
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", function () {
      start();
      watch();
    });
  } else {
    start();
    watch();
  }
})();
