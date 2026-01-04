  </div><!-- .container -->
</main>

<footer class="x-small text-secondary">
  <div class="container pt-3">
    <div class="row">
      <div class="col col-sm-5 mb-2">
        <div><%= $network_hostname %></div>
        <div><%= $network_macaddr %></div>
        <div id="uptime"></div>
      </div>
      <div class="col col-sm-7 mb-2">
        <div class="text-sm-end">
          <div>Powered by <a href="https://thingino.com/">Thingino</a></div>
          <div><%= $BUILD_ID %></div>
          <div><%= $IMAGE_ID %></div>
        </div>
      </div>
    </div>
  </div>
</footer>

<div id="debug-wrap">
  <button type="button" class="btn btn-outline-secondary" id="debug" value="1" title="Debug info">
    <i class="bi bi-bug" style="font-size: 2rem"></i>
  </button>
</div>

<div class="modal fade" id="sendModal" tabindex="-1" aria-labelledby="sendModalLabel" aria-hidden="true">
  <div class="modal-dialog modal-lg">
    <div class="modal-content">
      <div class="modal-header">
        <h5 class="modal-title" id="sendModalLabel">Send snapshot/videoclip to...</h5>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body">
        <div class="row g-2">
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary text-start w-100" data-sendto="email" title="Send as configured">
                <i class="bi bi-envelope-at"></i> Email
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="email" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="email" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=email" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="ftp" title="Send as configured">
                <i class="bi bi-postage"></i> FTP
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="ftp" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="ftp" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=ftp" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="mqtt" title="Send as configured">
                <i class="bi bi-postage"></i> MQTT
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="mqtt" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="mqtt" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=mqtt" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="ntfy" title="Send as configured">
                <i class="bi bi-postage"></i> Ntfy
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="ntfy" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="ntfy" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=ntfy" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="storage" title="Send as configured">
                <i class="bi bi-sd-card"></i> Storage
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="storage" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="storage" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=storage" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="telegram" title="Send as configured">
                <i class="bi bi-telegram"></i> Telegram
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="telegram" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="telegram" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=telegram" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <button type="button" class="btn btn-outline-primary w-100 text-start" data-sendto="webhook" title="Send as configured">
                <i class="bi bi-postage"></i> Webhook
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="webhook" data-type="photo" title="Send photo only">
                <i class="bi bi-image"></i>
              </button>
              <button type="button" class="btn btn-outline-primary flex-shrink-0" data-sendto="webhook" data-type="video" title="Send video only">
                <i class="bi bi-film"></i>
              </button>
              <a href="tool-send2.cgi?tab=webhook" class="btn btn-outline-secondary flex-shrink-0" title="Configure">
                <i class="bi bi-gear"></i>
              </a>
            </div>
          </div>
          <div class="col-6">
            <div class="btn-group d-flex" role="group">
              <a href="image.cgi" target="_blank" class="btn btn-outline-primary w-100 text-start" title="Save image">
                <i class="bi bi-download"></i> Download
              </a>
            </div>
          </div>
        </div>
      </div>
    </div>
  </div>
</div>

<script>
document.addEventListener('DOMContentLoaded', () => {
  const modal = bootstrap.Modal.getInstance(document.getElementById('sendModal')) || new bootstrap.Modal(document.getElementById('sendModal'));
  document.querySelectorAll('#sendModal button[data-sendto]').forEach(btn => {
    btn.addEventListener('click', () => {
      modal.hide();
    });
  });
});
</script>

</body>
</html>
