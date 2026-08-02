# Thingino WebUI Plugin System

Architecture, implementation plan, and roadmap for a build-time plugin
system that lets optional packages contribute pages to the Thingino Web UI
without modifying core webui source files.

## 1. Current State

Two ad-hoc patterns exist today for wiring optional packages into the web UI.
Both work but neither is general-purpose.

### Pattern A — Marker injection (motors)

The core webui contains placeholder comments that a package's `.mk` file
replaces at build time with `$(SED)`:

- `navigation.js` contains `/* THINGINO_MOTORS_NAV_ITEMS */`
- `preview.html` contains `<!-- THINGINO_MOTORS_PREVIEW_SCRIPT -->`

`thingino-motors.mk` uses `$(SED)` to inject nav items and `<script>` tags,
then re-runs `apply_asset_tag.py` and `apply_cdn_fallback.py` so the injected
markup gets cache-busting tags and CDN fallbacks.

The runtime existence check (`motors: true/false` in `runtime-config.js`) is
done by `S48webui-config`, which probes `jct /etc/thingino.json get motors`.

**Limitations:**

- The marker comment is a single injection point.  Two plugins that want to
  inject into the same spot race; the last one to `sed` wins.
- The sed expression is fragile — a change to the marker format in
  `navigation.js` silently breaks one or more plugin packages.
- Adding a new injection point (e.g. a plugin that adds a Tools menu entry
  instead of a Settings entry) requires editing `navigation.js` to add a new
  marker, then updating every plugin's `.mk`.
- Plugin authors must know to re-apply asset tags and CDN fallbacks or the
  injected markup won't have cache-busting.  This is easy to forget.

### Pattern B — Conditional install in core webui (doorbell)

The doorbell web files (`config-doorbell.html`, `config-doorbell.js`,
`json-config-doorbell.cgi`, `json-chime-status.cgi`) live **inside** the
`thingino-webui` package directory, not in the `wyze-accessory` package.

`thingino-webui.mk` has a hardcoded block:

```make
if [ "$(BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL)" = "y" ]; then \
    $(INSTALL) ... config-doorbell.html ... \
    $(INSTALL) ... config-doorbell.js ... \
    ...
fi
```

At runtime, `navigation.js` reads `uiConfig.device.doorbell` (set by
`S48webui-config` checking for the presence of
`/var/www/x/json-chime-status.cgi`) to decide whether to show the nav item.

**Limitations:**

- The core `thingino-webui.mk` must know about every optional package and
  hardcode its install logic.  This doesn't scale.
- Plugin files live in the wrong package directory, making it unclear who
  owns them.
- Adding a new plugin means touching `thingino-webui.mk`, `navigation.js`,
  `S48webui-config`, and potentially `preview.html` — five files in three
  packages for one feature.

### Why formalize this

The motors and doorbell integrations prove that plugins are valuable.
The goal is to replace both patterns with a single convention that:

1. Lets a plugin package ship **all** its web files in its own directory.
2. Requires **zero changes** to core webui source files for a new plugin.
3. Assembles everything at build time so there's **no runtime scanning cost**.
4. Gives plugin authors a single, documented manifest format to target.

---

## 2. Plugin Architecture

### Overview

```
┌──────────────────────────────────────────────────┐
│  Plugin package (e.g. thingino-motors)            │
│                                                    │
│  files/                                            │
│  ├── motors.webui.json    ◄── plugin manifest      │
│  ├── www/                                          │
│  │   ├── config-motors.html                        │
│  │   ├── a/                                        │
│  │   │   ├── config-motors.js                      │
│  │   │   └── preview-motors.js                     │
│  │   └── x/                                        │
│  │       ├── json-motor.cgi                        │
│  │       └── ...                                   │
│  └── ...                                           │
│                                                    │
│  thingino-motors.mk installs files + manifest      │
│  DEPENDENCIES += thingino-webui (ordering)         │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│  Build-time assembly (thingino-webui finalize)     │
│                                                    │
│  scripts/assemble_plugins.py scans:                │
│    /var/www/a/plugins/*.webui.json                 │
│                                                    │
│  Produces:                                         │
│    /var/www/a/plugins.js   (merged plugin config)  │
│    Injects <script> tags into preview*.html        │
│    Injects <link> tags into all HTML pages         │
│    Re-applies asset tags & CDN fallbacks           │
└──────────────────┬───────────────────────────────┘
                   │
                   ▼
┌──────────────────────────────────────────────────┐
│  Runtime (camera)                                 │
│                                                    │
│  navigation.js reads plugins.js → builds nav      │
│  S48webui-config sets feature flags               │
│  All plugin JS/CGI already on disk (static)       │
│  Zero runtime scanning overhead                   │
└──────────────────────────────────────────────────┘
```

