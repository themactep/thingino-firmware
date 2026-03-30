# Implementation Roadmap

Status: Proposed

## Purpose

This file turns the architecture into a sequence of work that can be reviewed,
reassessed, and changed as implementation teaches us more.

## Phase 1: Canonical camera API on prudynt-backed cameras

Goal: make one streamer backend controllable through a stable network API.

Deliverables:

- camera agent service exists
- local prudynt adapter exists
- API can expose capabilities, runtime state, and persisted config
- API supports a small set of actions: snapshot, clip, reboot, restart streamer
- SSE event stream exists

Review questions:

- is the API small enough to stay stable
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