# Thingino Camera API RFC

Status: Proposed

## Purpose

This document defines the first concrete Thingino-native network API between the
desktop hub and a camera.

It is intentionally small. The goal is not to model every internal detail on
day one, but to define a stable and practical contract that works across
streamer backends.

## Design goals

- simple enough to implement on constrained cameras
- expressive enough for the desktop hub to manage real devices
- explicit about capability detection and partial support
- versioned from the beginning
- separate control from media transport

## Transport

- remote transport: HTTPS
- local transport: Unix socket or `127.0.0.1`
- payload format: JSON
- event stream: Server-Sent Events

Base path:

```text
/api/v1
```

## Authentication

The final auth model is defined in [security.md](security.md), but the API must
already assume authenticated callers.

Headers reserved for authenticated use:

- `Authorization: Bearer <token>`
- client certificate identity when mutual TLS is enabled

## Common response envelope

Simple reads may return raw resources. Mutations and actions should use an
envelope.

Example:

```json
{
  "status": "accepted",
  "request_id": "2d7f7f8d5c8448d8",
  "applied": ["image.brightness"],
  "staged": [],
  "restart_required": []
}
```

## Error format

```json
{
  "status": "error",
  "error": {
    "code": "validation_failed",
    "message": "Invalid config value",
    "fields": [
      {
        "path": "image.brightness",
        "message": "must be between 0 and 255"
      }
    ]
  }
}
```

## Resource model

### `GET /device`

Returns camera identity and software inventory.

Example:

```json
{
  "id": "0244dd22592e",
  "name": "front-door",
  "hostname": "thingino-front-door",
  "manufacturer": "Thingino",
  "model": "atom_cam2_t31x_gc2053_atbm6031",
  "hardware": {
    "soc_family": "t31",
    "soc_model": "t31x",
    "sensor": "gc2053"
  },
  "software": {
    "firmware_version": "master-20260329",
    "streamer": "prudynt",
    "api_version": "1"
  }
}
```

### `GET /capabilities`

Returns what the camera can actually do.

Example:

```json
{
  "streams": {
    "count": 2,
    "rtsp": true,
    "webrtc": false,
    "snapshot": true,
    "clip_recording": true
  },
  "audio": {
    "input": true,
    "output": false
  },
  "ptz": {
    "enabled": false
  },
  "daynight": {
    "enabled": true,
    "modes": ["auto", "day", "night"]
  },
  "privacy": {
    "enabled": true
  },
  "firmware": {
    "upgrade": true
  }
}
```

### `GET /state`

Returns runtime state suitable for dashboards and operational views.

Example:

```json
{
  "system": {
    "uptime_seconds": 12345,
    "temperature_c": 54.2,
    "streamer_running": true
  },
  "network": {
    "ip": "192.168.1.50",
    "online": true
  },
  "motion": {
    "enabled": true,
    "active": false
  },
  "daynight": {
    "mode": "auto",
    "running_mode": "day"
  },
  "privacy": {
    "enabled": false
  },
  "streams": [
    {
      "id": 0,
      "codec": "h264",
      "bitrate": 2048000,
      "fps": {
        "num": 15,
        "den": 1
      },
      "healthy": true
    }
  ]
}
```

### `GET /config`

Returns persisted configuration in the canonical model.

The configuration schema should map to stable Thingino concepts rather than raw
backend internals. Backend-specific fields can exist under a namespaced escape
hatch when unavoidable.

### `PATCH /config`

Applies a partial config update.

Request example:

```json
{
  "image": {
    "brightness": 128,
    "anti_flicker": 1
  },
  "motion": {
    "enabled": true
  },
  "streams": [
    {
      "id": 0,
      "bitrate": 3072000
    }
  ]
}
```

Response example:

```json
{
  "status": "accepted",
  "applied": [
    "image.brightness",
    "image.anti_flicker",
    "motion.enabled",
    "streams[0].bitrate"
  ],
  "staged": [],
  "restart_required": []
}
```

## Actions

### `POST /actions/snapshot`

Request:

```json
{
  "stream_id": 0,
  "mode": "inline"
}
```

Response options:

- direct JPEG body when `mode=inline`
- JSON containing a temporary URL when `mode=url`

### `POST /actions/record`

Request:

```json
{
  "stream_id": 0,
  "duration_seconds": 10,
  "mode": "url"
}
```

Response:

```json
{
  "status": "accepted",
  "request_id": "clip-01j0example",
  "result": {
    "url": "/api/v1/jobs/clip-01j0example/result"
  }
}
```

### `POST /actions/streamer/restart`

Request body may be empty.

### `POST /actions/reboot`

Request body may be empty or include a reason string.

### `POST /actions/firmware/install`

Deferred until the hub and camera trust model is implemented well enough.

## Media endpoints

The API should expose media metadata, not replace RTSP.

### `GET /streams`

Returns stream descriptors.

Example:

```json
[
  {
    "id": 0,
    "name": "main",
    "codec": "h264",
    "rtsp_url": "rtsp://192.168.1.50:554/ch0",
    "snapshot_path": "/api/v1/actions/snapshot?stream_id=0"
  },
  {
    "id": 1,
    "name": "sub",
    "codec": "h264",
    "rtsp_url": "rtsp://192.168.1.50:554/ch1"
  }
]
```

## Events

### `GET /events`

Returns an SSE stream.

Event types:

- `state.changed`
- `motion.started`
- `motion.stopped`
- `streamer.restarted`
- `record.completed`
- `firmware.progress`
- `health.warning`

Example event payload:

```json
{
  "type": "state.changed",
  "timestamp": "2026-03-29T21:00:00Z",
  "paths": ["privacy.enabled", "daynight.running_mode"]
}
```

## Backend mapping notes

The initial implementation should map the canonical model to existing prudynt
controls where possible:

- config writes via `prudyntctl json -` and `jct`
- snapshots via `prudyntctl snapshot`
- clip recording via `/run/prudynt/mp4ctl`
- privacy via `/run/prudynt/video_ctrl`
- streamer restart via init scripts

This keeps the first version practical and testable.

## Explicit non-goals for v1

- full CRUD over every backend-specific field
- replacing ONVIF for third-party NVRs
- carrying live video inside the control API
- introducing WebSocket before SSE proves insufficient