### Key design decisions

**Build-time, not runtime.** The assembly happens once during `make`, not at
every boot.  This keeps boot time unchanged and avoids adding directory-scanning
code to the camera.

**Manifest-driven, not marker-driven.** Plugins declare what they need (nav
items, scripts, styles, preview injection, feature flags) in a JSON file.
The assembly script merges all manifests into a single configuration blob.
No more sed injection races.

**Each plugin owns its files.** Web files live in the plugin's package
directory (`package/thingino-motors/files/www/`), not in
`package/thingino-webui/files/www/`.  This is the single most important
architectural rule.

**Core webui is a platform.** `thingino-webui` provides the shell (navigation,
footer, control bar, preview page, theme) and the assembly tooling.  Plugins
provide content that slots into named extension points.

---

## 3. Plugin Manifest Specification

Each plugin package ships a single JSON manifest file.  By convention it is
named `<plugin-name>.webui.json` and installed to
`$(TARGET_DIR)/var/www/a/plugins/`.

### 3.1 Manifest schema

```jsonc
{
  // "$schema": "https://thingino.com/schemas/webui-plugin-v1.json",

  // Required.  Unique plugin identifier.  Must match the manifest filename
  // (e.g. "motors" for motors.webui.json).  Used for ordering and conflict
  // detection.
  "name": "motors",

  // Optional.  Human-readable label for debugging/logging.
  "label": "Pan/Tilt Motors",

  // Optional.  Minimum webui plugin-API version required.
  // The assembly script reports a warning if the core is older.
  "apiVersion": 1,

  // ── Navigation ──────────────────────────────────────────────────
  // Array of nav contributions.  Each entry targets a named section
  // in the navigation bar and declares a position.
  "nav": [
    {
      // Named section to insert into.  Standard sections:
      //   "ddSettings"   — Settings dropdown
      //   "ddTools"      — Tools dropdown
      //   "ddServices"   — Services dropdown
      //   "ddStreamer"   — Streamer dropdown
      //   "ddInfo"       — Information dropdown
      //   "ddHelp"       — Help dropdown
      //   "top"          — Top-level nav links (before dropdowns)
      "section": "ddSettings",

      // Where in the section to insert.
      //   "append"              — at the end (default)
      //   "prepend"             — at the beginning
      //   "after:<label>"       — after the item with this label
      //   "before:<label>"      — before the item with this label
      //   "index:<n>"           — at 0-based position <n>
      "position": "after:GPIO pins",

      // Nav item(s) to insert.  Multiple items can share the same
      // position; they are inserted in the order listed.
      "items": [
        {
          "label": "Pan/Tilt motors",
          "href": "/config-motors.html",
          // Optional.  Additional CSS class.
          "className": null,
          // Optional.  Hide the item (still in DOM).  Default false.
          "hidden": false
        }
      ]
    }
  ],

  // ── Scripts ─────────────────────────────────────────────────────
  // JS files to load on every page.  Injected into <head> of all HTML
  // pages after core scripts (runtime-config.js, navigation.js, etc.).
  // Paths are relative to /var/www/ (e.g. "/a/config-motors.js").
  "scripts": [
    "/a/config-motors.js"
  ],

  // ── Stylesheets ──────────────────────────────────────────────────
  // CSS files to load on every page.  Injected into <head> of all HTML
  // pages.  Rarely needed since most styling uses Bootstrap utilities;
  // prefer inline styles or a minimal embedded <style> in the plugin's
  // HTML page unless there's a real reuse case.
  "styles": [],

  // ── Preview-page injection ──────────────────────────────────────
  // Scripts to load only on the preview page.  Injected just before
  // </body> on /preview.html (and /preview-raptor.html if applicable).
  "preview": {
    "scripts": [
      "/a/preview-motors.js"
    ],
    // Optional.  HTML snippet injected into the preview page body
    // (e.g. motor-control overlay <div>).  If absent, nothing is
    // injected beyond the scripts above.
    "html": null
  },

  // ── Feature flags ────────────────────────────────────────────────
  // Key-value pairs merged into thinginoUIConfig.device at build time.
  // These are available to all JS as uiConfig.device.<key>.
  // The build-time value is the default; S48webui-config can override
  // at runtime (e.g. by probing for installed CGIs or config keys).
  "featureFlags": {
    "motors": true
  },

  // ── CGI endpoints ────────────────────────────────────────────────
  // Declarative list of CGI scripts this plugin installs.
  // Purely for documentation/introspection; the web server doesn't
  // need this.  Used by the assembly script to detect conflicts
  // (two plugins claiming the same CGI path).
  "cgi": [
    "/x/json-motor.cgi",
    "/x/json-motor-params.cgi",
    "/x/json-motor-stream.cgi",
    "/x/json-motors-config.cgi"
  ],

  // ── Pages ────────────────────────────────────────────────────────
  // HTML pages this plugin installs.  Used by the assembly script to
  // re-apply asset tags and CDN fallbacks specifically to these pages,
  // and to detect conflicts.
  "pages": [
    "/config-motors.html"
  ]
}
```

