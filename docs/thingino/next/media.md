# Media Service

Status: Proposed

## Purpose

This document defines how video, audio, snapshots, and short recordings should
move through the new architecture.

The main rule is simple: media transport is not the control plane.

## Recommendations

### Live video

Use RTSP as the default live media protocol.

Why:

- already standard for cameras and NVR tools
- efficient for direct client consumption
- avoids forcing the control API to carry video concerns
- already aligns with current Thingino use

### Browser-first or NAT-sensitive viewing

Use WebRTC only where it solves a real problem.

Typical reasons:

- browser playback without additional relay software
- lower-latency interactive viewing
- networks where RTSP is impractical

WebRTC should be optional. It should not become a mandatory dependency for every
camera if RTSP already serves the need.

### Snapshots

Snapshots should be action-oriented control requests that return either:

- image bytes directly
- a temporary URL
- a job handle when capture is asynchronous

The control API can initiate a snapshot, but snapshot delivery is still media.

### Short recordings

Short recordings should also be triggered as actions, not modeled as normal
configuration fields.

The API should allow the hub to request:

- stream selection
- duration
- output behavior, such as temporary file or persistent clip

## Service boundaries

The media service layer should answer:

- which live transports are available
- which streams exist
- which codecs and profiles are active
- whether snapshot and clip capture are supported

It should not redefine image tuning, auth policy, or general configuration.

## Capability examples

- `rtsp: true`
- `webrtc: false`
- `audio.tx: true`
- `audio.rx: false`
- `snapshot: true`
- `clip_recording: true`

## Hub expectations

The hub should not assume all cameras support identical media behavior.

Important examples:

- some cameras may expose multiple streams
- some may support audio return paths and some may not
- some may have WebRTC support and some may not
- some may support only one snapshot source

## Deferred concerns

- hub-side recording as a built-in responsibility
- media transcoding inside the camera agent
- forcing a single media protocol across all use cases

## Exit criteria for phase one

- hub can discover live stream URLs and metadata
- hub can request a snapshot
- hub can request a short clip where supported
- hub can display unsupported media features clearly