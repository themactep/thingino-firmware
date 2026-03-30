# Camera Agent Service

Status: Proposed

## Purpose

The camera agent is the canonical southbound API for Thingino-native clients.
It is the only service the hub should need in order to inspect state, change
configuration, and trigger actions on a camera.

All other camera-facing integrations should either call the agent directly or be
implemented as adapters on top of it.

## Why this service exists

Today, control logic is split across local scripts, FIFO endpoints, streamer-
specific helpers, CGI handlers, and protocol-specific integration code. That is
manageable for a single camera UI, but it does not scale cleanly to:

- multiple streamer backends
- fleet operations from a desktop hub
- consistent security and permissions
- long-term protocol compatibility

The agent gives us one stable contract while allowing each streamer backend to
keep its own internals.

## Responsibilities

- expose camera capabilities
- expose current runtime state
- expose current persisted configuration
- accept validated configuration changes
- trigger actions such as snapshot, reboot, record clip, restart streamer
- translate generic requests into backend-specific local actions
- emit state changes and lifecycle events

## Non-responsibilities

- streaming video itself
- rendering the main user interface
- being a generic automation broker
- implementing every compatibility protocol directly inside the streamer

## Local adapter model

The agent should not reimplement streamer internals. It should adapt to them.

Examples of likely local adapters:

- prudynt adapter
  - local HTTP JSON control path
  - `prudyntctl`
  - FIFO controls such as `/run/prudynt/video_ctrl` and `/run/prudynt/mp4ctl`
- raptor adapter
  - service-specific local IPC once defined
- strero adapter
  - service-specific local IPC once defined
- system adapters
  - `jct` for persisted config
  - existing motor, light, ircut, reboot, upgrade helpers

## External API shape

The external contract should stay small and versioned.

Base path:

```text
/api/v1
```

Recommended groups:

- `GET /device`
- `GET /capabilities`
- `GET /state`
- `GET /config`
- `PATCH /config`
- `POST /actions/snapshot`
- `POST /actions/record`
- `POST /actions/reboot`
- `POST /actions/streamer/restart`
- `GET /events`

## Device model

The hub should work from a stable device model rather than streamer-specific
objects.

Candidate top-level resources:

- `device`
- `network`
- `streams`
- `image`
- `audio`
- `motion`
- `daynight`
- `privacy`
- `ptz`
- `storage`
- `system`
- `firmware`

Each resource should report both:

- current runtime state
- configuration that survives restart

If those differ, the API should make that visible instead of hiding it.

## Capability model

The camera must tell the hub what it can actually do.

Examples:

- number of streams
- available transport protocols
- PTZ support
- snapshot support
- clip recording support
- audio input and output support
- privacy mask support
- day and night control support
- LED types present
- sensor count
- firmware upgrade support

The hub should hide or disable unsupported features rather than guessing.

## Configuration semantics

Configuration writes should be predictable.

Recommended rules:

- `GET /config` returns the persisted configuration model
- `PATCH /config` accepts partial updates
- validation errors are explicit and field-specific
- fields that require restart identify that requirement in the response
- responses indicate whether changes were applied live, staged, or rejected

Example response shape:

```json
{
  "status": "accepted",
  "applied": ["image.brightness"],
  "staged": ["streams[0].codec"],
  "restart_required": ["streamer"]
}
```

## Actions

Actions should stay explicit and separate from config mutation.

Examples:

- snapshot capture
- start a short recording
- restart streamer
- rotate credentials
- reboot
- start firmware install

Actions should be idempotent where practical, or return a request identifier if
they are asynchronous.

## Event stream

The first event transport should be Server-Sent Events.

Why SSE first:

- simple on both camera and hub
- fits one-way camera-to-hub updates
- easier to debug than WebSocket
- lower implementation burden for constrained devices

Event categories:

- connectivity
- stream state
- motion
- recording
- storage
- temperature and health
- firmware lifecycle
- configuration changes

## Transport and listener model

The safest default is to keep the agent local-only unless remote pairing is
enabled.

Preferred model:

- local Unix socket or `127.0.0.1` listener for on-device callers
- optional HTTPS listener for remote hub access
- no plain HTTP on untrusted networks

## Open questions

- whether the first implementation should be a thin wrapper over existing local
  helpers or own more direct process control from day one
- whether persisted config should remain file-backed through `jct` or move to a
  dedicated service later
- whether event history should exist locally or remain a hub concern

## Exit criteria for first usable version

- hub can enumerate capabilities
- hub can read runtime state and persisted config
- hub can change at least image, motion, privacy, daynight, and stream bitrate
- hub can trigger snapshot, clip, and reboot
- hub receives live events without polling-heavy behavior
- prudynt-backed cameras work without the camera-hosted web UI package