### 3.2 Standard nav sections

| Section ID    | Nav bar entry   | Default items include…                     |
|---------------|-----------------|---------------------------------------------|
| `ddInfo`      | Information     | File/log viewers, system usage, diagnostics |
| `ddSettings`  | Settings        | Admin, GPIO, Network, RTSP, Time, etc.      |
| `ddTools`     | Tools           | File manager, ping/trace, SD card, send2    |
| `ddServices`  | Services        | Timelapse, video recorder, MQTT, HA         |
| `ddStreamer`  | Streamer        | Image quality, main/sub stream, OSD, sensor |
| `ddHelp`      | Help            | About, Wiki, Logout                         |

`"top"` is a virtual section that inserts items as top-level nav links
(before any dropdown).  Use sparingly.

### 3.3 Position values

| Value              | Behavior                                        |
|--------------------|-------------------------------------------------|
| `"append"`         | Add after all existing items (default)          |
| `"prepend"`        | Add before all existing items                   |
| `"after:<label>"`  | Add immediately after the item with this label  |
| `"before:<label>"` | Add immediately before the item with this label |
| `"index:<n>"`      | Insert at 0-based position                      |

Label-based positions are resolved against the merged (core + preceding
plugins) item list at assembly time.  If the label isn't found, the item is
appended with a warning.

### 3.4 Conflict detection

The assembly script checks for:

- Two manifests with the same `"name"` → **error**, build fails.
- Two plugins claiming the same `"pages"` path → **error**, build fails.
- Two plugins claiming the same `"cgi"` path → **warning** (CGIs are just
  files on disk; the later install wins, but this is probably a mistake).
- `"after:"` / `"before:"` label not found → **warning**, item appended.

Warnings are printed to the build log but don't fail the build.  Errors
fail the build.

---

## 4. Build-Time Assembly

### 4.1 The assembly script

`package/thingino-webui/scripts/assemble_plugins.py` runs as the **last
step** in the webui install sequence (via a `TARGET_FINALIZE_HOOKS` hook
registered by `thingino-webui.mk`).  It does the following in order:

1. **Discover** — scans `$(TARGET_DIR)/var/www/a/plugins/*.webui.json`
   and parses each manifest.
2. **Validate** — checks for duplicate plugin names, page conflicts, etc.
3. **Merge nav** — builds a single, ordered nav configuration by applying
   each plugin's `nav` contributions to the core menu structure.  Plugin
   order is determined by:
   - Explicit `"order"` field in the manifest (if added to the schema)
   - Otherwise, alphabetical by plugin `"name"`
   - `"prepend"` and `"after:…"` positions are resolved in plugin order
4. **Emit `plugins.js`** — writes a static JS file that sets
   `window.thinginoUIConfig.plugins`.  This is loaded by `navigation.js`.
5. **Inject preview scripts** — for each plugin with a non-empty
   `preview.scripts`, appends `<script src="…">` tags before `</body>`
   in `preview.html` and `preview-raptor.html`.
6. **Inject global scripts & styles** — for each plugin's `scripts` and
   `styles`, appends `<script>`/`<link>` tags before `</head>` in every
   HTML page under `/var/www/`.
7. **Re-apply asset tags** — runs `apply_asset_tag.py` with a tag that
   covers plugin files too.
8. **Re-apply CDN fallbacks** — runs `apply_cdn_fallback.py` so plugin
   pages get onerror fallbacks for CDN resources.

### 4.2 Dependency ordering

Plugin packages that ship webui files **must** declare:

