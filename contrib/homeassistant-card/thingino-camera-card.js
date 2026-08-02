/**
 * Thingino Camera Card — Custom Lovelace card for Thingino IP cameras.
 *
 * Shows a live camera feed with quick-access control buttons and sensor
 * readouts — everything the Thingino Home Assistant integration exposes.
 *
 * Controls supported:  Color Mode, Day/Night Mode, IR Cut Filter,
 * IR LED 850nm, Motion Guard, Privacy Screen, Snapshot, White Light.
 *
 * Sensors supported:   Live View status, Motion, WiFi Signal.
 *
 * ## Installation
 *
 * 1. Copy into Home Assistant's `www/` directory:
 *
 *      cp thingino-camera-card.js /config/www/
 *
 * 2. Register as a Lovelace resource (Settings → Dashboards → ⋮ → Resources):
 *
 *      URL:  /local/thingino-camera-card.js
 *      Type: JavaScript Module
 *
 * 3. Add the card to a dashboard view.
 *
 * ## YAML Config
 *
 * ```yaml
 * type: custom:thingino-camera-card
 * camera_entity: camera.generic_stream     # any HA camera entity
 * title: Front Porch
 * controls:
 *   - entity: switch.thingino_a1b2c3_color
 *     name: Color
 *   - entity: select.thingino_a1b2c3_daynight
 *     name: Day/Night
 *   - entity: switch.thingino_a1b2c3_ircut
 *     name: IR Cut
 *   - entity: switch.thingino_a1b2c3_ir850
 *     name: IR LED
 *   - entity: switch.thingino_a1b2c3_motion_guard
 *     name: Guard
 *   - entity: switch.thingino_a1b2c3_privacy
 *     name: Privacy
 *   - entity: button.thingino_a1b2c3_snapshot
 *     name: Snap
 *   - entity: switch.thingino_a1b2c3_white
 *     name: Light
 * sensors:
 *   - entity: camera.thingino_a1b2c3_live_view
 *     name: Live View
 *   - entity: binary_sensor.thingino_a1b2c3_motion
 *     name: Motion
 *   - entity: sensor.thingino_a1b2c3_rssi
 *     name: WiFi
 * show_title: true
 * show_sensors: true
 * ```
 *
 * ## Camera entity suggestions
 *
 * - **go2rtc WebRTC** (low latency): Install the WebRTC Camera custom
 *   integration, then point it at `http://<camera-ip>:1984/api/stream?src=<name>`.
 * - **Generic camera** (MJPEG stills / periodic snapshots): Use the built-in
 *   `generic` camera platform pointing at
 *   `http://<camera-ip>/cgi-bin/snapshot.cgi`.
 * - **Thingino MQTT camera**: Use `camera.thingino_<id>_live_view` directly
 *   (base64 JPEG frames, slow — not recommended for live view).
 *
 * License: MIT
 */

import { LitElement, html, css, nothing } from "https://cdn.jsdelivr.net/npm/lit@3/+esm";

/* ====================================================================== */

const ICON_MAP = {
  color:        ["mdi:palette",                     "mdi:palette-outline"],
  ircut:        ["mdi:camera-iris",                 "mdi:camera-iris"],
  ir850:        ["mdi:led-on",                      "mdi:led-off"],
  ir940:        ["mdi:led-on",                      "mdi:led-off"],
  motion_guard: ["mdi:motion-sensor",               "mdi:motion-sensor-off"],
  privacy:      ["mdi:eye-off",                     "mdi:eye"],
  white_light:  ["mdi:lightbulb-on",                "mdi:lightbulb"],
  white:        ["mdi:lightbulb-on",                "mdi:lightbulb"],
  snapshot:     ["mdi:camera",                      "mdi:camera"],
  daynight:     ["mdi:theme-light-dark",            "mdi:theme-light-dark"],
};

/* ====================================================================== */

export class ThinginoCameraCard extends LitElement {

  /* ---- Lit reactive properties --------------------------------------- */

  static get properties() {
    return {
      hass:   { type: Object },
      config: { type: Object },
    };
  }

  /* ---- Card metadata (HA editor support) ----------------------------- */

  static getConfigElement() {
    return document.createElement("div");
  }

  static getStubConfig() {
    return {
      camera_entity: "camera.generic_stream",
      title: "",
      controls: [
        { entity: "switch.thingino_a1b2c3_color", name: "Color" },
        { entity: "switch.thingino_a1b2c3_ircut", name: "IR Cut" },
      ],
      sensors: [
        { entity: "sensor.thingino_a1b2c3_rssi", name: "WiFi" },
      ],
    };
  }

  /* ---- Config -------------------------------------------------------- */

  setConfig(config) {
    if (!config.camera_entity)
      throw new Error("thingino-camera-card: `camera_entity` is required");

    this.config = {
      camera_entity:   config.camera_entity,
      title:           config.title || "",
      controls:        config.controls || [],
      sensors:         config.sensors || [],
      show_title:      config.show_title !== false,
      show_sensors:    config.show_sensors !== false,
      compact:         !!config.compact,
    };
  }

