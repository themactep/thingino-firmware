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

## a/timps-auth-gate.js

### File header: why a second, earlier session check

Core `main.js` already checks `/x/session-status.cgi` and redirects an
unauthenticated visitor to `/login.html`, but it does that from
`window.addEventListener("load", ...)` plus a 100 ms timeout - i.e. after
every subresource has settled. The stock pages pull Bootstrap CSS/JS from
jsdelivr and Montserrat from Google Fonts, so on a camera VLAN with no
internet route `load` only fires once those requests hit their TCP timeout.
Until then the visitor sits looking at a fully rendered `preview.html` -
nav bar, empty video box, every control widget. Nothing leaks (the session
cookie is `HttpOnly`, and `session-status.cgi`, `timps-token.cgi`, the
snapshot CGIs and the stream all 401 on their own), but it looks like the
camera let them in.

This file closes that window without forking `main.js`:
- It is a plugin-manifest "scripts" entry, so `assemble_plugins.py` injects
  it as a plain `<script src>` before `</head>` - no `defer`, no `async`
  (see `make_script_tag()`), so it is parser-blocking and runs before
  `<body>` is parsed. There is therefore no moment at which page content
  could paint before the gate is armed.
- Arming is `document.documentElement.style.visibility = "hidden"`, and
  revealing restores the previous inline value (normally `""`) rather than
  writing `visible`, so it never overrides page CSS and there is no second
  flash. `visibility` and not `display:none` so the themed page background
  still paints - a blank dark page, not a white one.
- The `HttpOnly` cookie is not readable from JS, so there is no way to know
  the answer without the round trip. `credentials: "same-origin"` is fetch's
  default for a same-origin URL and is spelled out here only to document
  that the cookie does ride along (HttpOnly blocks JS *reads*, not sending).

Fail-open, deliberately: a 1500 ms `setTimeout` reveals the page no matter
what, and an `AbortController` on the same deadline drops the request. A
network error, a 5xx, a non-JSON body or a missing `authenticated` key all
reveal too. The gate never becomes the reason a camera looks bricked - a
genuinely unauthenticated session still gets caught by `main.js`'s slower
check on exactly today's timeline. 1500 ms is ~50x the measured LAN
round trip (25-34 ms), so the timeout is a backstop, not a budget.

Only a definitive answer redirects: HTTP 401/403, or `authenticated:false`.
The target matches `main.js`'s `redirectToLogin()` (a bare `/login.html`;
core keeps no return-to parameter, so neither does this). It uses
`location.replace()` rather than assigning `location.href`, because this
fires before paint: an `href` assignment would push a history entry for a
page the user never saw, and Back from `/login.html` would land on it and
be thrown forward again.

Skipped pages (`SKIP`) are exactly the ones core does not gate: `/login.html`
and `/401.html` (`redirectToLogin()` bails on both, to avoid a loop),
`/wait.html` (the reboot splash - the CGI is down by design there, and a
reboot must not end at the login form), `/gphotos-auth-callback.html` (an
OAuth landing page that has to relay its code, and redirecting would lose
it), and `/` + `/index.html` (an empty `<meta http-equiv="refresh">` stub
with nothing to hide, whose refresh would race the gate). `wait.html`,
`gphotos-auth-callback.html` and `login.html` do not load `main.js` at all;
the injection is per-page-unconditional, hence the explicit list.

## Redirect stubs

Only the three the core WebUI links to stay: `tool-record.html` and
`config-privacy.html` (control-bar.js buttons) and `tool-sensor-data.html`
(control bar, and core ships its own page of that name, which would come
back without ours). The other merged pages' old names were dropped.

## Video pages: streamer-video.html + streamer-overlays.html

Two pages replace the four per-stream pages (streamer-main/-substream/
-osd0/-osd1.html, removed: nothing links to them any more). Each page
shows both streams behind tabs; `a/timps-ui.js` holds what they share.

### a/timps-ui.js

