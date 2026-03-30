# ONVIF Migration Plan

Status: Proposed

## Purpose

This document turns the ONVIF architecture direction into a concrete migration
task list for the current firmware tree.

## Current state in this repo

The ONVIF package currently installs:

- CGI-backed main service under `/var/www/onvif/onvif.cgi`
- discovery daemon
- notify daemon
- generated service files and static resources

The goal is to retire CGI as the primary ONVIF execution model without losing
required interoperability.

## Migration rule

Do not build a second independent source of truth.

The daemonized ONVIF service should translate requests into canonical camera-
agent operations wherever possible.

## Phase 1: Inventory and boundary cleanup

Tasks:

1. list which ONVIF operations are required for current interoperability goals
2. identify which operations currently read config directly versus compute from runtime state
3. identify which operations can be backed by the future camera-agent model
4. separate static resource installation from service execution concerns

Exit criteria:

- we know which ONVIF surface is required
- we know which parts are compatibility-only and which are accidental legacy

## Phase 2: Define ONVIF-to-agent mapping

Tasks:

1. map device identity responses to `GET /device`
2. map capability-related responses to `GET /capabilities`
3. map imaging controls to canonical config writes where practical
4. map snapshot URI generation to the native snapshot action or URL model
5. map PTZ operations to canonical PTZ actions when motors exist

Exit criteria:

- each required ONVIF operation has a clear canonical backing source

## Phase 3: Introduce daemon execution path

Tasks:

1. add an ONVIF daemon entrypoint separate from CGI
2. keep discovery and notify daemons working
3. expose the main service through the daemon instead of process-per-request CGI
4. ensure packaging and init flow remain simple

Exit criteria:

- ONVIF requests are served without CGI spawning

## Phase 4: Reduce direct legacy dependencies

Tasks:

1. stop reading private backend internals directly where the canonical API exists
2. unify auth and authorization handling with the camera-agent security model
3. move snapshot and identity behavior onto canonical sources where available

Exit criteria:

- ONVIF compatibility no longer depends on its own private state model

## Phase 5: Remove CGI path

Tasks:

1. remove CGI installation path from package layout
2. remove special web server routing that only exists for ONVIF CGI
3. confirm discovery, identity, media profile, snapshot, and PTZ compatibility still work

Exit criteria:

- required interoperability survives
- CGI-specific plumbing is gone

## Risks to watch

- trying to preserve too much optional ONVIF surface too early
- leaking canonical API details directly into ONVIF semantics
- keeping duplicate auth rules between ONVIF and native API

## Review questions

1. Which ONVIF clients do we actually need to keep working?
2. Which ONVIF operations buy real value versus legacy completeness?
3. Are we translating from the canonical model, or re-implementing business logic again?