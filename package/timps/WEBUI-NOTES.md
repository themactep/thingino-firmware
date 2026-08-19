# timps WebUI notes

Background, rationale and history for `www/a/*.js` and `www/*.html` that used
to live in long comment blocks inside those files. Moved out because those
files ship to cameras with 64 MB RAM and under a megabyte of writable
overlay, and JS ships to flash with its comments intact - every byte of prose
there is a byte of overlay spent on nothing the camera runs. This file does
NOT ship (see `package/timps/timps.mk`'s `TIMPS_INSTALL_WEBUI` install
loops: they glob `files/www/x/*`, `files/www/a/*` and `files/www/*.html`
only - a top-level `files/www/NOTES.md` matches none of those patterns).

Organised by file, then by function/section.

## a/timps-preview.js

### File header: why "timps-preview.js" and not "preview.js"

It used to be installed over thingino-webui's own `a/preview.js`, which is a
DIFFERENT script (core's `preview.js` belongs to core's `preview.html` and
drives an MJPEG `<img>` through the prudynt bridge CGIs). Two unrelated
scripts sharing one path is what forced timps to re-install its www overlay
from a global finalize hook to beat Buildroot's per-package-directory merge.
Only timps's own pages load this file, so it simply gets its own name and
the collision is gone.

### Direct-to-timps media URLs and the `?token=` query param

/x/timps-token.cgi hands the authenticated WebUI session the per-boot timps
token as `{"token":"...","port":8880}`. The token unlocks media viewing +
/control + /events on that port (never RTSP) and travels as `?token=`
because an `<img>` cannot send headers - it can show up in access logs,
which is accepted on the LAN. The token is per-boot, so it is fetched once
and cached; when the stream errors (e.g. 401 after a camera reboot minted a
new token) it is re-fetched once and the `<img>` retried, and if the token
endpoint itself is unavailable the preview falls back to the nostream
placeholder. Without a token the URLs still work on open timps configs
(empty `http.user`) and from localhost.

### `startPreview()` / the stream watchdog `timeout` constant

Deliberately long (120s), not tuned down: a `multipart/x-mixed-replace`
`<img>` only ever fires ONE "load" event, for the very first part - the
browser does not re-fire it for subsequent MJPEG frames, so `lastLoadTime`
never advances once the stream is up. A short timeout here would therefore
force a reconnect of an otherwise perfectly healthy, continuously streaming
preview every `timeout` ms forever (confirmed: server-side `stream_mjpeg()`
has no time/byte cap, connections were closing client-side every ~15s while
still transferring MBs of live JPEG data). This only exists to recover a
stream that goes truly silent without the browser ever firing "error" (e.g.
the camera's JPEG source hangs, or a network stall drops packets without a
socket-level error) - genuinely rare, so it can be long.

### `handleMessage()`: why `msg.restart_required` is checked at all

Set by the json-prudynt.cgi bridge (same hint `audio.js` shows) - prudynt
itself restarts its own threads and never sets the flag, so this only ever
fires for the bridge-backed pages, not the fully-native ones.

## a/timps-api.js

### `request()`: the full POST /control status-code contract

POST /control grades its answer (timps `src/control.h`, `src/mp4/httpd.c`).
Error bodies carry a machine-readable "reason"; 200 bodies are unchanged
byte-for-byte (that is the path a dragged slider posts on).

    400 not_json        the body was not a JSON object - a bug in the
                         calling page, keep it loud
    422 unknown_fields  it parsed, but no field in it is known to THIS
                         build - the key NAMES are wrong for this binary
    409 values_rejected the names were right, every value was refused
    503 oom              the daemon could not allocate - not our fault

Key off "reason", not off counter arithmetic. 422 and 409 are the opposite
advice and a client that confuses them loops forever: retrying a 422
unchanged can never succeed (this binary will never know that key), while a
409 is worth re-sending with valid values. That is exactly why the daemon
split them - see timps commit "control: say what this build can do, and
stop overloading 422".

Every one of these carries the same `{ok,accepted,changed,rejected}` body as
a 200, so parse BEFORE deciding and hang the counters off the error - a bare
"HTTP 422" would send the user hunting for a network problem that does not
exist. A 200 with `changed:0` stays a plain success on purpose: the field
already held the posted value (`accepted` counts that write), and clamped
writes are 200 too - clamping is the documented contract, not an error.

Fallback for daemons older than the reason-code split, which answer 422 to
BOTH failures and carry no "reason" at all: there the counters are the only
signal there has ever been, and `rejected>0` does discriminate correctly -
so use it, but ONLY when the daemon did not tell us. On a current build this
branch never runs.

## a/timps-control-bar.js

### File header: why a plugin script instead of a main.js fork, and why the override is safe

