/* recordings.js - browse/play/download/delete the timps SD recordings listed
 * by /x/json-recordings.cgi (a filesystem helper). Playback + download stream
 * the segment from the same CGI (?file=<rel>). Free-space is read from timps
 * GET /control (record.free_mb) when available. Dependency-free. */
(function () {
  "use strict";

  if (!document.body || document.body.id !== "page-recordings") return;

  var LIST = "/x/json-recordings.cgi";
  var listEl = document.getElementById("rec-list");
  var infoEl = document.getElementById("rec-info");
  var reloadBtn = document.getElementById("rec-reload");
  var video = document.getElementById("rec-video");
  var modalEl = document.getElementById("recModal");
  var modal = null;

  function toast(type, msg, ms) {
    if (typeof window.showAlert === "function") window.showAlert(type, msg, ms);
    else console.log("[recordings]", type + ":", msg);
  }

  function human(bytes) {
    var b = Number(bytes) || 0;
    if (b < 1024) return b + " B";
    if (b < 1048576) return (b / 1024).toFixed(0) + " KB";
    if (b < 1073741824) return (b / 1048576).toFixed(1) + " MB";
    return (b / 1073741824).toFixed(2) + " GB";
  }

  // "20260712/09/20260712T095252" -> a readable local timestamp; fall back to
  // the file mtime when the name isn't the default pattern.
  function labelFor(rel, mtime) {
    var m = /(\d{8})T(\d{2})(\d{2})(\d{2})/.exec(rel);
    if (m) {
      var d = m[1], H = m[3] ? m[2] : "";
      return d.slice(0, 4) + "-" + d.slice(4, 6) + "-" + d.slice(6, 8) +
        " " + m[2] + ":" + m[3] + ":" + m[4];
    }
    if (mtime) return new Date(Number(mtime) * 1000).toLocaleString();
    return rel;
  }

  function url(action, rel) {
    return LIST + "?" + action + "=" + encodeURIComponent(rel);
  }

  function play(rel, label) {
    if (!video) return;
    video.src = url("file", rel);
    var title = document.getElementById("recModalTitle");
    if (title) title.textContent = label;
    if (!modal && window.bootstrap) modal = new window.bootstrap.Modal(modalEl);
    if (modal) modal.show();
    video.play().catch(function () { /* user can press play */ });
  }

  function del(rel, tr) {
    if (!window.confirm("Delete this recording?\n" + rel)) return;
    fetch(url("del", rel), { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function () { if (tr) tr.remove(); toast("success", "Recording deleted.", 2500); })
      .catch(function (e) { toast("danger", "Delete failed: " + (e.message || e)); });
  }

  function render(files) {
    listEl.innerHTML = "";
    if (!files.length) {
      listEl.innerHTML = '<tr><td colspan="4" class="text-secondary">No recordings found.</td></tr>';
      return;
    }
    files.forEach(function (f) {
      var label = labelFor(f.file, f.mtime);
      var tr = document.createElement("tr");
      var actions = document.createElement("td");
      actions.className = "text-end";

      var playBtn = document.createElement("button");
      playBtn.className = "btn btn-sm btn-primary me-1";
      playBtn.innerHTML = '<i class="bi bi-play-fill"></i>';
      playBtn.title = "Play";
      playBtn.addEventListener("click", function () { play(f.file, label); });

      var dl = document.createElement("a");
      dl.className = "btn btn-sm btn-outline-secondary me-1";
      dl.href = url("file", f.file);
      dl.setAttribute("download", f.file.replace(/\//g, "_"));
      dl.title = "Download";
      dl.innerHTML = '<i class="bi bi-download"></i>';

      var delBtn = document.createElement("button");
      delBtn.className = "btn btn-sm btn-outline-danger";
      delBtn.innerHTML = '<i class="bi bi-trash"></i>';
      delBtn.title = "Delete";
      delBtn.addEventListener("click", function () { del(f.file, tr); });

      actions.appendChild(playBtn); actions.appendChild(dl); actions.appendChild(delBtn);

      var tdWhen = document.createElement("td"); tdWhen.textContent = label;
      var tdSeg = document.createElement("td");
      // textContent, not innerHTML: the segment name comes from the SD card and
      // must never be interpreted as HTML (stored-XSS otherwise).
      var segSpan = document.createElement("span");
      segSpan.className = "text-secondary small";
      segSpan.textContent = f.file;
      tdSeg.appendChild(segSpan);
      var tdSize = document.createElement("td"); tdSize.className = "text-end"; tdSize.textContent = human(f.size);

      tr.appendChild(tdWhen); tr.appendChild(tdSeg); tr.appendChild(tdSize); tr.appendChild(actions);
      listEl.appendChild(tr);
    });
  }

  function load() {
    listEl.innerHTML = '<tr><td colspan="4" class="text-secondary">Loading…</td></tr>';
    fetch(LIST, { cache: "no-store" })
      .then(function (r) { if (!r.ok) throw new Error("HTTP " + r.status); return r.json(); })
      .then(function (data) {
        render(data.files || []);
        if (infoEl) infoEl.textContent = (data.files || []).length + " segment(s) · " + (data.base || "");
      })
      .catch(function (e) {
        listEl.innerHTML = '<tr><td colspan="4" class="text-danger">Failed to list recordings: ' +
          (e.message || e) + "</td></tr>";
      });
    // free space (best effort)
    if (window.timpsApi) {
      window.timpsApi.get().then(function (j) {
        var fm = j && j.record && j.record.free_mb;
        if (infoEl && fm != null && fm >= 0) infoEl.textContent += " · " + fm + " MB free";
      }).catch(function () {});
    }
  }

  if (modalEl) modalEl.addEventListener("hidden.bs.modal", function () {
    if (video) { video.pause(); video.removeAttribute("src"); video.load(); }
  });
  if (reloadBtn) reloadBtn.addEventListener("click", load);

  if (document.readyState === "loading")
    document.addEventListener("DOMContentLoaded", load, { once: true });
  else load();
})();
