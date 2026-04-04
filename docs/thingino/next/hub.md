# Desktop Hub Service

Status: Proposed

Implementation progress: In progress

## Purpose

The desktop hub is the primary monitoring and configuration surface for Thingino
cameras. It owns multi-camera UX, discovery, fleet state, and richer workflows
that are awkward or wasteful to host on each camera.

## Current baseline

There is already an existing PC-side hub in `/home/paul/thingino/hub`.

Current characteristics:

- Python application with a small server-rendered web UI
- Telegram-to-MQTT bridge as the original core use case
- camera roster, camera detail, and config pages
- ONVIF device detail fetches for identity metadata
- snapshot preview caching and camera registration state
- native camera-agent client support with `/api/v1` defaults
- self-signed HTTPS camera-agent support for remote TLS endpoints
- database-backed action and coarse state history views
- camera detail quick controls for native motion, privacy, day/night, image, stream, and send2 settings

Recent implementation progress:

- camera detail pages now render from cached supported-controls data instead of blocking on live native capability or config reads
- quick controls now use narrow responses instead of full camera payloads where possible
- manual refresh actions now queue work and acknowledge immediately instead of blocking the page
- feedback for quick actions now floats above the page instead of shifting layout

This matters because the new architecture does not start from zero. The current
hub should be treated as the first desktop control plane component and expanded
toward the canonical camera API rather than discarded.

## Responsibilities

- discover and enroll cameras
- maintain authenticated sessions to many cameras
- present a fleet view and per-camera detail view
- aggregate health, alerts, and events
- handle bulk changes across multiple cameras
- proxy or coordinate media views where useful
- store user preferences and hub-local metadata

## Non-responsibilities

- becoming the only way to use a camera
- hiding camera capabilities behind a fake lowest common denominator
- replacing standards-based NVR clients where they already work well

## Why the hub exists

The camera is resource-constrained. The desktop is not.

The hub is where it makes sense to place:

- fleet dashboards
- multi-camera layouts
- search and filtering
- historical event review
- diff and audit views
- guided setup flows
- richer charts and diagnostics

As the hub matures, this should include a local historical store for trend and
timeline analysis. That store belongs in the hub because it is expensive in
storage terms and does not help the camera do its primary job.

That history store is no longer hypothetical; a first SQLite-backed action and
coarse-state history layer already exists and should continue to grow only as a
downstream analytics path.

## Camera relationship model

The hub should treat each camera as an independently versioned device exposing a
common Thingino API.

Important rule: the hub must consume capabilities, not assumptions.

## Recommended hub features for phase one

- camera discovery and manual add
- live status board for many cameras
- per-camera config editor driven by capabilities
- snapshot and short clip actions
- event feed
- firmware version visibility
- bulk operations for safe common settings

Current near-term priorities:

- refresh stale cached camera-detail data automatically when a detail page opens
- keep quick-control and refresh responses narrow and fast
- add lightweight regression coverage for response shape and non-blocking behavior
- reduce remaining dependency on slow or broad reads such as send2 overview fetches when they become the next bottleneck

For the existing hub, phase-one evolution should focus on adding Thingino API
client capabilities next to the current MQTT and ONVIF logic.

## Data owned by the hub

The hub can store data that does not belong on a camera, such as:

- tags and groups
- room names
- dashboards and layouts
- per-user favorites
- alert routing rules
- cached event history
- database-backed action and state history for analysis
- local trust store for paired cameras

## Data not owned by the hub

The hub should not silently become the source of truth for device configuration.
The camera still owns camera configuration and runtime state.

If the hub caches camera state, it must be clear that cached state can go stale.

The same rule applies to a historical database. It may retain observations,
diffs, and action logs for later analysis, but it must not become the authority
that live control paths read from before talking to a camera.

## Discovery

Expected discovery sources:

- manual host entry
- mDNS if introduced later
- ONVIF discovery for compatibility scenarios
- import from MQTT or inventory files if useful later

The first working version does not need every discovery mode.

## Failure model

The hub must handle cameras being offline, partially reachable, or outdated.

The UI should make these cases explicit:

- reachable and healthy
- reachable with degraded features
- authentication failed
- offline
- incompatible API version

## Upgrade tolerance

The hub and camera will not always update together. The API must tolerate small
version skew.

Recommended safeguards:

- explicit API versioning
- capability negotiation
- conservative fallback behavior
- clear errors for unsupported requests

## User experience priorities

- fast fleet visibility
- low-friction per-camera troubleshooting
- simple bulk changes with preview
- clear distinction between live state and saved config
- no requirement to open the camera-hosted UI for normal operations

## Deferred ideas

- cloud relay
- managed remote access service
- hub-side transcoding by default

The historical analytics store is no longer considered speculative. It is a
planned hub responsibility, but it should be implemented as a downstream write
path after the native API and hub flows are stable enough to generate useful
data.

These remaining ideas may become useful, but they should not distort the first
architecture.

## Historical storage direction

The hub should eventually keep deeper history in a local database so operators
can graph and analyze camera behavior over time.

Recommended constraints:

- treat the database as append-only or mostly append-only history
- keep live control paths independent from database availability
- store normalized time-series fields for common graphs instead of only raw JSON
- retain action events and config diffs longer than high-rate status samples
- start with SQLite because the hub is currently a single desktop service

The first version should focus on:

- action history: restart, privacy, clip recording, config patch, pairing, upgrade
- state samples: online status, streamer running, privacy, motion, day/night mode
- config change records: which fields changed and when
- capability snapshots: baseline comparison across firmware or streamer changes

This is described in more detail in [history-analytics.md](history-analytics.md).

## Immediate integration direction

The existing hub should gain a small client layer for the canonical camera API.

Recommended order:

- keep current MQTT registration and Telegram routing working
- add camera-agent discovery and capability fetch
- prefer camera-agent state and config over ad hoc camera metadata
- keep ONVIF only for compatibility and identity details until native API
	equivalents exist
- move snapshot fetches to the canonical API when available

This lets the hub remain useful while the camera-side service is being built.

In practice this integration has already started and is now the active development phase.
The next phase for development is still Phase 2: complete the hub as the normal
management surface before expanding Phase 2a beyond its current lightweight
history foundation.