  getCardSize() {
    return this.config?.compact ? 3 : 5;
  }

  /* ---- Entity helpers ------------------------------------------------ */

  _state(eid)          { return this.hass?.states?.[eid]; }
  _value(eid)          { const s = this._state(eid); return s ? s.state : null; }
  _attr(eid, key)      { const s = this._state(eid); return s?.attributes?.[key]; }

  _isOn(eid) {
    const v = this._value(eid);
    return v === "on" || v === "ON";
  }

  /* ---- Service calls ------------------------------------------------- */

  _call(domain, service, data) {
    this.hass.callService(domain, service, data);
  }

  _toggle(domain, eid) {
    const on = this._isOn(eid);
    this._call(domain, on ? "turn_off" : "turn_on", { entity_id: eid });
  }

  _press(eid) {
    this._call(eid.split(".")[0], "press", { entity_id: eid });
  }

  _toggleDaynight(eid) {
    const cur = this._value(eid);
    if (!cur) return;
    this._call("select", "select_option", {
      entity_id: eid,
      option: cur === "day" ? "night" : "day",
    });
  }

  /* ---- Dispatch actions per control type ----------------------------- */

  _handleControl(ctrl) {
    const eid    = ctrl.entity;
    const domain = eid.split(".")[0];

    if (domain === "switch" || domain === "input_boolean")
      this._toggle(domain, eid);
    else if (domain === "button")
      this._press(eid);
    else if (domain === "select")
      this._toggleDaynight(eid);
  }

  /* ---- Decide icon + active state per control ------------------------ */

  _ctrlMeta(ctrl) {
    const eid    = ctrl.entity;
    const domain = eid.split(".")[0];
    const val    = this._value(eid);

    if (!val) return { icon: "mdi:help-circle", active: false, label: "n/a" };

    // Detect entity "kind" from its id suffix
    let kind = "";
    const parts = eid.split("_");
    if (parts.length >= 3) kind = parts.slice(2).join("_");

    const pair = ICON_MAP[kind] || ICON_MAP[Object.keys(ICON_MAP).find(k => kind.includes(k)) || ""];
    const onIcon  = ctrl.icon || (pair ? pair[0] : "mdi:toggle-switch");
    const offIcon = ctrl.icon || (pair ? pair[1] : "mdi:toggle-switch-off-outline");

    if (domain === "button") {
      return { icon: ctrl.icon || "mdi:gesture-tap-button", active: false, label: ctrl.name || eid };
    }
    if (domain === "select") {
      return {
        icon: val === "night" ? "mdi:weather-night" : "mdi:weather-sunny",
        active: val === "night",
        label: val,
      };
    }

    const active = this._isOn(eid);
    return {
      icon:  active ? onIcon : offIcon,
      active,
      label: ctrl.name || eid,
    };
  }

  _sensorIcon(eid, val) {
    if (eid.includes("rssi") || eid.includes("wifi") || eid.includes("signal"))
      return "mdi:wifi";
    if (eid.includes("firmware_timestamp"))
      return "mdi:calendar-clock";
    if (eid.includes("firmware_version") || eid.includes("firmware"))
      return "mdi:package-up";
    if (eid.includes("doorbell"))
      return val === "ON" || val === "on" ? "mdi:doorbell" : "mdi:doorbell-outline";
    if (eid.includes("motion"))
      return val === "ON" || val === "on" ? "mdi:motion-sensor" : "mdi:motion-sensor-off";
    if (eid.includes("live_view") || eid.includes("camera"))
      return "mdi:camera";
    return "mdi:information";
  }

  /* ---- Camera poster URL --------------------------------------------- */

  _posterUrl() {
    const cam = this._state(this.config.camera_entity);
    if (!cam || cam.state === "unavailable") return null;
    return `/api/camera_proxy/${this.config.camera_entity}?t=${Date.now()}`;
  }

  _openMoreInfo() {
    const ev = new CustomEvent("hass-more-info", {
      bubbles: true, composed: true,
      detail: { entityId: this.config.camera_entity },
    });
    this.dispatchEvent(ev);
  }

  /* ---- Styles -------------------------------------------------------- */

