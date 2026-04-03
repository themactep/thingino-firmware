# Implementation Roadmap

Status: Proposed

Implementation progress: In progress

## Purpose

This file turns the architecture into a sequence of work that can be reviewed,
reassessed, and changed as implementation teaches us more.

## Phase 1: Streamer-agnostic camera agent with first adapter

Goal: make the canonical camera API independent from streamer ownership while
proving it with a first backend adapter.

Deliverables:

- camera agent service exists
- API is served by the agent, not by a streamer-specific daemon
- local prudynt adapter exists as the first backend glue layer
- API request tree is split into narrow metadata, capability, runtime, settings,
	and action resources
- `GET /config` is the only full-config endpoint
- API can expose capabilities, runtime state, and persisted config without
	returning full camera blobs from routine writes
- API supports a small set of actions: snapshot, clip, reboot, restart streamer
- SSE event stream exists

Current phase 1 status:

- implemented in tree
	- `package/thingino-agent` package exists
	- agent core and adapter split exists
	- prudynt adapter exists
	- managed local-only listener lifecycle exists through `thingino-agentd` and `S95thingino-agent`
	- compatibility routes exist
	- narrow `/capabilities/*`, `/runtime/*`, and `/settings/*` routes now cover image, motion tuning, daynight, privacy, services, firmware, most first-pass stream controls, richer system runtime, network, and streaming service runtime
	- `/health` exists
	- `/events` and `/config/schema` exist
	- narrow `PATCH` support now exists for stream `format` and `mode`
	- first narrow stream OSD settings now exist for `osd/enabled`, `osd/time/enabled`, `osd/usertext/enabled`, and `osd/usertext/format`
	- second narrow stream OSD settings now exist for `osd/time/format`, `osd/uptime/enabled`, and `osd/uptime/format`
	- third narrow stream OSD settings now exist for `osd/brightness/enabled` and `osd/brightness/format`
	- the remaining prudynt-backed OSD leaf settings now exist for top-level OSD controls plus the rest of the `brightness`, `time`, `uptime`, `usertext`, `logo`, and `privacy` trees on streams `0` and `1`
	- first storage settings now exist for `storage/autostart`, `storage/channel`, `storage/device-path`, `storage/duration`, `storage/filename`, and `storage/mount`, with runtime storage exposed at `runtime/storage`
	- first recorder runtime now exists at `runtime/recording`, reporting configured recorder defaults plus active clip state when prudynt exposes an active marker
	- richer stream runtime now exists at `runtime/streams/{id}`, reporting stream fields plus RTSP listener state and per-stream recording activity
	- first firmware lifecycle runtime now exists at `runtime/firmware`, reporting upgrade support, pending upgrade markers, and sysupgrade boot completion state
	- first narrow send2 settings now exist for motion output enables and per-service `send_photo` or `send_video` flags, with `capabilities/send2` exposed through the agent-owned route tree
	- snapshot, clip, privacy, daynight, reboot, and streamer service control paths exist
	- managed listener lifecycle was live-validated on the flashed image through `127.0.0.1:1998`
	- native local listener transport now exists for non-TLS mode, and the known local API tree is now daemon-owned end to end; a single packaged CGI dispatcher at `/var/www/x/api` remains only for the current TLS or `uhttpd` compatibility path
	- live validation proved representative native ownership first by removing selected runtime, settings, and action CGI files, and then by removing the remaining top-level route scripts plus `resource.cgi` while representative top-level, runtime, settings, schema, and SSE requests still passed through the daemon
	- rebuilt image validation confirmed the in-image listener path end to end in both modes: native non-TLS on `127.0.0.1:1998/x/api/v1/*` and TLS `uhttpd` compatibility through the packaged `/var/www/x/api` dispatcher, then restored the default disabled state afterward
	- remote HTTPS listener exposure now works through the current TLS `uhttpd` path when explicitly enabled, and live validation now confirms remote non-TLS binds are rejected, remote TLS binds without `agent.token` are rejected, and authenticated remote HTTPS requests succeed when `agent.tls=true`, `agent.listen=0.0.0.0`, and `agent.token` is configured
	- live validation now also confirms the native non-TLS listener does not depend on the packaged `/var/www/x/api` compatibility dispatcher: with that file temporarily removed on the flashed camera, representative `/x/api/v1/device`, `/x/api/v1/config/schema`, and `/x/api/v1/events` requests still passed through the daemon, then the file and default disabled state were restored
	- hot validation confirmed agent-owned typed SSE events and machine-readable schema output on the live camera, including motion edges, recording completion, firmware pending transitions, health warnings, and streamer restart lifecycle
	- rebuilt image validation confirmed the in-image `/events` and `/config/schema` paths end to end and restored the default disabled state afterward
	- hot validation confirmed representative stream `format` and `mode` writes through the managed listener and restored the original values afterward
	- hot validation confirmed representative OSD reads and writes through the managed listener and restored the original values afterward
	- hot validation confirmed representative second-slice OSD reads and writes through the managed listener and restored the original values afterward
	- hot validation confirmed representative third-slice OSD brightness reads and writes through the managed listener and restored the original values afterward
	- hot validation confirmed representative remaining OSD leaf reads and writes through the managed listener, including top-level OSD, nested text position, and logo transparency paths, then restored the original values afterward
	- hot validation confirmed representative storage reads and writes for `duration` and `mount`, plus runtime storage reporting against `/mnt/nfs`, then restored the original values afterward
	- hot validation confirmed `runtime/recording` in both idle and active short-clip states, then restored the default disabled listener state afterward
	- hot validation confirmed richer `runtime/streams/{id}` payloads directly and through the managed listener, and fixed aggregate `/runtime` stream entries to return runtime objects instead of stream config objects
	- hot validation confirmed `runtime/firmware` in default idle state and with a simulated pending partial-upgrade marker, then restored the default disabled listener state afterward
	- hot validation confirmed richer `runtime/system` and `health` payloads with load-average and memory fields from `/proc`, then restored the default disabled listener state afterward
	- hot validation confirmed representative send2 capability reads plus send2 setting reads and writes through the managed listener and restored the original values afterward
	- hot validation confirmed representative services and firmware capability reads through the managed listener
	- corrected full-image OTA validation now confirms the running device hashes match the rebuilt target for `thingino-agentctl`, `lib.sh`, and the prudynt adapter, and revalidates representative stream, OSD, storage, send2, runtime, health, schema, and SSE hello behavior on the flashed image before restoring the default disabled listener state
