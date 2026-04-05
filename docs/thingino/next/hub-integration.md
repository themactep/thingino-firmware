# Hub Integration Notes

Status: Proposed

Implementation progress: In progress

## Purpose

This document maps the target architecture to the existing hub project located
at `/home/paul/thingino/hub`.

## Current hub baseline

The current hub is already useful and should be evolved rather than replaced.

Observed structure:

- Python application
- MQTT client and routing logic
- Telegram bot integration
- server-rendered web UI
- ONVIF device identity lookup
- snapshot preview caching
- persisted camera registry and config editing
- native camera-agent client layer
- SQLite-backed history store and timeline views

Relevant files in the current hub:

- `app/main.py`
- `app/web.py`
- `config.example.yaml`

## What the current hub already solves well

- one shared Telegram bot token for many cameras
- fan-out of commands over MQTT
- small operator-facing dashboard
- camera identity and roster persistence
- simple camera detail pages

## What it does not yet solve cleanly

- fully polished autodiscovery and one-click connection for every recovery case
- lightweight regression coverage for response-shape and queued-refresh behavior
- deeper historical analysis such as graphs and config diffs

## Integration target

The hub should gain a new camera-agent client layer while preserving current
MQTT and ONVIF features.

Recommended layering:

```text
web UI / Telegram handlers
        |
hub service layer
        |
+----------------------+----------------------+------------------+
| camera-agent client  | MQTT bridge client   | ONVIF client     |
+----------------------+----------------------+------------------+
```

## Recommended next refactor

Introduce a hub-side camera service abstraction so the UI and Telegram flows do
not talk directly to raw MQTT payload formats forever.

Candidate responsibilities for that abstraction:

- fetch device and capability information
- fetch runtime state
- fetch full config only for explicit config screens, backup, and diff tools
- fetch and patch narrow settings resources for normal UI controls
- trigger snapshot, clip, reboot, and restart actions
- emit normalized action and state records to a hub-local history writer
- fall back to MQTT or ONVIF only where native API is not present yet

Current progress against that refactor:

- the hub already has a native camera-agent client layer
- native API-capable cameras now drive camera detail controls through capability-aware fields
- quick controls and camera-page refresh actions no longer require full camera payload reads on every interaction
- dedicated `/status`, `/events`, and `/enroll` pages now separate runtime status, live events, and onboarding from the main roster
- the preferred connect path now uses discovered roster identity plus valid credentials instead of manual camera-ID entry
- pairing repair now handles missing camera MQTT command subscriptions and avoids copying container-local broker aliases into camera config
- the remaining work is to keep page-open hydration and slower secondary reads narrow, cached, and well-tested

The target request tree and response-scope rules are defined in
[request-tree.md](request-tree.md).

## Compatibility strategy during transition

### MQTT stays first-class for existing Telegram command routing

Do not break the current Telegram-to-MQTT workflow while the camera agent is new.

### ONVIF remains useful for identity and compatibility

Keep current ONVIF identity lookup until the camera API exposes equivalent data.

### Prefer canonical API when available

As soon as a camera reports a working camera-agent endpoint, the hub should
prefer it for:

- state fetch
- config reads and writes
- snapshots
- action triggers

## Suggested config evolution

The existing `config.yaml` can grow camera-agent fields without breaking current
deployments.

Suggested per-camera additions:

```yaml
cameras:
  - id: "0244dd22592e"
    name: "front-door"
    api_base_url: "https://192.168.1.50/api/v1"
    api_token: ""
    snapshot_url: ""
    onvif_endpoint: "http://192.168.1.50/onvif/device_service"
```

Suggested global UI behavior:

- show transport used per camera: native API, MQTT-only, ONVIF-only
- show capability load failures clearly
- avoid hiding working cameras just because one transport is unavailable
- keep destructive or stateful actions on the camera detail page instead of adding roster-card clutter

## Immediate implementation opportunities in the hub

1. keep tightening the credentials-first connect path until autodiscovered cameras are adoptable with one obvious action in the common case
2. add lightweight regression coverage for connect and override-preservation behavior next to the existing queued-refresh and minimal-response tests
3. shorten repetitive quick-action messages so the UI feedback stays concise
4. cache or defer slower secondary reads such as send2 overview fetches if they become the next latency source
5. continue reserving `GET /config` for explicit config screens and tooling

## Historical storage integration

The existing hub is a good place to add a local history layer, but that layer
should sit beside the service logic rather than inside every request path.

Recommended approach:

1. add a small history writer component in the hub service
2. enqueue action and state records from native API flows and probe loops
3. batch writes to a local SQLite database in WAL mode
4. build timeline and graph views on top of stored samples

Important boundary:

- the UI may read history from the database
- the control path should not require the database to issue live camera actions

The same rule applies to API reads: quick controls should not require fetching
full camera config or full runtime blobs before every write.

That principle is now partly implemented in the current hub and should continue
to guide the remaining Phase 2 work.

This lets history and graphs grow in parallel with the native API rollout
without turning analytics storage into a dependency for core operation.

## Success criteria

- current hub features keep working during transition
- native API-capable cameras expose richer state in the same UI
- Telegram flows can gradually move from MQTT command strings to typed actions
- autodiscovered cameras can be connected and recovered without asking the operator to know or type the hub-facing camera identity

The next development phase remains Phase 2 hub completion, with only narrow
Phase 2a additions when they directly support the hub becoming the normal
operator surface.