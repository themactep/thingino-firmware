/**
 * SEI Rotation — applies CSS rotation to preview <img> elements
 * based on stream rotation from /x/json-osd-sei.cgi.
 * Lightweight, no overlay. Include on any page with a preview image.
 */
(function () {
  "use strict";
  var SEI_URL = "/x/json-osd-sei.cgi";
  var IMG_IDS = ["preview"];

  function rotateImg(img, rot) {
    if (rot) {
      img.style.transform = "rotate(" + rot + "deg)";
    }
  }

  function apply() {
    fetch(SEI_URL)
      .then(function (r) {
        if (!r.ok) return;
        return r.json();
      })
      .then(function (d) {
        if (!d || !d.rotation) return;
        var rot = d.rotation;
        for (var i = 0; i < IMG_IDS.length; i++) {
          var img = document.getElementById(IMG_IDS[i]);
          if (img) rotateImg(img, rot);
        }
      })
      .catch(function () {});
  }

  // Apply once on load
  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", apply);
  } else {
    apply();
  }

  // Retry faster initially (preview.js changes src after load)
  setTimeout(apply, 500);
  setTimeout(apply, 1500);
  // Keep checking periodically
  setInterval(apply, 5000);
})();