- **Tabs**: `[data-stream-tab]` buttons. The stream comes from `?s=0|1`,
  else the last choice (localStorage "timps-stream"), else 0; a switch
  rewrites `?s=` and `#preview`'s `data-stream`, and `timps-preview.js`
  re-reads that attribute on every stream (re)start.
- **Restart bar**: `markPending(keys)` collects keys that wait for a
  restart (from the POST reply's `deferred_keys`, or client-side knowledge
  such as an OSD item without a boot-time region) into one fixed bar with
  "Restart streamer" (`/x/restart-prudynt.cgi`), then polls `/control`
  until the daemon is back and calls the page's reload hook.
- **Badges**: `badge(live)` renders the live/restart tag used on field
  labels.

### a/streamer-encoder.js (streamer-video.html)

- One form (`v-*` ids) refilled per tab from `GET /control` `video[i]`.
- Live vs restart per field from `caps.video_live`, plus `rtsp_path`
  (always live, graded live by the daemon since timps v1.9.20).
- Rate-control fields that do nothing for the SoC/mode/codec are hidden
  and named under the card, instead of shown disabled.
- Live chips (kbit/s, fps, subscribers, clients) from the `stats` SSE, the
  same feed as the preview page's stats card.
- "Compare streams" renders both streams side by side from the last GET.

### a/streamer-osd.js (streamer-overlays.html)

- One compact row per in-use slot; clicking a row opens its editor.
- **Position**: timps x/y are px, >0 from left/top, <0 from right/bottom,
  0 = exactly centred (so no offset on a centred axis, and 1 px is the
  smallest edge distance). The editor shows this as a 3x3 anchor plus two
  offsets and prints the resulting `osdS.N.x/y`.
- **Preview**: dashed boxes over the live image mark each overlay; their
  size is an estimate (canvas text metrics of an expanded template, logo
  100x30). Selected box: drag, or arrow keys 1 px / Shift 10 px (POSTed
  debounced). A move on a locked (centred) axis shows a hint instead.
- **Both streams**: a page-level switch (localStorage "timps-osd-link")
  writes every change to osd0 and osd1, scaling font_size/outline/y by the
  height ratio and x by the width ratio.
- **Restart**: `osd.enabled` and enabling a slot that had no region at
  startup go to the restart bar; rows show Live / Needs restart / Off.
- **Caps**: leaves missing from `caps.osd` are shown disabled.
- **Colours**: `<input type=color>` + opacity range form "0xAARRGGBB";
  "transparency" is the separate group alpha.
- **Remote changes**: a config event reloads the page state, but not while
  an input has focus; the reload runs when focus leaves it.

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

### Statistics card: data sources (SSE + polled `/control?stats=1` + slow full GET)

Fed by timps's `/events?stream=stats` SSE - same token + EventSource
pattern as `/a/preview-motion.js`. Independent of the video player's own
connect/disconnect lifecycle: it keeps ticking even while disconnected, so
it also shows other clients' activity on this channel.

The SSE "stats" frame (`src/mp4/httpd.c` `stats_json`, ~every 2s by default)
carries the fast-moving per-frame numbers: fps/kbps/subs/drop per enabled
stream, plus uptime_s/clients. It does NOT carry the config-level encoder
fields (gop/profile/rc_mode) or the encoder-backlog block, so a slow 5s poll
(the same cadence as the control-bar heartbeat elsewhere in this webui)
fills in the rest via `timpsApi.statsExtra()`.

That poll hits **`GET /control?stats=1`**, not plain `GET /control`: the
scoped sub-endpoint (same own-small-buffer pattern as `?fields=1` /
`?dn_history=1`, see `src/mp4/httpd.c`) returns only those fields - a few
hundred bytes against the full snapshot's ~8 KB, every 5s for as long as the
card is open.

The Day/Night and Motion summary blocks are **pushed**, not polled: the card
opens a second subscription via `timpsApi.events("daynight,motion", ...)`.
timps emits the full state of both once on connect and again on every change
(`src/mp4/httpd.c`, `events_stream()`), so a card opened mid-session renders
current values immediately - no priming fetch, and no reason for them to
live in the polled payload at all.

