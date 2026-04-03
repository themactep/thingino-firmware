# Camera Agent Implementation Plan

Status: Proposed

Implementation progress: In progress

## Purpose

This document turns the camera-agent architecture into a first implementation
plan that fits the current Thingino firmware tree.

The main boundary is non-negotiable: the API belongs to the camera agent, not
to a streamer. Streamers stay behind local adapters.

## Current implementation status

Implemented in tree:

- `package/thingino-agent/` exists
- `thingino-agentctl` now acts as agent-owned core dispatch
- backend adapter loading exists
- prudynt adapter exists as the first real backend glue layer
- null adapter exists as fallback when no backend is active
- compatibility endpoints exist for `/device`, `/capabilities`, `/state`, `/config`, and current action routes
- narrow resource endpoints are installed for selected `/capabilities/*`, `/runtime/*`, and `/settings/*` paths
- `/health` exists in the package
- narrow runtime coverage now includes richer `system`, `network`, `services/streaming`, richer `streams/{id}` runtime, recorder runtime, and firmware lifecycle runtime
- narrow capability coverage now includes `services` and `firmware` through the agent-owned request tree
- narrow privacy settings now include `/settings/privacy/enabled` and `/settings/privacy/channel`
- narrow motion settings now include `/settings/motion/sensitivity` and `/settings/motion/cooldown-time`
- narrow stream settings now include enabled, audio-enabled, width, height, fps, bitrate, format, and mode reads for streams `0` and `1`
- first narrow stream OSD settings now include `/settings/streams/{0,1}/osd/enabled`, `/osd/time/enabled`, `/osd/usertext/enabled`, and `/osd/usertext/format`
- second narrow stream OSD settings now include `/settings/streams/{0,1}/osd/time/format`, `/osd/uptime/enabled`, and `/osd/uptime/format`
- third narrow stream OSD settings now include `/settings/streams/{0,1}/osd/brightness/enabled` and `/osd/brightness/format`
- remaining prudynt-backed stream OSD settings now include top-level `font-path`, `font-size`, `start-delay`, and `stroke-size`, plus the remaining `brightness`, `time`, `uptime`, `usertext`, `logo`, and `privacy` leaf paths for streams `0` and `1`
- first narrow send2 settings now include `/settings/motion/outputs/send2/{email,ftp,gphotos,mqtt,ntfy,storage,telegram,webhook}` plus `/settings/send2/services/{service}/send-photo` and `/send-video`
- first storage settings now include `/settings/storage/{autostart,channel,device-path,duration,filename,mount}`, runtime storage now includes `/runtime/storage`, and recorder runtime now includes `/runtime/recording`
- narrow stream writes now cover enabled, audio-enabled, width, height, fps, bitrate, format, and mode for streams `0` and `1`
- reboot action now exists at `/actions/reboot`
- adapter auto-selection exists through `agent.backend`
- a managed local-only listener now exists through `thingino-agentd` and `S95thingino-agent`
- the managed listener now defaults to a native local HTTP daemon for non-TLS mode, and the known local API tree is now served directly by the daemon; a single packaged CGI dispatcher at `/var/www/x/api` remains only for the current TLS or `uhttpd` compatibility path
- remote HTTPS exposure now exists through the current TLS `uhttpd` path when explicitly enabled with `agent.tls=true`, while non-TLS mode is enforced as loopback-only and remote TLS binds require `agent.token`
- `/events` now exists as an agent-owned SSE endpoint
- `/config/schema` now exists through the agent-owned config route using `PATH_INFO`

Partially implemented:

- the agent now has a native local standalone listener for the known local API tree, while `uhttpd` and a single packaged CGI dispatcher remain only for the current TLS path
- narrow settings coverage exists for image controls, motion enabled or tuning, daynight enabled or force-mode, privacy enabled or channel, and most first-pass stream controls, but not the full request tree
- compatibility bulk `PATCH /config` still exists for migration

Validated on flashed image:

