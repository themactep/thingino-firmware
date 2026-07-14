# timps (thingino package)

**timps** — Tiny IMP Streamer (https://github.com/Lu-Fi/timps).
Minimal-dependency streamer for Ingenic SoCs, replacing prudynt-t:
RTSP (H.264/H.265, AAC/G.711) + fragmented-MP4 browser preview (MSE) +
JPEG/MJPEG (incl. piggyback encoders on the video channels), OSD with its
own TrueType rasterizer, motion detection (IMP_IVS), on-demand encoding.
Pure C, links only against vendor libimp/libalog/libsysutils + pthread.

## Layout

```
package/timps/
├── Config.in                 BR2_PACKAGE_TIMPS (+ _CONTROL, _DAYNIGHT)
├── timps.mk                  buildroot package (SITE_METHOD=git)
└── files/
    ├── timps.conf.example    -> /etc/timps.conf.example
    ├── S95timps              -> /etc/init.d/S95timps
    ├── color                 -> /usr/sbin/color (day/night hook, _DAYNIGHT)
    └── www/x/*.cgi           -> /var/www/x/ (WebUI bridge, finalize hook)
```

## Source download (git + header submodule)

The package fetches timps via git (`TIMPS_SITE_METHOD = git`)
with `TIMPS_GIT_SUBMODULES = YES`, which also pulls the Ingenic IMP
headers from the `gtxaspec/ingenic-headers` submodule at `include/` — the
exact prudynt-t pattern. The source Makefile's `IMP_INC` default
(`./include/<SoC>/<ver>/<lang>`) therefore works without overrides.

`TIMPS_SITE` points at <https://github.com/Lu-Fi/timps>
(`TIMPS_SITE_BRANCH = main`). **After the first push** pin
`TIMPS_VERSION` in `timps.mk` to a commit hash (currently `main` = branch
tip). thingino convention: `_SITE_BRANCH` = branch, `_VERSION` = exact
commit — only a pinned commit is reproducible.

## Enabling

timps is one of the exclusive **streamer choices**:

* `make menuconfig` → Thingino Firmware → Streamer Packages → **Streamer**
  → `timps (minimal RTSP/MP4/MJPEG)`
  (`BR2_PACKAGE_THINGINO_STREAMER_TIMPS=y`, selects
  `BR2_PACKAGE_TIMPS`).
* Because the choice is exclusive, prudynt-t / raptor / strero can never be
  enabled at the same time — the old "conflicts with prudynt-t" caveat is
  gone (timps also no longer installs any `prudyntctl`).
* `BR2_PACKAGE_FAAC=y` — optional; automatically builds with `USE_FAAC=1`
  (software AAC for browser MP4 + RTSP audio; without it audio falls back
  to G.711/pcmu).
* `BR2_PACKAGE_TIMPS_CONTROL=y` — optional `/control` endpoint
  (`USE_CONTROL=1`) for live web-UI-style imaging changes. Not needed for
  the preview.
* `BR2_PACKAGE_TIMPS_DAYNIGHT=y` — native automatic day/night switching
  (`USE_DAYNIGHT=1`, selects `_CONTROL` and `thingino-daynight`). See
  "Automatic day/night" below.

Build as usual; incremental rebuild: `make br-timps-rebuild`.

## What gets installed

* `/usr/bin/timpsd` (stripped)
* `/etc/timps.conf.example` — seeded to `/etc/timps.conf` on first
  start; adjust `sensor.*` if needed.
* `/etc/init.d/S95timps` — start/stop/restart init script.
* `/var/www/x/*.cgi` — WebUI bridge CGIs (only with WebUI + `_CONTROL`,
  see "WebUI integration" below).

The preview page talks to timps directly (see below).

## Endpoints / thingino compatibility

* RTSP on **port 554**, paths **`/ch0`** (main) and **`/ch1`** (sub) — same
  as prudynt, so `rtsp://user:pass@<ip>:554/ch0` NVR URLs keep working
  (set in the shipped conf example; timps's built-in default is 8554).
* HTTP server on **port 8880**: `/` player page, `/?embed=1&chn=N` bare
  player, `/stream.mp4?chn=N` (fMP4), `/snapshot.jpg?chn=N`,
  `/stream.mjpeg?chn=N`. Requests from 127.0.0.0/8 bypass timps's
  HTTP Basic auth. On `BR2_PACKAGE_TIMPS_CONTROL` builds the three media
  endpoints also accept the timps token as `?token=` (viewing only, never
  RTSP) — that is how the WebUI previews load them directly (a query token
  can land in access logs; accepted on the LAN).
* `GET /events` (SSE, `BR2_PACKAGE_TIMPS_CONTROL` builds): pushes `motion`
  (grid cells), `daynight` (mode/brightness/gain) and periodic `stats`
  events as JSON — same access rules as `/control`; the browser passes the
  per-boot token as `?token=` (EventSource cannot send headers; may land in
  logs, accepted on the LAN). The preview motion overlay subscribes to
  `?stream=motion` instead of polling; config keys `events.enabled` /
  `events.stats_ms` / `events.max_clients` (see the conf example).

## Web UI preview (raptor pattern)

When the timps streamer is chosen, `package/thingino-webui` installs
`files/www/preview-timps.html` as `/var/www/preview.html`
(`THINGINO_WEBUI_PREVIEW_HTML` switch in `thingino-webui.mk`, exactly like
`preview-raptor.html` for raptor — no finalize-hook override anymore).

That page is a **native MSE/fMP4 player** (no iframe): it fetches
`http://<location.hostname>:8880/stream.mp4?chn=N` and drives a MediaSource
SourceBuffer with the same queue/eviction/live-edge logic as timps's
embedded player (`src/mp4/httpd.c`, `PLAYER_TAIL`); codec strings probed:
`avc1.640028` (+ `mp4a.40.2`), `hvc1.1.6.L123.B0`. The motor joystick and
`/a/preview-motors.js` are carried over unchanged from `preview-raptor.html`,
so PTZ via `/x/json-motor.cgi` keeps working.

The motion-grid overlay (`/a/preview-motion.js`) gets the per-boot token
from `/x/timps-token.cgi`, probes `GET /control` once (feature detection +
initial state) and then **subscribes** to
`http://<host>:8880/events?stream=motion&token=<tok>` — timps pushes grid
changes, no polling. If EventSource is unavailable or `/events` keeps
failing (old timpsd, `events.enabled = 0`), it falls back to the previous
4 Hz `GET /control` polling, so nothing regresses. The stream is closed
while the tab is hidden and reopened on return; EventSource reconnects on
its own after a streamer restart (server `retry: 3000`).

**Known limitation (mixed content):** if the web UI is served over HTTPS,
browsers block the plain-HTTP `:8880` video request and the preview stays
black. Serve the web UI over HTTP or reverse-proxy timps under the
same HTTPS origin.

**Note (HTTP auth):** the stream is fetched by the *browser*, not by the
camera. The page appends the per-boot timps token (`?token=`, shared with
the motion overlay's single `/x/timps-token.cgi` fetch) to the
`/stream.mp4` fetch, so the preview works even when `http.user`/`http.pass`
are set in timps.conf. Without a token (endpoint unavailable) the old
behavior remains: open `http://<ip>:8880/` once to cache Basic credentials,
or leave timps's HTTP auth empty — the 401 hint in the status line stays.

## No snapshot proxy CGIs

All previews are fully self-contained: the main preview page plays timps's
fMP4 stream directly from the camera's HTTP port, and the settings pages'
small live preview, the fullscreen modal and the endpoint list
(`/a/preview.js`) build
`http://<host>:8880/stream.mjpeg?chn=N&token=<tok>` /
`.../snapshot.jpg?chn=N&token=<tok>` URLs directly (token from
`/x/timps-token.cgi`, cached per page; re-fetched once when the stream
errors after a camera reboot, `nostream.svg` fallback when unavailable).
**No `/x/ch*.jpg|mjpg` proxy CGIs and no `prudyntctl` shim are installed**
— the finalize hook even purges the WebUI's own prudynt-flavored copies, so
a timps image carries no dead snapshot endpoints (keep `videoN.jpeg = true`
in timps.conf so `?chn=N` works). PTZ still uses thingino's own
`/x/json-motor.cgi` (the real motor control, not a timps shim). External
consumers should fetch `http://<ip>:8880/snapshot.jpg?chn=N` directly
(Basic auth, or `?token=`/`X-Timps-Token` with the persistent `http.token`).

## WebUI integration (bridge CGIs)

The stock WebUI settings pages talk prudynt JSON to a handful of shell CGIs.
When `BR2_PACKAGE_THINGINO_WEBUI=y` **and** `BR2_PACKAGE_TIMPS_CONTROL=y`,
`timps.mk` installs timps-flavored replacements from `files/www/x/` via a
`TARGET_FINALIZE_HOOK`, overriding the WebUI's own copies (same file names;
the pages themselves only carry small streamer-agnostic tweaks in
`package/thingino-webui`, e.g. the caps-based grey-out on the Image/Audio
pages and the restart hint on the Main-/Substream pages). All of them keep
the WebUI session auth
(`/var/www/x/auth.sh`) and talk to `http://127.0.0.1:8880/control`
(localhost bypasses timps's HTTP auth).

| CGI | What it does now |
|---|---|
| `json-prudynt.cgi` | Workhorse. Translates prudynt-shaped JSON to `/control`: all numeric `image.*` keys pass through, filtered by the per-SoC `caps.image` list of `GET /control` (unsupported keys are dropped from forward and echo, so the page keeps them greyed out); `image.{hflip,vflip}` `true/false` -> `1/0`; audio live keys `mic_vol`/`mic_gain`/`mic_alc_gain`/`mic_high_pass_filter`/`mic_agc_enabled`/`mic_agc_target_level_dbfs`/`mic_agc_compression_gain_db`/`mic_noise_suppression` -> `audio.{volume,gain,alc_gain,high_pass,agc,agc_target_dbfs,agc_compression_db,ns}` (applied to the running input, filtered by `caps.audio`); audio persist-only keys `mic_enabled`/`mic_format` (AAC/G711A/G711U)/`mic_sample_rate` (8/16 kHz)/`mic_bitrate`/`force_stereo`/`spk_enabled`/`spk_vol`/`spk_gain` -> `audio.{enabled,codec,samplerate,bitrate,force_stereo,spk_enabled,spk_volume,spk_gain}` (saved to `timps.conf`, applied on restart; the echo adds `"restart_required":true` so the Audio page shows a restart hint); `streamN.*` and `sensor.*` (ALL persist-only — encoder/stream/sensor settings are never reconfigured live; saved to `timps.conf`, applied on the next restart, echo adds `"restart_required":true`): `streamN.format` (H264/H265) -> `videoN.codec`, `streamN.fps/width/height/bitrate/gop/max_gop/profile/buffers/enabled` -> same-named `videoN.*` keys, a `"WIDTHxHEIGHT"` `resolution` string is split into width/height, `streamN.mode` (CBR/VBR/FIXQP/SMART/CAPPED_VBR/CAPPED_QUALITY) -> `videoN.rc_mode`, `streamN.rtsp_endpoint` (`ch0`) -> `videoN.rtsp_path` (`/ch0`), `sensor.{model,i2c_addr,fps,width,height}` -> `sensor.*`; `streamN.osd.*` (the prudynt per-stream OSD tree) -> timps's PER-STREAM overlay set `osdN.M.*`, applied LIVE (stream0's page edits timps `osd0.*`, stream1's page `osd1.*`; item 0 = time, 1 = user text, 2 = uptime, 3 = logo): `enabled`, `position "x,y"` -> `x/y`, `fill_color "#rrggbb[aa]"` -> `color 0xAARRGGBB`, `stroke_color` -> `outline_color` (text outline drawn under the fill), osd-level `stroke_size` -> `outline` (px) and `font_size` -> `font_size` of all text items, `time.format`/`usertext.format` -> item texts (`%hostname` <-> `{hostname}`), osd-level `enabled` -> the GLOBAL `osd.enabled` master switch (restart); the echo returns each stream's own set so each OSD page populates its stream; `action.save_config` -> no-op "ok" (timps persists live); `action.dump_config` -> `GET /control` passthrough; `mp4.start/stop` -> explicit error (no record API); `motion/privacy.enabled` -> echoed only (not wired); `streamN.audio_enabled` dropped (timps audio is global, the toggle stays greyed out). |
| `json-imp.cgi` | Live day/night bar: `auto` -> `{"daynight":{"enabled":true}}` (native auto detection on); `color` -> disables auto + `image.running_mode`; `daynight` -> disables auto + `force_mode`; `ir850/ir940/white/ircut` keep calling the GPIO helpers `light`/`ircut`. |
| `json-prudynt-save.cgi` | No-op success — timps already persisted every applied change to `/etc/timps.conf`. |
| `json-prudynt-config.cgi` | Config export: streams `GET /control` (timps shape) as a JSON download. |
| `restart-prudynt.cgi` / `restart-timps.cgi` | `/etc/init.d/S95timps restart` (same ok-JSON as the original; the prudynt name is kept because the WebUI calls it). |
| `json-heartbeat.cgi` / `json-heartbeat-slow.cgi` | timps-aware control-bar heartbeat (SSE / single shot; payload built by `timps-heartbeat.sh` from `GET /control` + the GPIO tools). Carries the day/night telemetry the control bar reads: `daynight_brightness` (%), `total_gain` (ISP [24.8] linear, 256 = 1x — feeds the `.dnd-gain` display), `daynight_mode` (`day`/`night`), `daynight_enabled`; `null` while unknown, like the stock heartbeat. |
| `json-timegraph-stream.cgi` | Photosensing data-collector SSE (`tool-sensor-data.html`): polls `GET /control` every second (bounded, default 1 h — the page's EventSource reconnects) and emits `data: {"time_now","total_gain","daynight_brightness","daynight_mode"}` events, plus the `total_gain_*_threshold` chart lines when the photosensing page saved them to `/etc/thingino.json`. The page's history request (`json-prudynt.cgi`, `{"daynight":{"history":null}}`) is answered with the single current sample — timps keeps no sample ring, the graph grows from the live stream. |

Not bridged (see the CGI headers for details): recording (`mp4`), motion
toggle, mic/spk mute, `spk_sample_rate`, the G726/OPUS/PCM audio codecs,
per-stream `audio_enabled`, and the remaining `prudyntctl events` consumers
(`events.cgi`, `json-send2.cgi` live-apply). The page metrics `ev` and
`ae_luma` are prudynt-only and stay absent from the timegraph stream.

### Direct-to-timps token (`timps-token.cgi`)

timps generates a random **per-boot token** and writes it to
`/run/timps.token` (0640). `timps-token.cgi` (WebUI session auth via
`auth.sh`) serves it as `{"token":"...","port":8880}` (port/token-file path
read from `/etc/timps.conf`). With it a WebUI page can skip the localhost
bridge CGIs and call timps **directly from the browser**: fetch the token
once, then `fetch('http://<host>:8880/control', {method:'POST', headers:
{'X-Timps-Token': token}, body: json})` — timps answers the CORS preflight
and reflects the page's `Origin`. The token unlocks `/control`, `/events`
and **viewing** the HTTP media endpoints (`/stream.mp4`, `/stream.mjpeg`,
`/snapshot.jpg` — that is what the settings-page previews and the MSE
preview use, as `?token=` since an `<img>`/`EventSource` cannot send
headers), but never RTSP. The remaining bridge CGIs stay as-is (they use
the localhost bypass and keep working). A cross-origin attacker cannot
obtain the token (the file is only readable on-device by the authenticated
WebUI backend), so serving it to the logged-in session does not widen the
attack surface.

## Automatic day/night

With `BR2_PACKAGE_TIMPS_DAYNIGHT=y` (default when timps is selected) timps does
the day/night **detection natively** — the separate `daynightd` daemon is not
needed and its init script `S97daynightd` plus the WebUI "Photosensing" nav
entry are removed at finalize (`TIMPS_DISABLE_DAYNIGHTD` hook). Detection is a
thread inside `timpsd`: it samples `/proc/jz/isp/isp-m0` (integration time +
gains), computes a scene brightness %, applies the same
threshold/hysteresis/dwell rules as `daynightd` and on a change runs
thingino's `/sbin/daynight day|night` (package `thingino-daynight`, selected),
which drives the IR-cut filter, IR LEDs and the `color` hook per
/etc/thingino.json. The package installs a timps flavor of `color` to
`/usr/sbin/color` (same CLI as raptor's) that sets `image.running_mode`
through `/control` — timps never sets the ISP mode directly, so manual
`daynight`/`color` calls and the auto thread stay consistent.

Config keys in `/etc/timps.conf` (defaults = daynightd's):
`daynight.enabled` (1), `daynight.threshold_low` (25), `daynight.threshold_high`
(75), `daynight.hysteresis` (0.1), `daynight.interval_ms` (500),
`daynight.transition_s` (5), `daynight.switch_cmd` (`daynight`),
`daynight.isp_path` (`/proc/jz/isp/isp-m0`).

The WebUI imaging bar works as before: **Auto** re-enables detection
(`{"daynight":{"enabled":true}}` via `/control`), the manual day/night/color
buttons disable it and force a mode (see `json-imp.cgi` above); `GET /control`
reports the live status `"daynight":{"enabled":N,"mode":N,"brightness":N,
"total_gain":N}` — brightness in %, total_gain in the IMP [24.8] linear scale
(256 = 1x, derived from the isp-m0 analog/digital/ISP-digital gain fields, log2
units with 32 = 2x — the same value prudynt/raptor report), −1 while unknown.
The thread keeps measuring in manual mode, so the WebUI gain display and the
Photosensing data collector stay live with auto detection off.

## Sizes / build flags

The .mk builds with `-Os -ffunction-sections -fdata-sections` and links with
`--gc-sections`; the binary is stripped on install. `USE_FAAC=0` and
`USE_CONTROL=0` keep it smallest. For small-RAM SoCs (T10/T20, 64 MB) buffer
bounds can be shrunk via `TIMPS_CFLAGS += -DMS_AU_BUF_MAX=...` etc.
(see the comment at the top of the source Makefile).
