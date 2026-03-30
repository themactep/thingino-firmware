# Camera Agent Implementation Plan

Status: Proposed

## Purpose

This document turns the camera-agent architecture into a first implementation
plan that fits the current Thingino firmware tree.

## First implementation target

Target only prudynt-backed cameras first.

Reason:

- existing local control primitives already exist
- we can validate the API model before solving every backend
- it keeps the first package small and useful

## Packaging strategy

Introduce a new package:

```text
package/thingino-agent/
```

Expected contents:

- `Config.in`
- `thingino-agent.mk`
- daemon source or bundled artifact
- init script
- optional config file template

## Runtime shape

The first version should run as a small daemon with two listener modes:

- local-only listener by default
- optional remote HTTPS listener when explicitly enabled

Prefer one daemon over adding more CGI or shell wrappers.

## Recommended first features

### Reads

- device identity
- capabilities
- runtime state
- persisted config

### Writes

- image controls
- motion enable or disable
- privacy enable or disable
- day or night force mode
- stream bitrate changes

### Actions

- snapshot
- short clip
- streamer restart
- reboot

### Events

- SSE stream with a small set of state changes

## Local integration plan

### Persisted config

Use existing `jct` interactions initially instead of inventing a new storage
layer.

### Runtime updates

Use existing local interfaces initially:

- `prudyntctl json -`
- `prudyntctl snapshot`
- `/run/prudynt/mp4ctl`
- `/run/prudynt/video_ctrl`
- `/etc/init.d/S31prudynt`

### State gathering

Gather state from:

- config files for persisted intent
- runtime files under `/run/prudynt`
- process checks and init status
- network information already available in system helpers

## Implementation language

The design intentionally does not force a language, but the selection criteria
for the first implementation are:

- small runtime footprint
- straightforward HTTPS and SSE support
- easy JSON handling
- simple process and file integration

Whatever is chosen, the daemon should remain thin and avoid pulling in a large
web framework.

## Buildroot integration

The first package should:

- be selectable independently of the optional camera web UI
- depend only on the minimum TLS and HTTP stack it needs
- not force ONVIF or MQTT packages to be installed

Candidate integration tasks:

1. add `package/thingino-agent/Config.in`
2. add package include under the relevant menu
3. install daemon binary or script
4. install init script and default config
5. add any required TLS helper dependencies

## Suggested init behavior

- start after network basics and local streamer controls are available
- do not fail hard when the streamer is down; surface degraded state instead
- allow the local-only control surface to start before remote exposure is enabled

## Risks

- too much shelling out can make the daemon slow or fragile
- too much backend-specific logic in v1 can freeze the wrong model
- remote exposure before auth is solid creates avoidable risk

## Acceptance checklist for the first package

- package builds cleanly in the existing tree
- daemon starts on prudynt-backed cameras
- hub can read capabilities and state
- hub can write a small config subset successfully
- snapshot and clip actions work
- optional camera web UI is not required