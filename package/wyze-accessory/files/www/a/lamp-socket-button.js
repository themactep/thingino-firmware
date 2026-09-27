/**
 * Wyze Lamp Socket control bar button.
 *
 * Adds a Lamp toggle (with a settings dropdown) to the control bar built by
 * control-bar.js when lamp_socket.enabled is true. The button is disabled
 * while no socket is detected.
 */
(function () {
  "use strict";

  const API = "/x/json-lamp-socket.cgi";
  let button = null;

  function apiFetch(body) {
    const opts = { headers: { Accept: "application/json" } };
    if (body) {
      opts.method = "POST";
      opts.headers["Content-Type"] = "application/json";
      opts.body = JSON.stringify(body);
    }
    return fetch(API, opts)
      .then(function (r) {
        return r.json();
      })
      .then(function (data) {
        if (data.error) throw new Error(data.error.message);
        return data;
      });
  }

  function render(data) {
    if (!button) return;
    button.classList.remove("pending");
    button.classList.toggle("active", data.state === "on");
    button.disabled = data.present === false;
    button.title =
      data.present === false
        ? "Lamp Socket not detected"
        : "Lamp Socket: " + (data.state || "unknown");
  }

  function sync() {
    const bar = document.getElementById("button-bar");
    if (!bar) return;
    apiFetch()
      .then(function (data) {
        if (data.enabled !== true) {
          if (button) button.parentNode.remove();
          button = null;
          return;
        }
        if (!button) bar.appendChild(buildGroup());
        render(data);
      })
      .catch(function () {
        /* Silently ignore */
      });
  }

  function toggle() {
    if (!button || button.disabled) return;
    button.classList.add("pending");
    const action = button.classList.contains("active") ? "off" : "on";
    apiFetch({ action: action })
      .then(function (data) {
        render({ present: true, state: data.state });
      })
      .catch(function (err) {
        button.classList.remove("pending");
        if (typeof showAlert === "function") {
          showAlert("danger", "Lamp Socket: " + err.message);
        }
      });
  }

  function buildGroup() {
    const group = document.createElement("div");
    group.className = "btn-group flex-fill";
    group.setAttribute("role", "group");

    button = document.createElement("button");
    button.type = "button";
    button.id = "lamp-socket";
    button.className = "btn btn-secondary";
    button.title = "Lamp Socket";
    button.innerHTML =
      '<i class="bi bi-lamp"></i><span class="btn-label ms-1">Lamp</span>';
    button.addEventListener("click", toggle);

    const dropdown = document.createElement("button");
    dropdown.type = "button";
    dropdown.className = "btn btn-secondary dropdown-toggle dropdown-toggle-split";
    dropdown.title = "Lamp options";
    dropdown.setAttribute("data-bs-toggle", "dropdown");
    dropdown.setAttribute("aria-expanded", "false");
    dropdown.innerHTML = '<span class="visually-hidden">Toggle lamp menu</span>';

    const menu = document.createElement("ul");
    menu.className = "dropdown-menu";
    menu.innerHTML =
      '<li><a class="dropdown-item" href="/config-lamp-socket.html">' +
      '<i class="bi bi-gear"></i><span class="ms-1">Lamp settings</span></a></li>';

    group.appendChild(button);
    group.appendChild(dropdown);
    group.appendChild(menu);
    return group;
  }

  // control-bar.js builds #button-bar in its own DOMContentLoaded handler,
  // which runs after this head script's handler; defer one tick past it.
  function init() {
    setTimeout(sync, 0);
  }

  if (document.readyState === "loading") {
    document.addEventListener("DOMContentLoaded", init, { once: true });
  } else {
    init();
  }

  document.addEventListener("visibilitychange", function () {
    if (!document.hidden) sync();
  });

  window.thinginoLampSocket = { sync: sync };
})();
