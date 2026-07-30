/**
 * SEI Rotation — applies CSS rotation to preview <img> elements
 * via polling /x/json-osd-sei.cgi every 2s.  Stops after first
 * rotation is received; re-starts on preview img src change.
 */
(function () {
  "use strict";
  var POLL_URL = "http://" + window.location.hostname + ":8080/api/v1/osd-sei";
  var POLL_MS = 2000;
  var IMG_IDS = ["preview"];
  var timer = null;
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

  function poll() {
    fetch(POLL_URL, { cache: "no-store" })
      .then(function (r) {
        return r.json();
      })
      .then(function (d) {
        if (!d || !d.rotation) return;
        var rot = d.rotation;
        for (var i = 0; i < IMG_IDS.length; i++) {
          var img = document.getElementById(IMG_IDS[i]);
          if (img) rotateImg(img, rot);
        }
        applied = true;
        if (timer) {
          clearInterval(timer);
          timer = null;
        }
      })
      .catch(function () {});
  }

  function start() {
    // preview.html handles rotation itself; skip to avoid double-polling.
    if (window.location.pathname === "/preview.html") return;
    if (!document.getElementById("preview")) return;
    if (timer) return;
    poll();
    timer = setInterval(poll, POLL_MS);
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
