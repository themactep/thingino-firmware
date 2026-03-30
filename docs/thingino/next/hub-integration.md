# Hub Integration Notes

Status: Proposed

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

- canonical Thingino-native camera control
- capability-driven configuration UI
- distinction between runtime state and persisted config on the device
- hub-native understanding of non-MQTT actions and device resources
- long-lived historical storage for graphs, timelines, and drift analysis

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
- fetch and patch camera config
- trigger snapshot, clip, reboot, and restart actions
- emit normalized action and state records to a hub-local history writer
- fall back to MQTT or ONVIF only where native API is not present yet

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

## Immediate implementation opportunities in the hub

1. add a lightweight camera-agent client module
2. extend camera state model to store capabilities and API reachability
3. add a native API probe on registration refresh
4. prefer native snapshot action over raw snapshot URL when available
5. add camera config read and patch screens backed by the native API

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

This lets history and graphs grow in parallel with the native API rollout
without turning analytics storage into a dependency for core operation.

## Success criteria

- current hub features keep working during transition
- native API-capable cameras expose richer state in the same UI
- Telegram flows can gradually move from MQTT command strings to typed actions