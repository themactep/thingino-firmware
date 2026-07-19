/**
 * SEI Rotation — applies CSS rotation to preview <img> elements
 * via SSE stream from /x/json-osd-sei.cgi.
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

  function handleEvent(event) {
    try {
      var d = JSON.parse(event.data);
      if (!d || !d.rotation) return;
      var rot = d.rotation;
      for (var i = 0; i < IMG_IDS.length; i++) {
        var img = document.getElementById(IMG_IDS[i]);
        if (img) rotateImg(img, rot);
      }
      applied = true;
    } catch (_) {}
  }

  function start() {
    if (source) return;
    source = new EventSource(SSE_URL);
    source.onmessage = handleEvent;
    source.onerror = function () {
      source.close();
      source = null;
      if (!applied) setTimeout(start, 3000);
    };
  }

  // Also re-apply on preview src change (preview.js replaces the img)
  var observer = new MutationObserver(function () {
    if (applied) {
      // Re-apply to new img elements
      setTimeout(function () {
        if (source && source.readyState === EventSource.OPEN) return;
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