- rebuilt image flashed to `192.168.88.160`
- corrected full-image OTA validation used a regenerated rootfs image, and the running `thingino-agentctl`, `lib.sh`, and prudynt adapter hashes now match the rebuilt target tree
- installed route files confirmed for health, runtime system or network or streaming, privacy settings, motion tuning, broadened stream settings, and reboot action
- `GET` validation passed for health, runtime system or network or streaming, privacy settings, motion tuning, and stream setting reads for streams `0` and `1`
- representative `PATCH` validation passed for motion sensitivity, motion cooldown time, and privacy channel with restore where applicable
- reboot action path validated through the flashed CGI wrapper using a mocked `reboot` binary so the device was not restarted
- managed local-only listener lifecycle validated by starting `S95thingino-agent` on loopback, confirming `127.0.0.1:1998`, and reading `/x/api/v1/health` plus `/x/api/v1/runtime/system`
- rebuilt-and-flashed image revalidated with in-image `thingino-agentd` and `S95thingino-agent`, including `/x/api/v1/device`, then restored to the default disabled listener state
- hot validation confirmed `/x/api/v1/config/schema` returns the current machine-readable schema and `/x/api/v1/events` streams agent-owned SSE with typed motion, recording completion, firmware lifecycle, health warning, streamer restart, and state-change events sourced from prudynt runtime signals
- rebuilt-and-flashed image revalidated `/x/api/v1/config/schema` and `/x/api/v1/events` through the in-image managed listener, then restored the default disabled listener state
- hot validation confirmed representative narrow `PATCH` support for `/x/api/v1/settings/streams/0/format` and `/x/api/v1/settings/streams/1/mode`, then restored the original stream values and default disabled listener state
- hot validation confirmed representative narrow `GET` and `PATCH` support for the first stream OSD setting paths after live script upload, then restored the original OSD values and default disabled listener state
- hot validation confirmed representative narrow `GET` and `PATCH` support for the second stream OSD setting paths after live script upload, then restored the original OSD values and default disabled listener state
- hot validation confirmed representative narrow `GET` and `PATCH` support for the third stream OSD brightness setting paths after live script upload, then restored the original OSD values and default disabled listener state
- hot validation confirmed representative narrow `GET` and `PATCH` support for the remaining OSD leaf paths including `font-size`, `time/position`, and `logo/transparency`, then restored the original OSD values and default disabled listener state
- hot validation confirmed representative direct and managed-listener support for storage `duration` and `mount`, plus runtime storage reporting against `/mnt/nfs`, then restored the original storage values and default disabled listener state
- hot validation confirmed direct and managed-listener support for `/runtime/recording`, including idle state and a short active clip state from prudynt's recorder marker, then restored the default disabled listener state
- hot validation confirmed direct and managed-listener support for richer `/runtime/streams/{id}` payloads, including RTSP listener state and per-stream recording activity, and fixed `/runtime` aggregate stream entries to use runtime objects instead of config objects
- hot validation confirmed direct and managed-listener support for `/runtime/firmware`, including default idle state and a simulated pending partial-upgrade marker, then restored the default disabled listener state
- hot validation confirmed richer `/runtime/system` and `/health` payloads with load-average and memory fields sourced from `/proc`, then restored the default disabled listener state
- hot validation confirmed representative narrow `GET` and `PATCH` support for the first send2 capability and setting paths after live script upload, then restored the original send2 values and default disabled listener state
- hot validation confirmed representative narrow `GET` support for `/x/api/v1/capabilities/services` and `/x/api/v1/capabilities/firmware` after live script upload
- rebuilt-and-flashed image validation now confirms representative stream `format` writes, OSD `time/format` reads or writes, storage `mount` and `duration` reads or writes, runtime storage reads, send2 telegram reads or writes, richer `/runtime/system`, richer `/health`, current schema event types, and `/events` hello output, then restores the default disabled listener state
- rebuilt-and-flashed image validation now also confirms the in-image native listener binary is the active non-TLS transport, with representative `/x/api/v1/device`, `/x/api/v1/config/schema`, `/x/api/v1/runtime/system`, and `/x/api/v1/events` SSE hello behavior all passing before restore to the default disabled listener state
- rebuilt-and-flashed image validation now also confirms `agent.tls=true` starts `uhttpd` on `127.0.0.1:1998` and serves the same representative `/x/api/v1/device`, `/x/api/v1/runtime/system`, `/x/api/v1/config/schema`, and `/x/api/v1/events` routes through the packaged single-file dispatcher at `/var/www/x/api`, then restores the default disabled listener state
- live validation now also confirms remote exposure policy on the updated wrapper and init path: non-TLS `agent.listen=0.0.0.0` fails closed, TLS `agent.listen=0.0.0.0` without `agent.token` fails closed, and authenticated remote HTTPS requests return `401` without a bearer token and `200` with the configured bearer token, then restore the default disabled listener state
- live validation now also confirms the native non-TLS path does not require the packaged `/var/www/x/api` compatibility dispatcher: after temporarily removing that file on the flashed camera, representative `/x/api/v1/device`, `/x/api/v1/config/schema`, and `/x/api/v1/events` requests still passed through the daemon, then the file and default disabled listener state were restored
- hot validation with the rebuilt native listener now confirms `/runtime/system`, `/settings/motion/sensitivity` GET or PATCH, and `/actions/snapshot` continue to work even after their installed CGI route files are temporarily removed on the live camera, proving those paths are now directly owned by the daemon rather than the CGI fallback path, with state restored afterward
- hot validation with the rebuilt native listener now also confirms `/actions/privacy`, `/actions/daynight`, and `/actions/record` continue to work even after their installed CGI route files are temporarily removed on the live camera, proving those action paths are directly owned by the daemon rather than the CGI fallback path, with temporary runtime state and test artifacts restored afterward
- hot validation with the rebuilt native listener now also confirms the remaining top-level routes and generic resource path are no longer required for the local API path: after temporarily removing `device`, `health`, `capabilities`, `state`, `config`, `events`, and `resource.cgi`, representative top-level, runtime, settings, schema, and SSE requests still passed through the daemon, with the installed files restored afterward