```make
THINGINO_MOTORS_DEPENDENCIES += thingino-webui
```

This guarantees that when the plugin's `INSTALL_TARGET_CMDS` runs,
`thingino-webui` has already installed the core webui files and registered
its finalize hook.  The finalize hook then runs after all packages are
installed and discovers the plugin manifests.

Buildroot's `TARGET_FINALIZE_HOOKS` is the mechanism — it runs after every
package's `INSTALL_TARGET_CMDS` has completed, which is exactly when all
`*.webui.json` manifests are in place.

### 4.3 What `navigation.js` needs to change

Today, `navigation.js` builds the menu in `buildDefaultMenu()` as a
hardcoded array.  It already supports loading a fully custom menu from
`window.thinginoUIConfig.nav.items` (the `globalConfig` path).

The change: after `buildDefaultMenu()` returns the default array, apply
the plugin nav contributions from `window.thinginoUIConfig.plugins` on
top — inserting, appending, and prepending items according to each
plugin's declared positions.

Pseudocode for the new logic:

```js
function buildMenu() {
  let items = buildDefaultMenu();       // core hardcoded items
  const plugins = uiConfig.plugins || {};
  for (const [name, plugin] of Object.entries(plugins)) {
    if (!plugin.nav) continue;
    for (const contribution of plugin.nav) {
      items = applyNavContribution(items, contribution);
    }
  }
  return items;
}
```

`applyNavContribution` finds the target section, resolves the position,
and splices the new items.  This is the only runtime overhead — a single
loop over plugins (typically 0–5 entries) at page load.

---

## 5. Implementation Plan

### Phase 1 — Core infrastructure (1–2 PRs)

**Goal:** The assembly pipeline exists and one plugin (motors) is fully
migrated to it.

Files to create:

| File | Purpose |
|------|---------|
| `package/thingino-webui/scripts/assemble_plugins.py` | Manifest scanner, validator, merger, HTML injector |
| `package/thingino-motors/files/motors.webui.json` | Manifest for the motors plugin (migrate from sed-based) |

Files to modify:

| File | Change |
|------|--------|
| `package/thingino-webui/thingino-webui.mk` | Add `THINGINO_WEBUI_FINALIZE_HOOKS` that calls `assemble_plugins.py`; register it via `TARGET_FINALIZE_HOOKS`. Remove the doorbell conditional install block (moved to Phase 2). |
| `package/thingino-webui/files/www/a/navigation.js` | Add `applyPluginNav()` logic. Remove `/* THINGINO_MOTORS_NAV_ITEMS */` marker. Remove doorbell-specific nav item (moved to manifest). |
| `package/thingino-webui/files/www/preview.html` | Remove `<!-- THINGINO_MOTORS_PREVIEW_SCRIPT -->` marker. Remove inline motor overlay HTML (moved to manifest). |
| `package/thingino-webui/files/www/preview-raptor.html` | Same as preview.html. |
| `package/thingino-webui/files/S48webui-config` | Remove per-plugin probing for motors/doorbell. Feature flags come from the merged manifest; S48webui-config just reads the assembled config. |
| `package/thingino-motors/thingino-motors.mk` | Remove `$(SED)` injection, remove manual re-apply of asset tags/CDN fallbacks. Add `$(INSTALL)` of `motors.webui.json`. Keep `DEPENDENCIES += thingino-webui`. |

### Phase 2 — Migrate doorbell to manifest system (1 PR)

**Goal:** Doorbell plugin uses the manifest system; core webui has zero
knowledge of doorbell.

Files to create:

| File | Purpose |
|------|---------|
| `package/wyze-accessory/files/doorbell.webui.json` | Manifest for doorbell plugin |

Files to modify:

| File | Change |
|------|--------|
| `package/thingino-webui/thingino-webui.mk` | Remove `BR2_PACKAGE_WYZE_ACCESSORY_DOORBELL_CTRL` install block entirely. |
| `package/wyze-accessory/wyze-accessory.mk` | Add install steps for doorbell HTML/JS/CGI files + manifest. Add `DEPENDENCIES += thingino-webui`. |
| `package/thingino-webui/files/www/a/navigation.js` | Remove doorbell-specific logic from `buildDefaultMenu()`. |
| `package/thingino-webui/files/www/config-doorbell.html` | **Move** to `package/wyze-accessory/files/www/config-doorbell.html`. |
| `package/thingino-webui/files/www/a/config-doorbell.js` | **Move** to `package/wyze-accessory/files/www/a/config-doorbell.js`. |
| `package/thingino-webui/files/www/x/json-config-doorbell.cgi` | **Move** to `package/wyze-accessory/files/www/x/json-config-doorbell.cgi`. |
| `package/thingino-webui/files/www/x/json-chime-status.cgi` | **Move** to `package/wyze-accessory/files/www/x/json-chime-status.cgi`. |

