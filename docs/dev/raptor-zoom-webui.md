# Raptor preview: zoom buttons (web UI)

## Summary

Adds `1x 2x 3x 4x 8x` buttons to the Raptor live preview page. Each button
calls `GET /x/zoom.cgi?f=<factor_mille>` and then reloads the page so the
WebRTC preview reconnects at the new resolution.

Pairs with the raptor PR `rvd, raptorctl: add digital zoom (set-zoom/get-zoom)`;
the endpoint drives `raptorctl rvd set-zoom` / the streamer restart.

## Why a CGI plus page reload

The preview on Raptor builds is the WebRTC page (`#raptor-webrtc-video`), not
the MJPEG template, so the buttons are injected above the video by `zoom.js`
and the page is reloaded after a change. A reload is deliberate: a zoom change
alters the stream resolution, so the WebRTC session must be renegotiated.

## Endpoint direction logic (why it is not just `set-zoom`)

On T31 the scalers are downscale-only, so the stream resolution tracks zoom and
the two directions behave differently in `rvd`:

- **Zoom in** (shrink buffers): `rvd` applies it in place. The endpoint calls
  `raptorctl rvd set-zoom <f>` and answers `{"mode":"inplace"}`.
- **Zoom out** (grow buffers): `rvd` cannot grow them in place without freezing
  the encoder, so it records the request only. The endpoint writes the target to
  `/run/raptor-zoom` and restarts the streamer out-of-process
  (`/etc/init.d/S31raptor restart`, with `PATH` set because the init script does
  not set it), answering `{"mode":"restart"}`. On start, `rvd` boots at full
  resolution and then shrinks to the persisted target.

The endpoint decides direction from `/run/raptor-zoom`, which `rvd` keeps equal
to the **applied** factor, so the choice stays correct across clicks and boots.

The restart is done by the CGI, not by `rvd`: forking the init script from
inside `rvd` leaves the daemons stopped.

## Capability and state

The page first calls `GET /x/zoom.cgi?info=1`, which reports the applied factor
and whether the running raptor provides `get-zoom`. The buttons are only
rendered when zoom is supported, the current level is marked active, and a
click on the current level is a no-op. Requests are serialised (buttons are
disabled until the response arrives), and a failed request shows an error
instead of reloading.

## Files

- `files/www/x/zoom.cgi` — auth'd endpoint, direction logic above.
- `files/www/a/zoom.js` — buttons above the video wrapper (`#raptor-webrtc-video`
  is inside a fixed-aspect, overflow-hidden box, so the bar goes before the
  wrapper); reload after an in-place change (~1.8 s) or a restart (~12 s).
- `files/www/preview.html` — loads `/a/zoom.js`.
- `thingino-raptor.mk` — installs the two files.
- `files/raptor.webui.json` — registers `/x/zoom.cgi`.

## Notes

- Zoom is not persisted across reboot (`/run` is tmpfs), so a device boots at 1x.
- Zoom-out costs a brief reconnect; zoom-in is immediate.
