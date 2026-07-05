# OSD as H.264 SEI Metadata

Thingino embeds on-screen display (OSD) elements as SEI NAL units in the
H.264 / H.265 stream instead of burning them into video frames via the IPU
hardware.  A client (web UI, RTSP player) reads the metadata and renders the
overlay.

## Quick start

```json
"stream0": {
    "osd": {
        "mode": "metadata",
        "enabled": true,
        "time_enabled": true,
        "usertext_enabled": true,
        "uptime_enabled": true,
        "brightness_enabled": true
    }
}
```

- `"mode": "overlay"` – classic IPU‑blended OSD (default, unchanged).
- `"mode": "metadata"` – OSD embedded as SEI; no IPU resources used.

The camera must be restarted after changing `mode`.

## Stream rotation

**The encoder always runs landscape (rotation = 0).**  Software rotation on the
SoC is expensive (~55 % CPU on T31 at 2048×1536).  Instead, set
`stream0.rotation` to the desired display angle (0, 90, 180, 270) – the value
is carried in the SEI metadata and the web‑UI preview rotates client‑side via
CSS.

```json
"stream0": {
    "rotation": 90
}
```

The SEI payload includes a `rotation` field so any client can apply the
correct transform:

```json
{"v":1, "sw":2048, "sh":1536, "rotation":90, "elements":[…]}
```

### Rotating in RTSP players

The stream itself is landscape.  Players must rotate on the client side:

**mpv**
```
# ~/.config/mpv/input.conf
r cycle_values video-rotate 90 180 270 0
Alt+RIGHT add video-rotate 90
Alt+LEFT  add video-rotate -90
```

**VLC** — Tools → Effects and Filters → Video Effects → Geometry → Rotate.

**ffplay**
```
ffplay -vf "transpose=clock" rtsp://camera/ch0
```

## SEI payload format

Version 1 JSON, injected before every IDR frame (NAL type 6 / 39).

```json
{
  "v": 1,
  "sw": 2048,
  "sh": 1536,
  "rotation": 90,
  "elements": [
    {
      "t":      "time",
      "text":   "2026-07-05 12:34:56",
      "x":      10,
      "y":      10,
      "w":      310,
      "h":      58,
      "fs":     32,
      "color":  "#FFFFFFCC",
      "stroke": "#000000CC"
    }
  ]
}
```

| Field | Meaning |
|-------|---------|
| `v` | Schema version (1) |
| `sw`, `sh` | Encoder stream width / height (pre‑rotation canvas) |
| `rotation` | Display rotation in degrees (0 / 90 / 180 / 270) |
| `elements[].t` | Element type: `time`, `usertext`, `uptime`, `brightness` |
| `x`, `y` | Position in encoder‑pixel coordinates. Positive = from left/top; negative = from right/bottom; zero = centred. |
| `w`, `h` | Bounding‑box size in encoder pixels (includes stroke) |
| `fs` | Configured OSD font size |
| `color` | Fill colour `#RRGGBBAA` |
| `stroke` | Stroke colour `#RRGGBBAA` |

**Thingino UUID:** `a1b2c3d4-e5f6-4780-abcd-ef1234567890` (user‑data‑unregistered
payload type 5).

## HTTP API

The current OSD state is available as JSON on the camera’s HTTP server
(port 8080, same as the MJPEG stream).  No authentication required.

```
GET /api/v1/osd-sei
```

A CGI proxy at `/x/json-osd-sei.cgi` forwards the request through uhttpd
(port 80) so the web UI can fetch it from the same origin.

## Web UI

The preview page renders OSD elements as positioned `<div>` overlays on top
of the MJPEG image.  Styling is entirely in CSS (`main.css`); the JavaScript
only manages positioning and text updates.

### CSS architecture

```css
#sei-osd-overlay {
  position: absolute; left: 0; top: 0;
  overflow: hidden; pointer-events: none; z-index: 10;
}
.sei-osd-el {
  position: absolute;
  font-family: monospace; font-size: 1rem; line-height: 1.2;
  pointer-events: none; white-space: nowrap;
  color: var(--c);
  text-shadow:
    -1px -1px 0 var(--s), 1px -1px 0 var(--s),
    -1px  1px 0 var(--s),  1px  1px 0 var(--s);
}
.sei-osd-el[data-sei-type="time"]       { --c: var(--sei-c-time);       --s: var(--sei-s-time); }
.sei-osd-el[data-sei-type="usertext"]   { --c: var(--sei-c-usertext);   --s: var(--sei-s-usertext); }
.sei-osd-el[data-sei-type="uptime"]     { --c: var(--sei-c-uptime);     --s: var(--sei-s-uptime); }
.sei-osd-el[data-sei-type="brightness"] { --c: var(--sei-c-brightness); --s: var(--sei-s-brightness); }
```

Colours are set **once** on the overlay container as CSS custom properties
(`--sei-c-*`, `--sei-s-*`) from the first SEI response.  Element-type
selectors map them to local `--c` / `--s` variables.  No inline styles.

### Positioning

Elements that use negative coordinates (`x < 0` or `y < 0`) are anchored
with CSS `right` / `bottom` so they follow the overlay’s edge when
dimensions change (e.g. during rotation).  Centred elements (`x == 0` or
`y == 0`) use `left: 50%` / `top: 50%` with `translate(-50%, -50%)`.
Positive coordinates map directly to `left` / `top`.

Positions are scaled from encoder pixels to rendered pixels using
`clientWidth / streamWidth` and `clientHeight / streamHeight`.

### Efficient updates

On each poll the JS hashes the element structure (types + positions +
sizes).  When the structure is unchanged — which is almost always — only
the **text content** of elements that actually changed is updated via
`textContent`.  No DOM reconstruction, no style recalculation.

### Rotation

The `<img>` element is rotated with `transform: rotate(…)`.  The overlay
swaps its `width` / `height` and offsets itself to align with the rotated
image’s visual centre.  The full‑screen preview modal (`#preview_fullsize`)
inherits the same rotation transform.

## Implementation notes

| File | Role |
|------|------|
| `Config.hpp` / `Config.cpp` | `_osd.mode` field, config wiring |
| `SEIWriter.hpp` / `SEIWriter.cpp` | H.264/H.265 SEI NAL unit builder |
| `OSD.hpp` / `OSD.cpp` | Text generation, `getSEIJson()`, metadata‑mode skip of IPU |
| `IMPEncoder.cpp` | FS→ENC direct binding when `mode=metadata` |
| `IMPFramesource.cpp` | `IMP_FrameSource_SetChnRotate` **disabled** (rotation is client‑side) |
| `VideoWorker.cpp` | SEI injection before first IDR slice of each GOP |
| `HTTPMJPEG.cpp` | `/api/v1/osd-sei` endpoint (before auth check) |
| `preview.html` | Client‑side overlay rendering with CSS rotation |
