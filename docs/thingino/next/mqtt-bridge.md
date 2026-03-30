# MQTT Bridge Service

Status: Proposed

## Purpose

MQTT should remain an integration bus for automation systems such as Home
Assistant. It should not become the canonical camera control plane.

## Why keep it

- it already fits HA and other automation tools well
- it works well for command and state fan-out
- it is useful for event publishing and simple actions

## Why not make it primary

- request and response semantics are awkward for rich configuration workflows
- authentication and authorization are delegated to the broker model
- schema evolution is harder to manage than a versioned API
- debugging complex write flows is harder than plain HTTPS JSON

## Target role

MQTT should bridge selected capabilities from the canonical camera model:

- availability state
- motion and event notifications
- simple command topics
- selected configuration entities that map cleanly to MQTT semantics

## Architecture

The bridge should be downstream of the camera agent.

Preferred flow:

```text
camera internals -> camera agent -> MQTT bridge -> broker -> automation clients
```

and:

```text
automation command -> broker -> MQTT bridge -> camera agent -> local adapter
```

This prevents MQTT-specific code from becoming a second source of truth.

## Good MQTT use cases

- availability
- motion events
- privacy toggle
- snapshot trigger
- reboot trigger
- selected numeric controls with stable mapping

## Weak MQTT use cases

- large structured configuration edits
- complex validation flows
- long-running action progress reporting
- full fleet management from the desktop hub

## Design rule

If a feature cannot be represented clearly in MQTT, keep it native to the camera
agent and expose only a smaller automation-friendly subset over MQTT.

## Exit criteria for phase one

- existing HA-style integrations still work
- MQTT topics derive from the same canonical state model as the native API
- disabling MQTT does not break the native hub