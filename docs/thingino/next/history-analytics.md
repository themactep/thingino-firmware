# Hub History And Analytics

Status: Proposed

Implementation progress: In progress

## Purpose

This document describes how the desktop hub should retain deeper operational
history so operators can graph, compare, and analyze camera behavior over time.

The goal is not just to keep logs. The goal is to make long-term behavior
visible without turning the history store into part of the live control plane.

## Design rule

The history database is downstream from live control.

That means:

- the camera remains the source of truth for state and configuration
- the hub issues live reads and writes directly against the camera API
- the hub records observations and action results after the fact
- the database may be unavailable without preventing normal camera control

This avoids creating a second source of truth and keeps analytics from making
basic operation fragile.

## Why keep deeper history

Short-lived in-memory status is enough for immediate operator feedback, but it
is not enough for:

- trend graphs
- uptime and instability analysis
- config drift review
- before-and-after change correlation
- comparing behavior across firmware or streamer backends
- answering "what changed before this camera started failing"

## Recommended first storage choice

Start with SQLite.

Reasons:

- the hub is currently a single desktop service
- write rates are modest
- deployment and backup stay simple
- WAL mode is good enough for concurrent read-heavy UI access

PostgreSQL or TimescaleDB can come later if the hub becomes multi-user,
multi-process, or high-ingest enough to justify the added complexity.

## What to store

### Action events

One record per user-visible action or important background operation.

Examples:

- restart streamer
- snapshot request
- clip recording request
- privacy change
- config patch
- pairing and unpairing
- upgrade request

Recommended fields:

- timestamp
- camera id
- actor or source
- action name
- status: success or error
- short detail string
- summarized payload or target fields

### State samples

Periodic observations suitable for graphing.

Examples:

- camera reachable or not
- API reachable or not
- streamer running
- motion enabled
- privacy enabled
- day/night running mode
- IP address changes

Prefer normalized columns for common values instead of storing only raw JSON.

### Config change records

History of what changed, not only that something changed.

Good first options:

- one row per changed config path
- or one event row containing a JSON diff summary

Important fields:

- timestamp
- camera id
- changed path or paths
- previous value when available
- new value when available
- actor or source

### Capability snapshots

Occasional snapshots of capabilities and baseline config are useful for:

- comparing firmware revisions
- comparing streamer adapters
- understanding why a feature disappeared or changed shape

These should be stored less frequently than state samples.

## Suggested schema shape

The exact SQL is an implementation detail, but the model should likely include:

- `cameras`: stable hub-side camera metadata
- `action_events`: operator and system actions
- `state_samples`: graphable time-series observations
- `config_changes`: normalized config diff history
- `capability_snapshots`: infrequent baseline snapshots

## Retention strategy

Do not keep raw high-frequency samples forever.

Recommended approach:

- keep high-resolution recent samples for a short window
- keep longer-lived coarse rollups for trend views
- keep action and config-change history longer than periodic status samples

This keeps storage growth predictable and makes SQLite viable for longer.

## Integration with the existing hub

The current hub in `/home/paul/thingino/hub` should add a small history writer
component rather than mixing direct SQL into every route handler.

Recommended flow:

1. hub service performs live camera action or probe
2. hub updates immediate in-memory/UI-facing state
3. hub enqueues a history record
4. background writer flushes queued records to SQLite

This lets analytics evolve in parallel with native API work.

Current implementation status:

- SQLite-backed history storage already exists in the current hub
- native action history is already recorded and shown in camera detail and history views
- coarse probe and state samples already exist for first-pass operational diagnosis
- dashboard live events now also feed from history-backed action records plus native camera-agent event subscriptions
- config-change history rows now exist for native config patches, send2 writes, hub override saves, and enrollment updates, and they are surfaced in the camera history timeline
- graph views and broader normalized sampling are not implemented yet

## What should not happen

Avoid these failure modes:

- reading desired device state from history before talking to a camera
- using the database as the authority for live configuration
- blocking control actions on synchronous history writes
- storing only opaque JSON when normalized graphable fields are known

## Near-term implementation order

Recommended order once implementation starts:

1. expand normalized sampling only for fields that directly help current hub operation and troubleshooting
2. add graph views for a small set of normalized fields once the sampled data is stable enough to be useful

The current next slice should likely focus on graph views and a slightly wider
set of normalized samples, because the hub now has enough action, probe, and
config-change history to make those views useful without inventing synthetic
data first.

## Relationship to the rest of the plan

This work should proceed alongside hub-native API adoption, not ahead of it.

The database becomes most valuable when:

- the native API surfaces enough consistent state to sample
- the hub is the normal management path
- operators already issue meaningful actions through the hub

At that point, the historical store turns the hub from a live control surface
into a useful analysis tool as well.

The next development phase is not a history-first phase. Phase 2a should remain
parallel and subordinate to Phase 2 until the hub's live camera-management path
is complete and stable.