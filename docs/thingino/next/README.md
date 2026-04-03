# Thingino Next Architecture

This directory tracks the target architecture for moving Thingino from a
camera-hosted web UI to a centralized desktop hub that can manage many cameras.

The intent is practical:

- define a small canonical control plane for cameras
- keep the camera footprint low
- support multiple streamer backends without redesigning the API per streamer
- preserve compatibility with third-party tooling where it matters
- make decisions explicit so they can be reviewed and changed later

## Status

This is a working design set, not a frozen specification.

- Proposed: direction we believe is right and want to build toward
- Accepted: direction we have validated enough to implement by default
- Deferred: useful idea, but not required for the first usable system
- Rejected: considered and intentionally not pursuing

Unless a file says otherwise, treat its current contents as Proposed.

## Core direction

Thingino should expose one canonical southbound API from each camera and let
other protocols adapt to it.

The preferred split is:

- control plane: HTTPS JSON API
- state/events: Server-Sent Events
- media plane: RTSP first, WebRTC where it solves a real problem
- automation bus: MQTT bridge, optional
- interoperability: ONVIF adapter, optional
- camera-hosted UI: optional package, no longer the primary control surface

This keeps the camera small and lets the desktop hub own discovery, fleet view,
multi-camera workflows, bulk configuration, and richer monitoring.

## Service map

- [camera-agent.md](camera-agent.md): canonical API service on the camera
- [api-rfc.md](api-rfc.md): concrete API resources, actions, and payloads
- [request-tree.md](request-tree.md): target request tree and response-scope rules
- [camera-agent-implementation.md](camera-agent-implementation.md): first package and daemon plan in this tree
- [hub.md](hub.md): centralized desktop service and UI
- [hub-integration.md](hub-integration.md): how the existing `/home/paul/thingino/hub` fits and evolves
- [history-analytics.md](history-analytics.md): database-backed historical storage, graphs, and fleet analysis
- [media.md](media.md): streaming and snapshot transport
- [onvif.md](onvif.md): interoperability adapter
- [onvif-migration.md](onvif-migration.md): task list to replace CGI-backed ONVIF service
- [mqtt-bridge.md](mqtt-bridge.md): automation and Home Assistant integration
- [camera-web-ui.md](camera-web-ui.md): optional on-camera UI package
- [security.md](security.md): pairing, auth, transport security, permissions
- [roadmap.md](roadmap.md): phased rollout, review checkpoints, and exit criteria

## Design principles

### One canonical device model

The hub should not need to know whether a camera runs prudynt, raptor, or
strero. The camera API presents stable resources and capability flags; backend
adapters translate those resources to local implementation details.

That model should be accessed through narrow resource endpoints. Full-document
reads are exceptional and should be limited to explicit config export or debug
flows.

### Low camera footprint

The camera should avoid large web stacks and duplicate services. If a protocol
exists only for compatibility, it should be an adapter over the canonical API,
not a second source of truth.

### Clear boundary between media and control

Media transport and device control solve different problems and should remain
separate. Video should flow through media protocols. Configuration, state, and
commands should flow through the control plane.

### Capability-driven hub

The hub renders features based on camera-reported capabilities rather than hard-
coding assumptions about sensors, motors, streamers, or GPIO features.

### History is downstream, not authoritative

The hub may store long-term history for graphs, audits, and analysis, but that
store must remain downstream from live camera control. The camera remains the
source of truth for device state and configuration; the history store is an
analytics layer, not a second control plane.

### Security defaults matter

Remote control should not require exposing unauthenticated local helpers.
Pairing, transport security, and authorization need to be part of the design,
not a later patch.

## What this design is not

- not a commitment to a specific implementation language
- not a full REST purity exercise
- not a requirement to remove ONVIF or MQTT
- not a promise that every camera must run every service

## Current repo observations

The current tree already points toward this split:

- streamer selection is abstracted in `package/thingino-streamer`
- prudynt already exposes a local JSON control surface used by wrappers
- HA integration already uses MQTT as an integration bus, not the main model
- ONVIF discovery and notification are daemonized, but the main ONVIF service is
  still CGI-backed

That makes the most practical next step a dedicated camera agent that becomes
the one network-facing control service for Thingino-native clients.

## How to use this directory

When work starts on a service:

1. confirm the file still reflects reality
2. record any design changes in-place
3. keep scope, risks, and open questions current
4. move stable decisions from Proposed to Accepted

When a document becomes wrong, update it instead of letting it rot.