Not implemented yet:

- additional backend adapters beyond prudynt
- native TLS or an intentional proxy design to replace the current `uhttpd` TLS path

## First implementation target

Build the standalone camera agent first, with one production adapter at the
start.

Reason:

- it keeps the canonical API independent from any specific streamer process
- we can validate the API model with one backend without freezing a prudynt-only shape
- existing prudynt local control primitives make it the easiest first adapter

That means:

- phase 1 may ship a prudynt adapter first
- phase 1 must not embed the HTTP API inside prudynt
- later adapters must plug into the same agent without changing northbound API paths

## Packaging strategy

Introduce a new package:

```text
package/thingino-agent/
```

Expected contents:

- `Config.in`
- `thingino-agent.mk`
- daemon source or bundled artifact
- init script
- optional config file template
- backend adapter directory or dispatch layer

## Runtime shape

The first version should run as a small daemon with two listener modes:

- local-only listener by default, with non-TLS binds enforced as loopback-only
- optional remote HTTPS listener when explicitly enabled, with bearer-token protection required for non-loopback TLS binds

Prefer one daemon over adding more CGI or shell wrappers.

The daemon should own:

- HTTP routing
- request validation
- response shaping
- auth and pairing policy
- event fan-out

Adapters should own only backend translation.

Example split:

- camera agent
	- serves `/api/v1/*`
	- maps requests to canonical resources
	- chooses the active adapter
- prudynt adapter
	- converts canonical image, motion, daynight, snapshot, and record operations
		into `prudyntctl`, FIFOs, init scripts, and runtime-file reads
- future adapters
	- expose the same canonical resources through their own local glue

## Recommended first features

### Reads

- device identity
- capabilities
- runtime state
- persisted config

### Writes

- image controls
- motion enable or disable
- privacy enable or disable
- day or night force mode
- stream bitrate changes

### Actions

- snapshot
- short clip
- streamer restart
- reboot

### Events

- SSE stream with a small set of state changes

## Local integration plan

### Adapter contract

The first implementation should define a narrow internal adapter contract before
adding more routes.

Minimum adapter responsibilities:

- report backend identity and availability
- read local runtime state for supported resources
- read persisted config for supported resources
- apply live config changes for supported resources
- report whether a change was applied live, staged, or requires restart
- execute explicit actions such as snapshot, clip, and service restart

Minimum agent responsibilities:

