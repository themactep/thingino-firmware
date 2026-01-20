(function () {
    const params = new URLSearchParams(window.location.search);
    const payload = {
      source: 'thingino-gphotos',
      code: params.get('code') || null,
      state: params.get('state') || null,
      scope: params.get('scope') || null,
      error: params.get('error') || null,
      error_description: params.get('error_description') || null
    };

    const statusEl = $('#status');
    const notifyStatus = msg => {
      if (statusEl) statusEl.textContent = msg;
    };

    const origin = window.location.origin;
    if (window.opener && typeof window.opener.postMessage === 'function') {
      try {
        window.opener.postMessage(payload, origin);
        notifyStatus('Authorization code sent back to Thingino.');
        setTimeout(() => window.close(), 1200);
        return;
      } catch (err) {
        notifyStatus('Unable to notify the camera. Please copy the URL manually.');
      }
    } else {
      notifyStatus('No parent window detected. Return to Thingino and paste the "code" parameter manually.');
    }
  })();
