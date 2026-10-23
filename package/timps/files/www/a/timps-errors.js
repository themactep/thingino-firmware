(function () {
  "use strict";

  var ERR_V = 1;

  function fam() {
    var soc = window.thinginoUIConfig && window.thinginoUIConfig.device &&
      window.thinginoUIConfig.device.soc;
    var m = soc && String(soc).toLowerCase().match(/^(t\d+|c\d+)/);
    return m ? m[1] : "";
  }

  function rotAlign(f) {
    if (f === "t31") return "width and height must be multiples of 64, e.g. 1280×704 or 640×384";
    if (f === "t23") return "the height must be a multiple of 16";
    if (/^t(10|20|21)$/.test(f)) return "width and height must be multiples of 16, e.g. 640×368";
    return "width and height are not aligned for rotation";
  }

  var TEXT = {
    101: "value refused (empty or not allowed)",
    102: "unknown setting for this streamer build",
    103: "can only be set in /etc/timps.conf",
    104: "not supported on this SoC",
    201: "this rotation is not available on this camera",
    202: "only the substream can be rotated on this SoC",
    203: rotAlign,
    204: function (f) { return "picture too large for rotation (at most " + (f === "t31" ? "1280×704" : "704×576") + ")"; },
    205: "frame rate too high for rotation (at most 15 fps)",
    206: "the installed libimp cannot rotate (needs OpenIMP with T1x rotation)",
    207: "the streamer's libimp refused the rotation at start (see the log)",
    208: "the height must be at least 256 for rotation",
  };

  function text(code) {
    var t = TEXT[code];
    if (typeof t === "function") t = t(fam());
    return t || "error " + code;
  }

  function list(errors) {
    return Object.keys(errors || {}).map(function (k) { return k + ": " + text(errors[k]); });
  }

  function rotFit(code, v) {
    var f = fam(), w = +v.width, h = +v.height, fps = +v.fps;
    var L = f === "t31" ? [1280, 704, 64, 64, 15, 0] : f === "t23" ? [704, 576, 16, 32, 15, 256] :
      /^t(10|20|21)$/.test(f) ? [704, 576, 16, 16, 0, 0] : null;
    if (!L || !w || !h || [203, 204, 205, 208].indexOf(code) < 0) return null;
    var s = Math.min(1, L[0] / w, L[1] / h);
    function al(x, a, m) { var r = Math.round(x / a) * a; return r > m ? Math.floor(m / a) * a : r; }
    var nw = al(w * s, L[2], L[0]), nh = al(h * s, L[3], L[1]);
    if (L[5] && nh < L[5]) { nh = L[5]; nw = al(nh * w / h, L[2], L[0]); }
    var nf = L[4] && fps > L[4] ? L[4] : fps;
    if (nw === w && nh === h && nf === fps) return null;
    return { width: nw, height: nh, fps: nf };
  }

  window.timpsErrors = {
    v: ERR_V,
    rotFit: rotFit,
    known: function (code) { return Object.prototype.hasOwnProperty.call(TEXT, code); },
    text: text,
    list: list,
  };
})();