A third, slow loop fetches the full `GET /control` every 15s for what no
push or `?stats=1` carries: the per-stream fps/bitrate targets (bars, dashed
target line), the recorder state, `queue_drops`/`last_errors` (health tile)
and `version`. ~8 KB per 15s; moving these into `?stats=1` would let it go.

All loops only run while the Statistics card is visible (toggled by
`#ms-stats-toggle`).

### `applyStatsExtra()`: the `ave_bitrate` / queue-backlog fallback

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
`daynight_day_confirm_s`, `daynight_probe_confirm_s`,
`daynight_probe_min_gap_s`, `daynight_heartbeat_s`/`_max_s`,
`daynight_interval_ms`, `daynight_boot_probe`,
`daynight_diagnose_thresholds`, `daynight_mode` (auto/schedule),
`daynight_time_night_start`/`day_start`, `daynight_sun_latitude`/
`longitude`, `daynight_sun_sunrise`/`sunset_offset_min`. Read-only:
`daynight_night_baseline`/`daynight_day_trigger` (the adaptive trigger in
effect), `daynight_sun_computed_sunrise`/`_sunset`, and the
`probe_jump_pct`/`ref_delay_s`/`boot_settle_s` values that became fixed
constants in the 2026-08-22 consolidation.

The old "Time Schedule" column that also lived on
`/x/json-config-daynight.cgi` was dead, orphaned config that nothing read -
it has been replaced by the timps-native Decision source column.

### `daynight_calendar` is a UI-only selector, derived from the values

timps stores ONE calendar and picks it from the values themselves - a
complete `time_night_start`+`time_day_start` window outranks `sun_latitude`/
`longitude`, and 0/0 is "no location". There is no config key saying which was
meant, so `calFromValues()` mirrors `dn_cal_kind()` in `daynight.c` to drive
the selector, and `collectTimps()` always CLEARS the unselected calendar's
values on save. Without that clear, a leftover time window keeps outranking a
location the user just typed in and the save still reports success.

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

The "Privacy masks" tab of streamer-overlays.html (config-privacy.html is a
redirect to `#privacy`). The stream comes from the page's stream tabs (the
"timps-stream" event from `a/timps-ui.js`), the masks are drawn over the
live `#preview` instead of a polled snapshot, and "both streams" is the
page-wide `#osd-link` switch. Turning that switch on no longer mirrors all
existing masks at once; like the overlays, only later edits are mirrored.
Masks are listed like the overlays (only slots in use; a row opens the
editor). Selected mask: arrows move 1 px, Shift 10 px, Ctrl/Cmd+arrows
resize; Alt is avoided because Alt+Left is the browser's "back".

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
never re-enabled `#pm-add` (then also a stream select) and never restored the original
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

## a/streamer-image.js (streamer-image.html)

Cards with sliders; every image key is live. Keys missing from `caps.image`
are hidden and named under the preview. Red/blue gain are shown only in
Manual or Custom white balance. Double-click resets a slider to its middle.

## Record and timelapse pages

