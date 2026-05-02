# Camera API Request Tree

Status: Proposed

## Purpose

This document defines the target request tree for the Thingino camera API.

Primary rule:

- only `GET /api/v1/config` may return the full persisted configuration
- all other endpoints must return only the local resource they own
- normal UI controls should read or write narrow resources, not bulk documents

This is the contract the hub, optional camera UI, and future adapters should
target during the refactor.

## Design rules

### One full-document read endpoint

`GET /api/v1/config` is the only endpoint allowed to return the whole canonical
configuration tree.

Use cases:

- backup and export
- import review
- advanced debug view
- full diff tooling

It is not the normal endpoint for dashboards, toggles, sliders, or per-field
editing.

### No omnibus reads for normal operation

The API should stop treating `state`, `capabilities`, and `config` as the
default answer to every request.

Normal clients should ask for the narrow subtree or single value they need.

Examples:

- a brightness slider asks for `GET /api/v1/settings/image/brightness`
- a motion toggle uses `GET /api/v1/settings/motion/enabled` and `PATCH` on the
  same path
- the live view asks for `GET /api/v1/runtime/streams/0`
- a preview button uses `POST /api/v1/actions/snapshot`

### Small writes must not require full readback

After `PATCH /api/v1/settings/image/hflip`, the response should describe only
that write result.

It should not append the full config, full state, or a large mixed camera blob.

### Local resource shape

Responses should return either:

- a local subtree
- a single named value
- a mutation envelope naming the applied field paths

Examples:

```json
{
  "hflip": true
}
```

```json
{
  "status": "accepted",
  "applied": ["settings.image.hflip"],
  "restart_required": []
}
```

## Request tree

```text
/api/v1
├── /device
├── /health
├── /events
├── /config
├── /config/schema
├── /capabilities
│   ├── /image
│   ├── /motion
│   ├── /daynight
│   ├── /privacy
│   ├── /storage
│   ├── /streams
│   ├── /services
│   └── /send2
├── /runtime
│   ├── /network
│   ├── /system
│   ├── /motion
│   ├── /daynight
│   ├── /privacy
│   ├── /storage
│   ├── /recording
│   ├── /firmware
│   ├── /streams
│   │   └── /{id}
│   └── /services
│       └── /streaming
├── /settings
│   ├── /image
│   │   ├── /brightness
│   │   ├── /contrast
│   │   ├── /saturation
│   │   ├── /sharpness
│   │   ├── /anti-flicker
│   │   ├── /hflip
│   │   └── /vflip
│   ├── /motion
│   │   ├── /enabled
│   │   ├── /sensitivity
│   │   ├── /cooldown-time
│   │   └── /outputs
│   │       └── /send2
│   │           └── /{service}
│   ├── /daynight
│   │   ├── /enabled
│   │   └── /force-mode
│   ├── /privacy
│   │   ├── /enabled
│   │   └── /channel
│   ├── /storage
│   │   ├── /autostart
│   │   ├── /channel
│   │   ├── /device-path
│   │   ├── /duration
│   │   ├── /filename
│   │   └── /mount
│   ├── /streams
│   │   └── /{id}
│   │       ├── /enabled
│   │       ├── /audio-enabled
│   │       ├── /width
│   │       ├── /height
│   │       ├── /fps
│   │       ├── /bitrate
│   │       ├── /format
│   │       ├── /mode
│   │       └── /osd
│   │           ├── /enabled
│   │           ├── /font-path
│   │           ├── /font-size
│   │           ├── /start-delay
│   │           ├── /stroke-size
│   │           ├── /brightness
│   │           │   ├── /enabled
│   │           │   ├── /fill-color
│   │           │   ├── /format
│   │           │   ├── /position
│   │           │   ├── /rotation
│   │           │   └── /stroke-color
│   │           ├── /time
│   │           │   ├── /enabled
│   │           │   ├── /fill-color
│   │           │   ├── /format
│   │           │   ├── /position
│   │           │   ├── /rotation
│   │           │   └── /stroke-color
│   │           ├── /uptime
│   │           │   ├── /enabled
│   │           │   ├── /fill-color
│   │           │   ├── /format
│   │           │   ├── /position
│   │           │   ├── /rotation
│   │           │   └── /stroke-color
│   │           ├── /usertext
│   │           │   ├── /enabled
│   │           │   ├── /fill-color
│   │           │   ├── /format
│   │           │   ├── /position
│   │           │   ├── /rotation
│   │           │   └── /stroke-color
│   │           ├── /logo
│   │           │   ├── /enabled
│   │           │   ├── /height
│   │           │   ├── /path
│   │           │   ├── /position
│   │           │   ├── /rotation
│   │           │   ├── /transparency
│   │           │   └── /width
│   │           └── /privacy
│   │               ├── /enabled
│   │               ├── /fill-color
│   │               ├── /font-size
│   │               ├── /image-height
│   │               ├── /image-path
│   │               ├── /image-width
│   │               ├── /layer
│   │               ├── /opacity
│   │               ├── /position
│   │               ├── /rotation
│   │               ├── /stroke-color
│   │               ├── /stroke-size
│   │               └── /text
│   └── /send2
│       ├── /motion/sensitivity
│       ├── /motion/cooldown-time
│       └── /services
│           └── /{service}
│               ├── /send-photo
│               └── /send-video
└── /actions
    ├── /snapshot
    ├── /record
    ├── /reboot
    └── /services
        └── /{service}
            ├── /start
            ├── /stop
            └── /restart
```