Timps used to ship a whole copy of `a/main.js` (545 lines different from
core) just to re-point six control-bar actions at timps. That copy had to be
force-installed over thingino-webui's own file twice per build (see the
ordering note that used to live in `timps.mk`), and it had silently
drifted: it had lost core's `apiFetch()`/`API_KEY_PROMISE` helpers entirely
and carried other packages' code (the wyze-accessory doorbell banner, now
shipped by that package as `/a/doorbell-banner.js`).

How the override works, and why it is safe:
- `assemble_plugins.py` injects the manifest's "scripts" as `<script>` tags
  before `</head>`, so this file runs BEFORE `/a/main.js` (which every page
  loads from `<body>`, see thingino-webui's `*.html`).
- `main.js` is a classic script: its top-level `function name() {}`
  declarations become writable properties of the global object, and every
  call site inside `main.js` resolves them through the global scope at call
  time. Reassigning `window.<name>` after `main.js` has evaluated therefore
  redirects `main.js`'s own call sites too.
- "after main.js has evaluated" is what the `DOMContentLoaded` hook at the
  bottom of this file buys us: `DOMContentLoaded` fires once parsing is
  done, i.e. after the `<body>` script tag ran. Listener order is
  registration order, and this file registered first (it is in `<head>`),
  so the overrides are in place before any of `main.js`'s own
  `DOMContentLoaded` work.
- `main.js` wires the control-bar buttons from `window.addEventListener
  ("load", initAll)`, which is later still, so `initAll`'s click handlers
  already call the timps implementations.

## a/streamer-osd.js

### File header: full data-flow spec (Phase 1, data-driven OSD items)

Talks directly to the timps streamer over `window.timpsApi` (GET/POST
/control on timps's own port, per-boot token) - no json-prudynt.cgi bridge
for these pages (the OSD wiring in `a/timps-preview.js` is gated off here;
that script keeps only the live preview `<img>`, which already loads
straight from timps).

Each video stream carries its own independent set of up to `MS_MAX_OSD`
(=8) generic overlay items; every item is a text-or-logo slot with the same
field set. Instead of four hard-coded named boxes (time/usertext/uptime/
logo) this page renders one "card" per in-use item index and lets the user
add/remove items (0..8), edit every field, and drive both streams' item N
at once.

- **Stream**: detected from the page's body id (`page-streamer-osd0` ->
  section "osd0", `page-streamer-osd1` -> "osd1"). Index IS the identity -
  old configs (0=time, 1=user text, 2=uptime, 3=logo) load unchanged by
  index, distinguished text-vs-logo by each item's "type".
- **Load**: `timpsApi.get()` returns BOTH streams' item sets in one shot; we
  populate this stream's cards and remember the other stream's items (for
  the "apply to both" scope + its restart bookkeeping).
- **Save**: per-item changed leaves apply LIVE via
  `timpsApi.set({osdS:{N:{leaf:val}}})` and persist immediately. A card
  scoped to "both streams" POSTs the same leaves to osd0.N AND osd1.N.
- **Restart**: the global `osd.enabled` master switch is persist+restart,
  and enabling an item that was OFF when the streamer started cannot be
  applied live (its IMP region only exists when enabled at startup). Both
  surface the "Restart streamer" hint; each card shows a per-item Live /
  Needs-restart / Off status pill.
- **Caps**: `caps.osd` lists the item leaf keys this build/SoC applies live
  (text, x, y, font_size, color, transparency, outline, outline_color).
  Each per-leaf control greys out when its key is absent. enabled, x/y
  position and the structural controls are NOT caps-gated (enabled is
  structural, never advertised in caps.osd).
- **Type**: switching an item text<->logo (and logo upload) is Phase 2 - it
  needs a persist-only "type"/"logo_path" leaf the streamer does not accept
  over /control yet, so the type selector is disabled with a tooltip and
  simply reflects the item's current type.
- **Colors**: `<input type=color>` (#rrggbb) + its "-alpha" range make up
  the timps "0xAARRGGBB" color and back. This is separate from
  "transparency" (a 0..255 group alpha over the whole item).
- **Offline**: if timps is unreachable the page shows a notice and no
  cards; it never throws.

### `applyCorrections()`: why the OTHER stream's echo is never rendered here

DELIBERATE (a decision, not a gap): a "both" scope POST also carries echoes
for the OTHER stream ("osd\<OTHER\>.\*"). This page renders cards for ONE
stream only, so no visible widget shows the other stream's value - there is
nothing that could go stale, and writing such an echo into THIS stream's
cards would be wrong: the two streams legitimately hold different values
(that is what the scopes are for). The toast still reports those
corrections.

### `sendBody()`: what `r.rejected > 0` on an otherwise-200 response means

The daemon applied some leaves and refused others, and a silent success
would lie about the refused ones. NOT about cleared text any more - timps
`7893a1a` ("control: let an empty string clear a text field") makes `""` a
valid value for STRING fields, meaning "clear this", so a cleared
`.osd-text` is now accepted and stored empty. What still gets refused here
is null/`"undefined"` anywhere, and `""` on the NON-string leaves of a card
(font_size, transparency, x/y) - where `pint("")` would silently zero the
setting rather than clear it (timps `src/control.c`, `apply_one`).

## preview.html

### File header: install mechanism and the unspelled plugin marker

This page is installed straight over thingino-webui's own `/preview.html`
(same filename, timps's own package - see `TIMPS_INSTALL_WEBUI_CGIS` in
`timps.mk`), before thingino-webui's plugin-assembly finalize hook runs. So
it still goes through the normal plugin pipeline: the plugin preview-body
marker is replaced with the contributed overlays (thingino-motors' PTZ
joystick, ...) and their preview scripts are appended before the closing
body tag.

The marker is not spelled out literally in the HTML comment on purpose: the
assembler substitutes every occurrence of the marker string in the file, and
injected markup inside an HTML comment would terminate that comment early.

### `.jst` / `#motor` CSS: why the joystick reveal uses opacity, not visibility

Only the 9 joystick buttons (which together fill their 300px hover-reveal
circle, see `a/main.css` `#motor`/`.jst`) should take the pointer -
everything else must fall through to the native `<video controls>` bar and
click-to-play surface underneath. `main.css` reveals the joystick via
`visibility:hidden -> visible` on `#motor:hover`, but `visibility:hidden`
elements are never hit-tested (even with `pointer-events:auto`), so making
`#motor` itself click-through would stop it from ever detecting the hover
that reveals it. Swapping the hide/reveal to `opacity` keeps the buttons
hit-testable while still starting invisible, so hovering the circle still
reveals them exactly as before - only the container layers around/behind
them become click-through.

### Statistics card: why two data sources (SSE + polled /control)

Fed by timps's `/events?stream=stats` SSE - same token + EventSource
pattern as `/a/preview-motion.js`. Independent of the video player's own
connect/disconnect lifecycle: it keeps ticking even while disconnected, so
it also shows other clients' activity on this channel.

The SSE "stats" frame (`src/mp4/httpd.c` `stats_json`, ~every 2s by default)
carries the fast-moving per-frame numbers: fps/kbps/subs/drop per enabled
stream, plus uptime_s/clients. It does NOT carry the config-level encoder
fields (gop/profile/rc_mode) or the ave_bitrate/day-night/motion status
blocks - those only exist in GET /control, so a slow poll of /control (5s,
the same cadence as the control-bar heartbeat elsewhere in this webui) fills
in the rest via timps-api.js (loaded on demand by main.js's
`timpsApiReady()`, already used by the control bar on every page). Both
loops only run while the Statistics card is visible (toggled by
`#ms-stats-toggle`).

### `applyControlSnapshot()`: the `ave_bitrate` / queue-backlog fallback

`ave_bitrate` (`IMP_Encoder_GetChnAveBitrate`) only exists on T31; every
other platform - and a T31 stream before its first frame - reports -1 and
`control.c` omits the field entirely. `IMP_Encoder_Query`'s queue-backlog
counters (`left_pics`/`left_stream_bytes`/`left_stream_frames`) ARE
available on all 9 platforms, so they're used as an always-present
encoder-health stand-in instead of leaving the cell as a permanent "-"
placeholder.

### `pickMime()`: why advertising AAC wrongly blacks out the whole player

Only advertise an mp4a (AAC) audio track when timps actually muxes AAC into
the fMP4. With PCM (G.711) audio the stream is video-only (`httpd.c`
`can_audio = acodec==AAC`), so a SourceBuffer typed with mp4a would reject
the 1-track init segment (MSE requires the init tracks to match the codecs
string) and tear down the whole MediaSource -> black player, no video at
all. When `wantAac` is false the code therefore probes video-only strings
instead.

## a/config-photosensing.js

### File header: field mapping and the removed "Time Schedule" column

Full field map (all follow "daynight_\<key\>" -> "daynight.\<key\>", see
`fillTimps()`/`collectTimps()`): `daynight_enabled`,
`daynight_total_gain_night_threshold`, `daynight_total_gain_day_threshold`,
`daynight_day_gain_pct`, `daynight_baseline_delay_s`,
`daynight_night_reconfirm_s`, `daynight_boot_settle_s`/`_max_s`,
`daynight_boot_stable_pct`, `daynight_mode` (sensor/time/sun),
`daynight_time_night_start`/`day_start`, `daynight_sun_latitude`/
`longitude`, `daynight_sun_sunrise`/`sunset_offset_min`. Read-only:
`daynight_night_baseline`/`daynight_day_trigger` from the status fields of
the same names (the adaptive trigger in effect).

The old "Time Schedule" column that also lived on
`/x/json-config-daynight.cgi` was dead, orphaned config that nothing read -
it has been replaced by the timps-native Override Mode selector.

## a/preview-motion.js

### File header: SSE protocol, token, and the polling fallback

The page fetches the per-boot timps token once from `/x/timps-token.cgi`
(authenticated WebUI session required) and then SUBSCRIBES to the timps
push stream: `EventSource http://<host>:<port>/events?stream=motion&token=<tok>`.
timps pushes an "event: motion" frame whenever the grid state changes (same
JSON object as GET /control's "motion":
`{available,enabled,cols,rows,active:[0/1,...],...}`; `active` is row-major,
`index = row*cols+col`). EventSource cannot send custom headers, so the
token goes as `?token=` - it may show up in access logs, which is accepted
on the LAN (the token unlocks /control + /events + viewing the HTTP media
endpoints, never RTSP). CORS + the OPTIONS preflight are handled by timps.
`preview.html` primes `window.timpsTokenInfo` with a single shared token
fetch (its /stream.mp4 fetch reuses the token); this script uses that when
present and keeps its own fetch as a standalone fallback.

FALLBACK: if EventSource is unavailable or keeps failing while /control
still answers (e.g. an old timpsd without /events, or `events.enabled=0`),
the overlay falls back to the previous behavior - polling GET /control at
~4 Hz with the X-Timps-Token header - so nothing regresses. EventSource
reconnects by itself (the server sends "retry: 3000"); the stream is closed
while the tab is hidden and reopened when it becomes visible.

## a/privacy.js

### `send()`: why mirrored OTHER-stream echoes are never folded back

DELIBERATE (a decision, not a gap): the "apply to both" branch scales the
mask to the other stream's resolution and clamps it against those bounds ON
PURPOSE, so a corrected value there is the expected outcome of mirroring,
not a mistake to undo - and this page has no widget showing the other
stream's mask anyway. Folding such an echo into `regions[]` would corrupt
THIS stream's coordinates with the other stream's scale. The stream guard
in `send()`'s response handler is what enforces this; the toast still
reports every correction.

### `markAvailable()`: the bug it fixes

The old success path only did `classList.add("d-none")` on the warning: it
never re-enabled `#pm-add` / `#pm-stream` and never restored the original
message markup. So ONE transient failure disabled the editor PERMANENTLY.
That failure is real, not theoretical: a streamer restart tears the OSD
groups down while /control keeps serving, and `caps.privacy.available` is
derived from `imp_osd_group_active()` - it genuinely reports 0 for that
window (see the B3 comment in timps `src/hal/imp_osd.c`). A page loaded
then latched "unavailable"; the automatic re-`load()` driven by the
/events config resync afterwards silently re-hid the warning but left the
controls dead, leaving a page that looks fine yet cannot add or switch
masks until the user reloads by hand. `#pm-reload` had the same problem -
it was not disabled, so it re-ran `load()`, appeared to work, and still
left a dead editor.

## a/config-audio.js

### File header: full load/save/offline spec

- **Load**: `timpsApi.get()` -> populate every control from the "audio"
  object. LIVE controls are enabled only when their timps key is listed in
  `caps.audio` (the SoC capability matrix); the persist+restart keys
  (codec/samplerate/bitrate) are deliberately NOT in `caps.audio`, so they
  enable when the audio object carries them. Speaker volume/gain are live
  too (`caps.audio` carries `spk_volume`/`spk_gain` when an AO pipeline is
  compiled in); speaker sampling and stereo capture stay greyed out. A
  test-sound control (dropdown + Play/Stop) is shown when
  `caps.play.available` is set, driving the play queue via /control.
- **Save**: LIVE keys (volume/gain/alc_gain/high_pass/agc/agc_target_dbfs/
  agc_compression_db/ns) go straight to `timpsApi.set({audio:{...}})`,
  debounced so slider drags coalesce into one POST; timps applies them live
  AND persists immediately. PERSIST+RESTART keys (codec/samplerate/bitrate)
  are saved the same way but only take effect after a streamer restart, so
  those changes show the existing "Restart streamer" hint (the menu entry
  calls /x/restart-prudynt.cgi).
- **Offline**: if timps is unreachable the controls stay disabled and a
  small notice appears; nothing throws.

## a/timps-version.js

### File header: why this badge exists

Added after a 2026-08 incident where a stale cached build kept getting
reflashed undetected (see the "2026-08 stale-build incident" note in
`timps.mk`'s `TIMPS_BUILD_VERSION` section). Showing the running daemon's
compiled-in `MS_VERSION` at a glance from the WebUI catches that class of
drift without a manual /control fetch.