### Phase 3 — Developer tooling & docs (1 PR)

**Goal:** Plugin authors can validate manifests locally and get useful
error messages.

- `make check-plugins` target that runs the assembly script in
  validation-only mode (no file writes) and reports all warnings/errors.
- Shell-level validation in `scripts/assemble_plugins.py`: JSON schema
  check, path existence check (does the declared script actually exist on
  disk?), cross-plugin conflict report.
- Update `AGENTS.md` with a section on creating webui plugins.

### Phase 4 — Hardening & edge cases

- **User overlays:** A user's `user/<camera>/overlay/var/www/a/plugins/`
  should be able to override or mask a plugin manifest.  The assembly
  script processes overlays last so user files win.
- **Plugin disabling:** A user setting `BR2_PACKAGE_FOO=n` naturally
  prevents the manifest from being installed.  For finer control, a
  `disabled.webui.json` naming convention lets users rename manifests to
  skip them without deleting the package.
- **Backward compatibility:** The assembly script detects old-style
  marker comments (`/* THINGINO_*_NAV_ITEMS */`) in `navigation.js` and
  emits a warning urging migration.

---

## 6. Roadmap

### Milestone 1 — Assembly pipeline working (target: next release cycle)

- [ ] `assemble_plugins.py` script written and tested locally.
- [ ] `thingino-webui.mk` registers the finalize hook.
- [ ] `navigation.js` gains `applyPluginNav()` logic.
- [ ] `motors.webui.json` created; motors .mk updated.
- [ ] Motors plugin builds and renders correctly — parity with current
  injected nav + preview controls.
- [ ] Old marker comments and sed logic removed from motors .mk and
  webui source files.
- [ ] Build tested on at least one camera with motors and one without.

### Milestone 2 — Doorbell migration (target: same or next cycle)

- [ ] Doorbell files moved from `thingino-webui` to `wyze-accessory`.
- [ ] `doorbell.webui.json` created.
- [ ] Core webui install block for doorbell removed.
- [ ] Build tested on a camera with doorbell accessory.

### Milestone 3 — Documentation & validation (target: next cycle)

- [ ] `make check-plugins` target.
- [ ] Manifest schema documented in this file.
- [ ] `AGENTS.md` updated with plugin authoring section.
- [ ] Example "hello world" plugin in the repo (could be a minimal
  package that just adds a Tools menu entry pointing to an info page).

### Milestone 4 — New plugins onboarded

Candidates that could benefit from the plugin system:

- **thingino-sounds** — manage custom sound files for doorbell/alarm.
- **go2rtc / go2rtc-mini** — WebRTC preview page, config.
- **nino** — inference results viewer.
- **lightnvr** — NVR configuration panel.
- **compy** — compile-on-device tool UI.
- **magik-models** — model management and status.

Each of these currently has either no web UI or would need to
manually wire into the core — with the plugin system they'd just ship
a manifest.

---

## 7. Appendix: Plugin Authoring Quickstart

### Minimal plugin checklist

1. Create your package normally in `package/<name>/`.
2. In your package's `.mk`, add:
   ```make
   MYPLUGIN_DEPENDENCIES += thingino-webui
   ```
3. Create `files/<name>.webui.json` following the schema in §3.
4. In your install commands, copy the manifest:
   ```make
   $(INSTALL) -D -m 0644 $(MYPLUGIN_PKGDIR)/files/<name>.webui.json \
       $(TARGET_DIR)/var/www/a/plugins/<name>.webui.json
   ```
5. Install your web files (HTML, JS, CGI) into the standard directories:
   ```
   $(TARGET_DIR)/var/www/<page>.html
   $(TARGET_DIR)/var/www/a/<script>.js
   $(TARGET_DIR)/var/www/x/<endpoint>.cgi
   ```
6. Build and verify — the assembly script handles the rest.

### Testing a manifest locally

```bash
# Validate without building the full firmware
python3 package/thingino-webui/scripts/assemble_plugins.py \
    --check-only --www-root /path/to/staging/var/www
```

---

*Last updated: 2026-01-28*
