# Security Model

Status: Proposed

## Purpose

This document sets the default security posture for remote camera control in the
new architecture.

## Goals

- secure remote control over the network
- minimal camera footprint
- clear authentication and authorization model
- no unauthenticated reuse of local helper endpoints

## Threat model

The main concerns are:

- unauthorized access from the local network
- credential reuse across many cameras
- protocol sprawl with inconsistent auth rules
- accidental exposure of local-only control surfaces

## Recommended defaults

### Local-only by default

The camera agent should default to local access only.

Remote access should require explicit enablement through pairing or enrollment.

### TLS for remote access

Use HTTPS for remote control. Plain HTTP should not be the normal remote path.

### Strong camera-to-hub trust

Preferred first choice:

- mutual TLS between hub and camera

Fallback if implementation cost is too high initially:

- TLS plus short-lived signed bearer tokens issued during pairing

### Scoped permissions

Permissions should be capability-based rather than all-or-nothing.

Candidate scopes:

- `read`
- `control`
- `admin`
- `firmware`
- `media`

## Pairing model

Pairing should create explicit trust between one hub and one camera.

The pairing flow should:

- require local authorization or a physical trust assumption
- issue device and hub credentials
- allow credential rotation
- support revocation

## Credential separation

Do not force all protocols to share one credential.

Recommended separation:

- control credentials for the camera agent
- media credentials for RTSP or WebRTC where needed
- compatibility credentials for ONVIF if required

These may map to the same user in a small first version, but the design should
not depend on that forever.

## Auditability

The system should log at least:

- successful and failed authentication attempts
- config writes
- privileged actions such as reboot or firmware install
- pairing and revocation events

Detailed long-term retention can remain a hub concern.

## Security decisions explicitly rejected for now

- exposing local helper scripts directly on the network
- making ONVIF auth the master auth model for Thingino-native clients
- making MQTT broker auth the only control authorization mechanism

## Exit criteria for first usable version

- remote control is encrypted
- unauthenticated writes are not possible
- credentials can be rotated
- disabling the optional web UI does not remove secure remote management