`recordings.html` has two tabs: Clips (`a/recordings.js`) and Settings
(`a/tool-record.js`; its reload button is `#rec-cfg-reload`, because
`#rec-reload` belongs to the clip list). `timelapse-player.html` has Player
(`a/timelapse-player.js`) and Settings (`a/tool-timelapse.js`). The tabs come
from `timps-ui.js` `initPageTabs()`, and `#settings` deep-links, which is
what the tool-record.html redirect uses (the core control bar's "Recording
settings" link points there).

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
- **Save**: LIVE keys (volume/gain/alc_gain, speaker volume/gain) go
  straight to `timpsApi.set({audio:{...}})`, debounced so slider drags
  coalesce into one POST; timps applies them live AND persists immediately.
  PERSIST+RESTART keys (codec/samplerate/bitrate, high_pass/agc/ns and the
  AGC levels, backchannel) are saved the same way but only take effect after
  a streamer restart. The "Restart streamer" hint (the menu entry calls
  /x/restart-prudynt.cgi) follows the POST reply's `deferred_keys`, which
  timps >= v1.9.20 fills for these keys; an older daemon without the field
  gets the hint on every such save, as before.
- **Offline**: if timps is unreachable the controls stay disabled and a
  small notice appears; nothing throws.

## a/timps-version.js

### File header: why this badge exists

Added after a 2026-08 incident where a stale cached build kept getting
reflashed undetected (see the "2026-08 stale-build incident" note in
`timps.mk`'s `TIMPS_BUILD_VERSION` section). Showing the running daemon's
compiled-in `MS_VERSION` at a glance from the WebUI catches that class of
drift without a manual /control fetch.

### File uploads: sensor IQ and OSD font (`x/timps-upload.cgi`)

The old IQ page and the overlay font dialog posted to `/x/preview.cgi`,
which only prudynt-t ships, so neither upload worked on timps builds. Both
now use `x/timps-upload.cgi?kind=iq|font` through `timpsUi.uploadCard()`:
GET = file/size/md5, `custom` (copy in the overlay) and `stock` (one in
`/rom`); POST the raw file to install it; POST `&reset` deletes the overlay
copy. `iq` writes `/etc/sensor/<sensor>-<soc>.bin` (8 KB..2 MB, starts with
the Ingenic version string like `2.10`); `font` writes
`/usr/share/fonts/default.ttf` (TTF/OTF magic), the default `osd.font_path`.
The font GET also lists every TTF/OTF there; the Overlays select box sets
`osd.font_path` from it (restart key, so it lands in `deferred_keys`), and an
upload switches the selection to `default.ttf` since that is what it replaced.
`/etc/sensor` is a symlink to `/usr/share/sensor`, so the overlay copy lives
under `/overlay/usr/share/sensor/`. Both are read at streamer start, so the
cards raise the restart bar.

### Photosensing controls (`x/timps-dn-controls.cgi`)

timps runs `/usr/sbin/daynight day|night` on a switch, and that board script
reads `daynight.controls.{color,ircut,ir850,ir940,white}` from
`thingino.json`. The CGI that edits them (`json-config-daynight.cgi`) ships
with thingino-daynightd, which timps builds do not have, so the page uses
`x/timps-dn-controls.cgi` (GET with the script's defaults, POST only that
exact shape).

Menu: every page has exactly one entry. Removed duplicates: "File:
timps.conf" (= Streamer config), "Streamer log" (= core "Log: logcat"),
"Video Recorder" (= Recordings, Settings tab), "Privacy masks" (tab of
"Overlays & privacy masks"), "Sensor IQ File" (card on Image Quality).

### OSD frames and the preview after a restart

The overlay frames mirror `msttf_render()`/`resolve_pos()`: the page loads the
TTF timps rendered with (`osd.font_path`, via `timps-upload.cgi?kind=font&raw=`),
measures advances without kerning at `font_size` px, adds the same pad
(`font_size/4 + 1 + outline`), rounds the width up to even, places the region
like timps (clamped to the frame) and draws the frame around the text, i.e.
the region minus the pad. `{hostname}` uses the footer host, not the IP.

A streamer restart ends the MJPEG connection and changes the per-boot token.
`timps-api.js` fires `timps-back` when an event stream reconnects after an
outage (the restart bar fires it too); the preview then re-fetches the token
and reconnects, and the overlay page reloads its state. Failed preview loads
retry with 2..30 s backoff instead of giving up after one attempt.

### Day / Night page (`config-photosensing.html`)

Photosensing and the Sensor Data Collector are one page: a "Now" box (mode,
gain on a day | hysteresis | night bar, what comes next) above two tabs,
`#settings` (default; the photosensing form: `config-photosensing.js`, field
ids unchanged) and `#live` (preview, value tiles, history chart:
`tool-sensor-data.js`, collecting even while its tab is hidden). The Now box rides the page's config SSE (`config,daynight`).
`tool-sensor-data.html` redirects to `#live`. The chart shades night samples
instead of drawing a mode line, and the window buttons show time spans
(points × sample period: 2 s live, 10 s when the camera records).
