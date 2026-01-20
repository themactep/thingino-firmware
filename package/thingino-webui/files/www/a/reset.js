(function() {  const gridEl = $('#actionsGrid');
  const statusEl = $('#actionsStatus');
  const refreshBtn = $('#refreshActions');

  function setStatus(message, variant = 'info', useOverlay = false) {
    if (!statusEl) return;
    statusEl.textContent = message;
    statusEl.className = `alert alert-${variant} status-overlay`;
    if (useOverlay) {
      statusEl.dataset.overlay = 'true';
      statusEl.dataset.overlayText = message || 'Working...';
    } else {
      delete statusEl.dataset.overlay;
      delete statusEl.dataset.overlayText;
    }
    statusEl.classList.remove('d-none');
  }

  function clearStatus() {
    if (!statusEl) return;
    statusEl.classList.add('d-none');
    delete statusEl.dataset.overlay;
    delete statusEl.dataset.overlayText;
  }

  function createActionCard(action) {
    const col = document.createElement('div');
    col.className = 'col';

    const wrapper = document.createElement('div');
    wrapper.className = 'alert alert-danger h-100 d-flex flex-column';

    const title = document.createElement('h4');
    title.className = 'alert-heading';
    title.textContent = action.title || 'Reset action';
    wrapper.appendChild(title);

    const description = document.createElement('p');
    description.className = 'flex-grow-1';
    description.innerHTML = action.description_html || '';
    wrapper.appendChild(description);

    const cta = buildCta(action.cta || {});
    if (cta) wrapper.appendChild(cta);

    col.appendChild(wrapper);
    return col;
  }

  function buildCta(cta) {
    const variant = cta.variant || 'secondary';
    if (cta.type === 'form') {
      const form = document.createElement('form');
      form.method = cta.method || 'POST';
      form.action = cta.action || '#';
      (cta.fields || []).forEach(field => {
        const input = document.createElement('input');
        input.type = 'hidden';
        input.name = field.name;
        input.value = field.value;
        form.appendChild(input);
      });
      const button = document.createElement('button');
      button.type = 'submit';
      button.className = `btn btn-${variant}`;
      button.textContent = cta.button || 'Continue';
      form.appendChild(button);
      return form;
    }

    if (cta.type === 'link') {
      const link = document.createElement('a');
      link.href = cta.href || '#';
      link.className = `btn btn-${variant}`;
      link.textContent = cta.text || 'Continue';
      return link;
    }

    return null;
  }

  async function loadActions(showSpinner = true) {
    showAlert('', '');
    if (showSpinner) {
      setStatus('Loading reset options...', 'info', true);
    }
    try {
      const response = await fetch('/x/reset.cgi', { headers: { 'Accept': 'application/json' } });
      if (!response.ok) {
        throw new Error(`Request failed with status ${response.status}`);
      }
      const payload = await response.json();
      const actions = Array.isArray(payload.actions) ? payload.actions : [];
      if (!actions.length) {
        setStatus('No reset actions available right now.', 'warning');
        gridEl.innerHTML = '';
        return;
      }
      clearStatus();
      gridEl.innerHTML = '';
      actions.forEach(action => gridEl.appendChild(createActionCard(action)));
    } catch (error) {
      setStatus('Unable to load reset options. Try again.', 'danger');
      showAlert('danger', error.message || 'Unknown error');
    }
  }

  refreshBtn?.addEventListener('click', () => loadActions(false));
  loadActions(true);
})();