- select the active adapter
- expose the canonical HTTP API
- validate request payloads and path parameters
- keep response envelopes backend-neutral
- expose capability flags based on adapter support
- avoid leaking backend-native field names unless explicitly namespaced

### Persisted config

Use existing `jct` interactions initially instead of inventing a new storage
layer.

### Runtime updates

Use existing local interfaces through the active adapter, starting with prudynt:

- `prudyntctl json -`
- `prudyntctl snapshot`
- `/run/prudynt/mp4ctl`
- `/run/prudynt/video_ctrl`
- `/etc/init.d/S31prudynt`

### State gathering

Gather state through the active adapter from:

- config files for persisted intent
- runtime files under `/run/prudynt`
- process checks and init status
- network information already available in system helpers

When non-prudynt adapters are added, they should satisfy the same contract with
their own local data sources.

## Implementation language

The design intentionally does not force a language, but the selection criteria
for the first implementation are:

- small runtime footprint
- straightforward HTTPS and SSE support
- easy JSON handling
- simple process and file integration

Whatever is chosen, the daemon should remain thin and avoid pulling in a large
web framework.

## Buildroot integration

The first package should:

- be selectable independently of the optional camera web UI
- depend only on the minimum TLS and HTTP stack it needs
- not force ONVIF or MQTT packages to be installed
- not depend on a single streamer package owning the external API listener

Candidate integration tasks:

1. done: add `package/thingino-agent/Config.in`
2. done: add package include under the relevant menu
3. done in initial form: install agent script and support files
4. done in local-only form: install init script and managed listener lifecycle
5. pending: add any required TLS helper dependencies for remote exposure
6. done: add the first backend adapter, starting with prudynt

## Suggested init behavior

- start after network basics and local streamer controls are available
- do not fail hard when the streamer is down; surface degraded state instead
- allow the local-only control surface to start before remote exposure is enabled
- detect backend availability dynamically instead of assuming one streamer owns the API

Current lifecycle shape:

- `S95thingino-agent` manages the local-only listener lifecycle
- `thingino-agentd` starts the native listener on `agent.listen:agent.port` by default and falls back to a dedicated `uhttpd` instance only when `agent.tls=true`
- `thingino-agentd` enforces loopback-only non-TLS binds and requires `agent.token` before allowing non-loopback TLS exposure
- the managed listener serves `/var/www` with CGI prefix `/x`, so the agent continues to expose `/x/api/v1/*`
- default config keeps the listener disabled until explicitly enabled in `thingino.json`

## Risks

- too much shelling out can make the daemon slow or fragile
- too much backend-specific logic in v1 can freeze the wrong model
- serving the API from a streamer would lock the northbound contract to one backend boundary
- serving the API through CGI for too long would keep request handling and auth weaker than a native agent server
- remote exposure before auth is solid creates avoidable risk

## Acceptance checklist for the first package

- in progress: package files parse cleanly and install layout is defined in the tree
- in progress: camera-agent logic is independent from streamer-owned HTTP routing
- in progress: at least one real adapter, starting with prudynt, exists in the tree
- in progress: managed local-only listener lifecycle exists without requiring the main camera web UI to own the agent port
- in progress: the agent can read capabilities and runtime state through the prudynt adapter
- in progress: the agent can write a small config subset successfully in the prudynt adapter path
- in progress: snapshot and clip actions are wired through the prudynt adapter
- done: optional camera web UI compatibility assets are not required for the native non-TLS listener path

Current validation notes:

- shell syntax checks passed for the installed agent scripts
- a clean firmware image including the package was built and flashed to a camera
- on-device smoke validation passed for representative routes including `/device`, `/runtime/motion`, `/settings/image/hflip`, `/config`, `/state`, snapshot, and narrow `PATCH /settings/*`
- live testing exposed and fixed a JSON encoding bug in prudynt stream `format` and `mode` fields
- local-only managed listener lifecycle is wired in-tree and live-validated on the flashed image with temporary enable plus restore
- live validation now confirms the native non-TLS listener continues to work even when the packaged `/var/www/x/api` compatibility dispatcher file is temporarily absent, so the camera-hosted web compatibility asset is not required for the native path
- broad runtime coverage and full request-tree validation are still pending