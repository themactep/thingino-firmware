/**
 * SEI Rotation — applies CSS rotation to preview <img> elements
 * via SSE to /x/json-osd-sei.cgi.  Closes after first rotation received.
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

  function handle(e) {
    try {
      var d = JSON.parse(e.data);
      if (d && d.rotation) {
        for (var i = 0; i < IMG_IDS.length; i++) {
          var img = document.getElementById(IMG_IDS[i]);
          if (img) rotateImg(img, d.rotation);
        }
        applied = true;
        if (source) {
          source.close();
          source = null;
        }
      }
    } catch (_) {}
  }

  function start() {
    if (window.location.pathname === "/preview.html") return;
    if (!document.getElementById("preview")) return;
    if (source) return;
    source = new EventSource(SSE_URL);
    source.onmessage = handle;
    source.onerror = function () {
      if (source) {
        source.close();
        source = null;
      }
      if (!applied) setTimeout(start, 5000);
    };
  }

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
      if (img && img.parentNode)
        observer.observe(img.parentNode, { childList: true });
    }
  }

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", function () {
      start();
      watch();
    });
  else {
    start();
    watch();
  }
})();