## Endpoint roles

### Metadata

- `GET /device`: identity, model, software inventory
- `GET /health`: coarse operational status suitable for probes and roster views
- `GET /events`: event stream, not a config substitute

### Full config

- `GET /config`: full canonical persisted configuration
- `GET /config/schema`: machine-readable schema and constraints for tooling

No other route should return the whole config tree.

### Capabilities

Capability reads should also be narrow.

Allowed:

- `GET /capabilities/image`
- `GET /capabilities/daynight`
- `GET /capabilities/streams`

Transition-only compatibility:

- `GET /capabilities` may exist temporarily, but should be treated as a legacy
  bootstrap route and not the default call path for the hub UI

### Runtime

Runtime data should be read from dedicated runtime resources.

Examples:

- `GET /runtime/daynight`
- `GET /runtime/motion`
- `GET /runtime/storage`
- `GET /runtime/recording`
- `GET /runtime/firmware`
- `GET /runtime/streams/0`
- `GET /runtime/services/streaming`

Transition-only compatibility:

- `GET /state` may exist during migration, but the target architecture should
  move clients to the narrower `/runtime/*` resources

### Settings

Settings endpoints own persisted values and small write operations.

Examples:

- `GET /settings/image/hflip` -> `{"hflip": true}`
- `PATCH /settings/image/hflip` with `{"hflip": true}`
- `GET /settings/storage/mount`
- `PATCH /settings/storage/mount`
- `GET /settings/daynight/force-mode`
- `PATCH /settings/streams/0/bitrate`
- `PATCH /settings/send2/services/telegram/send-photo`

### Actions

Actions remain explicit commands rather than pretending to be config writes.

Examples:

- `POST /actions/snapshot`
- `POST /actions/record`
- `POST /actions/services/streaming/restart`

## Response scope rules

### Allowed response scopes

- full config: `GET /config` only
- subtree: the subtree addressed by the requested endpoint
- leaf value: the field addressed by the requested endpoint
- mutation envelope: `status`, `applied`, `staged`, `restart_required`, and
  optionally the updated local resource

### Forbidden response scopes

- returning the entire config from `PATCH /settings/...`
- returning the entire camera state from `POST /actions/...`
- returning capabilities from unrelated writes
- mixing state, config, history, and action results into one general-purpose
  camera blob

## Current-to-target mapping

| Current route | Target direction |
| --- | --- |
| `GET /device` | keep |
| `GET /capabilities` | split into `/capabilities/*`; keep temporary bootstrap compatibility |
| `GET /state` | split into `/runtime/*`; de-emphasize omnibus state reads |
| `GET /config` | keep as the only full-config read |
| `PATCH /config` | de-emphasize for normal UI writes; keep only for bulk import or advanced tools during transition |
| `POST /actions/privacy` | replace with narrow settings endpoints under `/settings/privacy/*` unless truly action-like semantics remain |
| `POST /actions/daynight` | replace with `/settings/daynight/*` for normal mode control |
| `POST /actions/snapshot` | keep |
| `POST /actions/record` | keep |
| `POST /actions/services/{service}/{operation}` | keep |

## Hub implications

The hub client should stop using a coarse probe for routine operations.

Target read patterns:

- dashboard cards: `device`, `health`, selected runtime endpoints
- camera detail controls: only the matching settings endpoints
- full config screen: `GET /config`
- preview/snapshot UI: `runtime/streams/*` and `actions/snapshot`

## Camera UI implications

The optional camera-hosted UI must follow the same rule set.

- toggles and sliders must not call `GET /config` after every write
- quick controls must not expect bulk camera payloads as mutation responses
- export and advanced debug pages may call `GET /config`

## Migration note

This tree is the target shape. The migration may temporarily keep coarse routes
for compatibility, but all new work should move clients to narrow resources and
remove bulk response payloads from normal actions.