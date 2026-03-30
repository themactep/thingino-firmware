# ONVIF Service

Status: Proposed

## Purpose

ONVIF remains important for interoperability, but it should no longer define the
native Thingino control model.

The recommended role for ONVIF is compatibility adapter.

## Current problem

The current ONVIF implementation still routes the primary service through CGI.
That makes it a poor foundation for the long-term control plane even if the
feature set itself remains useful.

## Target role

ONVIF should provide:

- discovery for third-party clients
- media and imaging interoperability where supported
- PTZ interoperability where supported
- event compatibility where worth the effort

It should not be the primary API used by the Thingino desktop hub.

## Recommended architecture

Rewrite ONVIF as a real daemon, but make it an adapter over the canonical camera
agent rather than a parallel implementation.

That means:

- ONVIF requests translate into camera-agent operations
- ONVIF state and capabilities derive from the same canonical model
- security and authorization remain consistent with the rest of the system

## Why not make ONVIF the native API

- SOAP and ONVIF profile semantics are heavy for first-party control
- the model is shaped for interoperability, not for Thingino-native UX
- configuration workflows are awkward compared to a small JSON API
- using ONVIF as the core would push complexity into every new feature

## What should stay compatible

- device discovery
- stream profile exposure
- snapshot URI where available
- PTZ operations where hardware exists
- selected imaging controls where practical

## What can be lower priority

- implementing every optional ONVIF service
- exposing brand-new Thingino-only features through ONVIF immediately
- full event feature parity before the native hub works well

## Service boundary

The ONVIF daemon should not own business logic that the camera agent already
owns. It should translate and validate requests, then call the canonical layer.

## Benefits of this approach

- one source of truth for capabilities and config
- simpler testing
- fewer divergent code paths
- easier long-term maintenance

## Exit criteria for migration

- discovery still works for standard ONVIF tooling
- native hub does not depend on ONVIF for normal operation
- the CGI path can be removed without losing required interoperability