  static get styles() {
    return css`
      :host {
        display: block;
        background: var(--ha-card-background, var(--card-background-color, #1c1c1c));
        border-radius: var(--ha-card-border-radius, 12px);
        overflow: hidden;
        color: var(--primary-text-color, #e1e1e1);
        box-shadow: var(--ha-card-box-shadow, 0 2px 2px rgba(0,0,0,.14));
      }

      /* --- Stream --- */
      .stream {
        position: relative;
        width: 100%;
        aspect-ratio: 16 / 9;
        background: #000;
        cursor: pointer;
        overflow: hidden;
      }
      .stream img {
        display: block;
        width: 100%;
        height: 100%;
        object-fit: contain;
      }
      .stream .overlay {
        position: absolute;
        inset: 0;
        display: flex;
        align-items: center;
        justify-content: center;
        background: rgba(0,0,0,0.4);
        opacity: 0;
        transition: opacity 0.2s;
      }
      .stream:hover .overlay,
      .stream.no-feed .overlay {
        opacity: 1;
      }
      .stream .overlay ha-icon {
        --mdc-icon-size: 48px;
        color: #fff;
      }

      /* --- Title --- */
      .title-bar {
        padding: 10px 14px 0;
        font-size: 0.95rem;
        font-weight: 600;
      }

      /* --- Controls --- */
      .controls {
        display: flex;
        flex-wrap: wrap;
        gap: 6px;
        padding: 10px 14px;
      }
      .ctrl {
        flex: 1 1 auto;
        min-width: 52px;
        display: flex;
        flex-direction: column;
        align-items: center;
        gap: 2px;
        padding: 8px 6px 6px;
        border-radius: 10px;
        border: none;
        background: var(--secondary-background-color, #2e2e2e);
        color: var(--secondary-text-color, #aaa);
        cursor: pointer;
        font: inherit;
        font-size: 0.7rem;
        line-height: 1.2;
        transition: background 0.2s, color 0.2s, box-shadow 0.2s;
      }
      .ctrl:hover {
        background: var(--primary-color, #4a90d9);
        color: #fff;
      }
      .ctrl.on {
        background: var(--primary-color, #4a90d9);
        color: #fff;
        box-shadow: 0 0 8px rgba(74,144,217,0.5);
      }
      .ctrl ha-icon {
        --mdc-icon-size: 22px;
        pointer-events: none;
      }
      .ctrl .lbl {
        white-space: nowrap;
        overflow: hidden;
        text-overflow: ellipsis;
        max-width: 64px;
      }

      /* --- Sensors --- */
      .sensors {
        display: flex;
        flex-wrap: wrap;
        gap: 14px;
        padding: 2px 14px 10px;
        font-size: 0.75rem;
        color: var(--secondary-text-color, #aaa);
      }
      .sensors .sens {
        display: flex;
        align-items: center;
        gap: 4px;
      }
      .sensors ha-icon {
        --mdc-icon-size: 16px;
      }
      .sensors .val {
        font-weight: 600;
        color: var(--primary-text-color, #e1e1e1);
      }
      .sensors .val.on {
        color: var(--primary-color, #4a90d9);
      }
    `;
  }

  /* ---- Render -------------------------------------------------------- */

  render() {
    if (!this.hass) return nothing;

    const poster = this._posterUrl();
    const hasFeed = !!poster;

    return html`
      <div class="stream ${hasFeed ? "" : "no-feed"}"
           @click=${this._openMoreInfo.bind(this)}>
        ${poster
          ? html`<img src=${poster} alt="camera feed" />`
          : html`<div style="display:flex;align-items:center;justify-content:center;height:100%;color:#555;">
                   <ha-icon icon="mdi:camera-off"></ha-icon>
                 </div>`
        }
        <div class="overlay">
          <ha-icon icon="mdi:play-circle-outline"></ha-icon>
        </div>
      </div>

      ${this.config.show_title && this.config.title
        ? html`<div class="title-bar">${this.config.title}</div>`
        : nothing}

      ${this.config.controls.length
        ? html`
            <div class="controls">
              ${this.config.controls.map(c => this._renderControl(c))}
            </div>`
        : nothing}

      ${this.config.show_sensors && this.config.sensors.length
        ? html`
            <div class="sensors">
              ${this.config.sensors.map(s => this._renderSensor(s))}
            </div>`
        : nothing}
    `;
  }

  _renderControl(ctrl) {
    const { icon, active, label } = this._ctrlMeta(ctrl);
    return html`
      <button class="ctrl ${active ? "on" : ""}"
              @click=${() => this._handleControl(ctrl)}
              title="${ctrl.name || ctrl.entity}: ${label}">
        <ha-icon icon=${icon}></ha-icon>
        <span class="lbl">${label}</span>
      </button>`;
  }

  _renderSensor(s) {
    const eid   = s.entity;
    const st    = this._state(eid);
    const val   = st ? st.state : "—";
    const uom   = st?.attributes?.unit_of_measurement || "";
    const icon  = s.icon || this._sensorIcon(eid, val);
    const on    = val === "ON" || val === "on";

    return html`
      <span class="sens" title="${s.name || eid}">
        <ha-icon icon=${icon}></ha-icon>
        ${s.name || eid}
        <span class="val${on ? " on" : ""}">${val}${uom ? "\u00A0" + uom : ""}</span>
      </span>`;
  }
}

/* ====================================================================== */

customElements.define("thingino-camera-card", ThinginoCameraCard);

console.log("%c[thingino-camera-card] %cloaded ✓",
  "color:#4a90d9;font-weight:bold", "color:inherit");
