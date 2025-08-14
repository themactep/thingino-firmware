#!/bin/haserl
<%in _common.cgi %>
<%
page_title="Local Recordings Gallery"

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------
# Provide sane defaults in case configuration file is missing.
# These variables may be overridden by /etc/thingino.config which is already
# sourced by _common.cgi
#
# send_local_save_dir  – the directory where send2local stores files
# ---------------------------------------------------------------------------

default_for send_local_save_dir "/mnt/records"

dir="$send_local_save_dir"

# ---------------------------------------------------------------------------
# Helper: ensure requested path stays inside $dir
# ---------------------------------------------------------------------------
safe_path() {
    case "$1" in
        "$dir"/*) return 0 ;;
        *)          return 1 ;;
    esac
}

# ---------------------------------------------------------------------------
# Helper: serve video file with HTTP range support
# ---------------------------------------------------------------------------
serve_video() {
    local file="$1"
    safe_path "$file" || redirect_back "danger" "Forbidden"
    [ -f "$file" ] || redirect_back "danger" "File $file not found"
    local filelength=$(stat -c%s "$file")

    # Pick MIME type by extension
    local mime="video/mp4"
    case "${file##*.}" in
        mov|MOV) mime="video/quicktime" ;;
    esac

    # If browser did not request a range, send entire file
    if ! env | grep -q ^HTTP_RANGE; then
        http_header "HTTP/1.1 200 OK"
        http_header "Content-Type: $mime"
        http_header "Accept-Ranges: bytes"
        http_header "Content-Length: $filelength"
        http_header "Content-Disposition: inline; filename=$(basename "$file")"
        http_header
        cat "$file"
        exit 0
    fi

    # Parse range header "bytes=start-end"
    local start=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $3}')
    [ -z "$start" ] && start=0
    if [ "$start" -gt "$filelength" ]; then
        http_header "HTTP/1.1 416 Requested Range Not Satisfiable"
        http_header "Content-Range: bytes */$filelength"
        http_header
        exit 0
    fi
    local end=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $4}')
    [ -z "$end" ] && end=$((filelength - 1))
    local blocksize=$((end - start + 1))

    http_header "HTTP/1.1 206 Partial Content"
    http_header "Content-Type: $mime"
    http_header "Accept-Ranges: bytes"
    http_header "Content-Range: bytes $start-$end/$filelength"
    http_header "Content-Length: $blocksize"
    http_header
    dd if="$file" skip=$start bs=1 count=$blocksize iflag=skip_bytes
    exit 0
}

# Stream / download handlers -------------------------------------------------
if [ -n "$GET_play" ]; then
    serve_video "$GET_play"
fi

if [ -n "$GET_dl" ]; then
    file="$GET_dl"
    safe_path "$file" || redirect_back "danger" "Forbidden"
    length=$(stat -c%s "$file")
    timemodepoch=$(stat -c%Y "$file")
    timestamp=$(TZ=GMT0 date +"%a, %d %b %Y %T %Z" --date="@$timemodepoch")
    http_header "HTTP/1.0 200 OK"
    http_header "Date: $timestamp"
    http_header "Server: $SERVER_SOFTWARE"
    http_header "Content-type: application/octet-stream"
    http_header "Content-Length: $length"
    http_header "Content-Disposition: attachment; filename=$(basename "$file")"
    http_header "Cache-Control: no-store"
    http_header "Pragma: no-cache"
    http_header
    cat "$file"
    exit 0
fi
%>
<%in _header.cgi %>
<%
# Ensure directory exists so that user sees meaningful message
[ -d "$dir" ] || mkdir -p "$dir"

# Gather list of recorded video thumbnails
list=$(ls -1t $dir/*.jpg 2>/dev/null | tr '\n' ' ')
%>

<% if [ -z "$list" ]; then %>
<div class="alert alert-info">No saved videos found in <code><%= $dir %></code>.</div>
<% else %>
<div class="row row-cols-2 row-cols-md-3 row-cols-lg-4 g-3">
<%
for f in $list; do
    # Skip if glob returned the literal pattern (when no match)
    [ -f "$f" ] || continue
    thumb="$f"
    base=$(basename "$f")
    name_noext="${base%.*}"
    vid="$dir/${name_noext}.mp4"
    if [ ! -f "$vid" ]; then
		vid="$dir/${name_noext}.mov"
	fi

%>
  <div class="col">
    <div class="card h-100 shadow-sm">
      <a href="?play=<%= $vid %>" data-bs-toggle="modal" data-bs-target="#playerModal" data-bs-url="?play=<%= $vid %>" class="position-relative">
        <img src="?dl=<%= $thumb %>" class="card-img-top" alt="<%= $base %>">
        <span class="position-absolute top-0 start-0 badge rounded-pill bg-dark m-2">▶</span>
      </a>
      <div class="card-body p-2">
        <p class="card-text small text-center"><%= $name_noext %></p>
      </div>
    </div>
  </div>
<%
done
%>
</div>

<!-- Video player modal -->
<div class="modal fade" id="playerModal" tabindex="-1" aria-labelledby="playerModalLabel" aria-hidden="true">
  <div class="modal-dialog modal-dialog-centered modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h1 class="modal-title fs-5" id="playerModalLabel">Video Player</h1>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body"></div>
      <div class="modal-footer">
        <a href="#" class="btn btn-primary" id="playerModalDownload">Download</a>
        <button type="button" class="btn btn-secondary" data-bs-dismiss="modal">Close</button>
      </div>
    </div>
  </div>
</div>
<% fi %>

<script>
const videoPlayer = document.createElement("video");
videoPlayer.id = "player";
videoPlayer.classList.add("w-100", "img-fluid");
videoPlayer.controls = true;

const playerModal = document.querySelector("#playerModal");
playerModal.querySelector('.modal-body').append(videoPlayer);

playerModal.addEventListener("show.bs.modal", ev => {
  const btn = ev.relatedTarget;
  const url = btn.dataset.bsUrl;
  document.querySelector('#playerModalLabel').textContent = url.replace('?play=', '');
  document.querySelector('#playerModalDownload').href = url.replace('?play=', '?dl=');
  videoPlayer.src = url;
  (async () => {
    try { await videoPlayer.play(); } catch(e) { console.debug(e); }
  })();
});

playerModal.addEventListener("hidden.bs.modal", () => {
  videoPlayer.pause();
});
</script>

<%in _footer.cgi %>