- partially implemented
	- the local non-TLS path is now native-owned for the known request tree, but `uhttpd` plus a single packaged CGI dispatcher are still retained for the current TLS path
	- bulk `PATCH /config` remains for migration
- not implemented yet
	- additional backend adapters

Review questions:

- is the API small enough to stay stable
- did we keep the northbound API independent from streamer process boundaries
- are narrow resource endpoints sufficient for normal hub and UI flows
- did we keep `GET /config` exceptional instead of making it the default read path
- are we exposing the right capability model
- are config writes clear about live apply versus restart required
- is the camera footprint acceptable

## Phase 2: Desktop hub as primary UI

Goal: make the hub the normal way to operate a Thingino fleet.

Deliverables:

- enrollment and pairing flow
- fleet dashboard
- per-camera config view
- event feed
- basic bulk operations
- initial persistent history store for action logs and coarse state samples

Review questions:

- can users operate cameras normally without the camera-hosted UI
- does the hub remain capability-driven instead of prudynt-specific
- is version skew handled well enough
- is historical storage clearly downstream from the live control path

## Phase 2a: Historical storage and analysis

Goal: preserve operational history long enough to graph, diff, and analyze fleet
behavior without distorting the control architecture.

Deliverables:

- hub-local database, starting with SQLite
- action history for native API operations and important hub workflows
- state samples for key graphable fields
- config change records or diffs
- first timeline and graph views in the hub UI

Review questions:

- are we storing normalized data for common analysis instead of only raw blobs
- does the retention policy keep growth reasonable
- can the database fail without breaking normal camera operation
- are we avoiding a second source of truth for configuration

## Phase 3: Optional camera-hosted UI over the same API

Goal: keep local fallback access without duplicating business logic.

Deliverables:

- optional package consumes the camera agent
- local UI covers bootstrap and troubleshooting cases
- camera remains usable without the package installed

Review questions:

- have we removed direct dependence on private streamer internals
- is the package genuinely optional

## Phase 4: ONVIF daemon migration

Goal: preserve interoperability while removing CGI as the main ONVIF path.

Deliverables:

- ONVIF daemon uses the canonical camera model
- required discovery and core interop still work
- CGI dependency can be retired

Review questions:

- are we maintaining only the ONVIF surface that buys real compatibility
- are we avoiding a second source of truth

## Phase 5: Additional streamer adapters

Goal: make the canonical API truly backend-neutral.

Deliverables:

- raptor adapter
- strero adapter
- capability and config mapping verified for each backend

Review questions:

- did the API remain generic enough
- which backend mismatches require model changes versus adapter logic

## Deferred work

- cloud relay
- advanced WebRTC-first deployments
- remote access productization

These should stay deferred until the local network architecture works well.

## Reassessment checklist

Use this when revisiting the design:

1. Did we add a second source of truth anywhere?
2. Did a compatibility protocol start driving native design decisions?
3. Did the camera footprint grow for hub-only features?
4. Does the hub still work from capabilities rather than backend assumptions?
5. Are security defaults still safe when features are disabled or missing?
6. Can we explain clearly which layer owns each responsibility?

## Success criteria

The architecture is working when:

- the hub is the normal management surface
- the camera UI is optional
- one canonical API serves native clients
- ONVIF and MQTT remain useful without owning the design
- adding or changing a streamer backend does not force a UI redesign