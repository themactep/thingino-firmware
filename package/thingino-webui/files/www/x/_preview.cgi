<div class="modal fade" id="mdPreview" tabindex="-1" aria-labelledby="mdlPreview" aria-hidden="true">
  <div class="modal-dialog modal-fullscreen">
    <div class="modal-content">
      <div class="modal-header">
        <h1 class="modal-title fs-4" id="mdlPreview">Full screen preview</h1>
        <button type="button" class="btn-close" data-bs-dismiss="modal" aria-label="Close"></button>
      </div>
      <div class="modal-body text-center">
        <img id="preview_fullsize" src="/a/nostream.webp" alt="Image: Stream Preview" class="img-fluid">
      </div>
    </div>
  </div>
</div>

<script>
const mdPreview = document.getElementById('mdPreview');
const previewTrigger = document.getElementById('preview');
let lastFocusedElement = null;

mdPreview.addEventListener('show.bs.modal', () => {
  lastFocusedElement = document.activeElement || previewTrigger;
  $('#preview_fullsize').src = '/x/ch0.mjpg';
});

mdPreview.addEventListener('hide.bs.modal', () => {
  if (mdPreview.contains(document.activeElement)) {
    document.activeElement.blur();
  }
  $('#preview_fullsize').src = '/a/nostream.webp';
});

mdPreview.addEventListener('hidden.bs.modal', () => {
  const target = lastFocusedElement && typeof lastFocusedElement.focus === 'function'
    ? lastFocusedElement
    : previewTrigger;
  if (target && typeof target.focus === 'function') {
    target.focus({ preventScroll: true });
  }
});
</script>
