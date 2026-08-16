# Prudynt WebUI Migration — Murky Items TODO

Direction: `thingino-webui` is a platform; prudynt-specific pages/CGIs/services
belong in `package/prudynt-t` behind the `prudynt.webui.json` plugin manifest
(the 79c1aad99 refactor started this; the "obvious" batch — RTSP access page,
Video Recorder page/service, orphan `json-motion.cgi` — was completed in
commit `<fill in>`).

The items below are prudynt-adjacent but entangled with shared features. Each
needs a decision before moving, so they're tracked here for future sessions.

## 1. `json-config-send2.cgi` — mixed ownership

- **File**: `package/thingino-webui/files/www/x/json-config-send2.cgi`
- **Problem**: the CGI serves two configs. The send2 half reads/writes
  `/etc/send2.json` (shared — `thingino-send2` owns that file and installs the
  send2 tools on every streamer). The motion half (`apply_motion_payload`)
  writes `{"motion": ...}` into **prudynt.json** via `ensure_prudynt_file()`.
  On raptor builds that motion write goes to a config file the streamer
  ignores — dead weight, arguably misleading.
- **Investigate**: does any send2 page actually expose the motion-trigger
  section? If yes, on raptor the UI should route through the agent
  (`/api/v1/config` motion), not prudynt.json. If the motion section is
  unreachable, delete the prudynt half and keep the CGI send2-only.
- **Acceptance**: send2 config page works identically on prudynt and raptor;
  no code path writes prudynt.json from a shared webui CGI.

## 2. `preview.js` `loadConfigFps()` — prudynt.json read in core

- **File**: `package/thingino-webui/files/www/a/preview.js`
- **Problem**: `loadConfigFps()` does `fetch("/etc/prudynt.json")` to override
  the stream0/stream1 FPS controls after night-mode halving. It's already a
  no-op on raptor (`if (preferStreamerAgent()) return;`), but the prudynt.json
  fetch is a prudynt-specific data source in the shared preview page.
- **Options**: (a) move the prudynt.json read into the prudynt plugin preview
  script (`preview-osd.js` or a small new one) and have it set the FPS inputs;
  (b) have the prudynt plugin expose an override hook (`window.thinginoStreamer`)
  that core calls when present.
- **Acceptance**: FPS override still works on prudynt; core preview.js has no
  `/etc/prudynt.json` reference.

## 3. `preview.js` export filename — cosmetic

- **File**: `package/thingino-webui/files/www/a/preview.js` (~line 1234)
- **Problem**: the config export button downloads
  `prudynt-config-<date>.json`. The export itself is a generic
  `action: { dump_config: null }` against the streamer API; only the filename
  is prudynt-flavored.
- **Options**: rename to something neutral (`streamer-config-<date>.json`), or
  let the plugin provide the filename via `window.thinginoStreamer` helper.
- **Acceptance**: filename matches the active streamer (or is neutral).

## 4. `json-imp.cgi` — prudyntctl fallback

- **File**: `package/thingino-webui/files/www/x/json-imp.cgi`
- **Problem**: day/night control is shared (daynightd), but the CGI falls back
  to `prudyntctl json -` for the image `running_mode` on prudynt builds
  ("prudynt images"). Raptor/timps route through their own channels.
- **Options**: keep (the fallback is harmless and the agent-ization of imaging
  is a separate effort), or move the prudyntctl branch into a prudynt-owned
  json-imp.cgi overlay like timps does.
- **Acceptance**: imaging page works on all three streamers; no prudyntctl
  invocation on non-prudynt builds.

## 5. `heartbeat-lib.sh` / `S99heartbeat` — prudynt probing

- **Files**: `package/thingino-webui/files/heartbeat-lib.sh`, `S99heartbeat`
- **Problem**: `heartbeat-lib.sh` probes prudynt (prudyntctl mic/spk/image,
  `/run/prudynt/privacy.active`) with raptor fallbacks. `S99heartbeat` is
  **not installed** (commented out in the .mk) — verify it's still wanted at
  all before touching the lib.
- **Options**: if heartbeat stays, route all probing through the agent
  (`thingino-agent` exposes the same data on every streamer) and delete the
  prudynt branches; if heartbeat is dead, remove both files.
- **Acceptance**: no prudynt-specific paths in shared heartbeat code.

## 6. `info.cgi` prudynt tab — leave as-is (recorded for completeness)

- **File**: `package/thingino-webui/files/www/x/info.cgi`
- **Status**: the file viewer lists `prudynt` and `raptor` tabs symmetrically.
  It's a generic viewer; the "File: prudynt.json" nav item is already owned by
  the prudynt plugin manifest. No action planned unless the tab list grows
  into a plugin mechanism.

## Already handled (do not reopen)

- **RTSP/ONVIF access page** — moved to `package/prudynt-t` (config-rtsp.html/js,
  json-config-rtsp.cgi), nav via plugin manifest; core `navigation.js` hide
  removed; timps' vestigial RTSP nav entry dropped (its page wrote prudynt.json
  and was broken there anyway).
- **Video Recorder** — moved to `package/prudynt-t` (tool-record.html/js/cgi,
  recordmgr, S95recordmgr gated on `BR2_THINGINO_DEV_IPCAM`); nav via plugin
  manifest; core `navigation.js` hide removed; `control-bar.js` recorder menu
  gated on non-raptor (raptor records natively via rmr).
- **`json-motion.cgi`** — deleted (orphan, zero callers anywhere).
