# Camera-Hosted Web UI

Status: Proposed

## Purpose

The camera-hosted web UI becomes an optional package rather than the primary
management surface.

## Why change the role

The current web UI model is tied too closely to one streamer and encourages
camera-local complexity that belongs on the desktop hub.

That shows up as:

- duplicated per-camera web stacks
- streamer-specific assumptions in UI flows
- weaker support for fleet-wide workflows
- larger on-device footprint than necessary

## Target role

The camera-hosted UI should serve as:

- emergency local access
- initial setup aid where needed
- troubleshooting fallback
- minimal standalone interface for users who want it

It should not be required for normal Thingino operation.

## Design rule

If the camera UI exists, it should consume the same canonical camera agent API
as the desktop hub. It should not call private streamer internals directly.

More specifically:

- normal controls must use narrow `/settings/*`, `/runtime/*`, and `/actions/*`
	routes
- the UI must not depend on bulk mixed camera payloads after every write
- `GET /config` is reserved for explicit full-config views such as export,
	import review, and advanced debugging

## Benefits

- less duplicated logic
- easier maintenance
- consistent behavior between hub and local UI
- simpler path to remove streamer-specific assumptions

The desktop hub is already moving in this direction. The current operator flow is
now centered on dedicated hub pages for camera controls, settings, send2,
history, and recovery, with setup rendered as an explicit ladder instead of a
page-specific collection of warnings.

## Packaging direction

- ship the camera agent independently
- make the UI package optional
- avoid making the UI a hard dependency of native remote management

## Scope for the optional UI

Good candidates:

- login and pairing bootstrap
- network diagnostics
- basic camera info
- minimal controls for image, motion, privacy, reboot
- explicit config export and advanced debug view backed by `GET /config`
- a last-resort local recovery surface when the hub cannot yet complete the
	connect or pair flow

Poor candidates:

- large fleet dashboards
- multi-camera views
- bulk editing workflows
- heavy historical analytics
- being the place where normal send2 routing or long-term configuration is
	managed once the hub is available

## Exit criteria

- cameras remain fully controllable by the hub without this package installed
- installing the package does not create a second source of truth