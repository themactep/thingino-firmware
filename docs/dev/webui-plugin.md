# Creating a WebUI Plugin

How to add configuration pages, navigation items, and scripts to the
Thingino Web UI from an optional package — without touching core webui
source.

See `plugin-system.md` for the full architecture.

## Quickstart

```
package/<name>/files/
├── <name>.webui.json       ← manifest (the only new file you need)
└── www/
    ├── config-<name>.html  ← your page
    ├── a/
    │   └── config-<name>.js
    └── x/
        └── json-<name>.cgi
```

Then in your `.mk`:

```make
ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
MYPLUGIN_DEPENDENCIES += thingino-webui
endif

define MYPLUGIN_INSTALL_TARGET_CMDS
    # ... your binary/service installs ...

ifeq ($(BR2_PACKAGE_THINGINO_WEBUI),y)
    $(INSTALL) -d $(TARGET_DIR)/var/www/a
    $(INSTALL) -d $(TARGET_DIR)/var/www/x
    $(INSTALL) -d $(TARGET_DIR)/var/www/a/plugins
    $(INSTALL) -D -m 0644 $(@D)/files/www/config-myplugin.html \
        $(TARGET_DIR)/var/www/config-myplugin.html
    $(INSTALL) -D -m 0644 $(@D)/files/www/a/config-myplugin.js \
        $(TARGET_DIR)/var/www/a/config-myplugin.js
    $(INSTALL) -D -m 0644 $(@D)/files/myplugin.webui.json \
        $(TARGET_DIR)/var/www/a/plugins/myplugin.webui.json
endif
endef
```

Validate with `scripts/check-plugins.sh` before building.

## Manifest reference

### Minimal manifest

```json
{
  "name": "myplugin",
  "nav": [{
    "section": "ddSettings",
    "position": "append",
    "items": [
      { "label": "My Plugin", "href": "/config-myplugin.html" }
    ]
  }],
  "pages": ["/config-myplugin.html"]
}
```

### All fields

| Field | Required | Purpose |
|-------|----------|---------|
| `name` | yes | Unique plugin ID (lowercase, hyphens/underscores) |
| `nav` | no | Menu items to inject into standard sections |
| `scripts` | no | JS files loaded on **every** page |
| `styles` | no | CSS files loaded on every page |
| `preview.scripts` | no | JS files loaded only on preview pages |
| `preview.html` | no | HTML snippet injected into preview page body |
| `featureFlags` | no | Key-value pairs merged into `thinginoUIConfig.device` |
| `pages` | no | HTML page paths (for conflict detection) |
| `cgi` | no | CGI endpoint paths (for conflict detection) |
| `router.pages` | no | Pages that may be swapped in place (see [In-place navigation](#in-place-navigation)) |

### Nav sections

| Section ID | Nav bar location |
|------------|-----------------|
| `ddSettings` | Settings dropdown |
| `ddTools` | Tools dropdown |
| `ddServices` | Services dropdown |
| `ddStreamer` | Streamer dropdown |
| `ddInfo` | Information dropdown |
| `ddHelp` | Help dropdown |

### Nav positions

| Value | Effect |
|-------|--------|
| `"append"` | End of section (default) |
| `"prepend"` | Beginning of section |
| `"after:GPIO pins"` | After item with matching label |
| `"before:Network"` | Before item with matching label |
| `"index:3"` | At 0-based position |

## Feature flags

Declared flags are merged into `window.thinginoUIConfig.device`:

```json
{ "featureFlags": { "myplugin": true } }
```

```js
// In your JS:
if (window.thinginoUIConfig.device.myplugin) { ... }
```

Flags are **build-time** (set when the package is built). For runtime
conditions, query a CGI endpoint from your page's JS instead.

## Global scripts

Scripts listed in `"scripts"` load on **every** page — keep them small
and focused. Ideal for notification banners, status checks, or polyfills.

```json
{ "scripts": ["/a/myplugin-banner.js"] }
```

Page-specific JS should be loaded directly by your HTML page with a
`<script>` tag, not listed here.

## Preview injection

Scripts and HTML injected into the preview page only:

```json
{
  "preview": {
    "scripts": ["/a/preview-myplugin.js"],
    "html": "<div id=\"myplugin-overlay\" style=\"display:none\">...</div>"
  }
}
```

The HTML snippet replaces `<!-- THINGINO_PLUGIN_PREVIEW_BODY -->` in
`preview.html` and `preview-raptor.html`.

## In-place navigation

With the "In-place navigation" setting on (Settings > Web Interface, off by
default), `/a/router.js` switches between pages by replacing the content of
`<main>` instead of loading the whole page. It does that only for pages that
are listed, and a page is listed by the package that owns it:

```json
{ "router": { "pages": ["config-myplugin"] } }
```

The names are page names without `.html`. The webui package's own pages are
listed in `package/thingino-webui/files/router-pages.json`.

A listed page has to keep to one rule, because its script runs again on
every visit:

- it loads exactly one script of its own, `/a/<page>.js`, from the body
  (scripts under `/a/vendor/` and the shell's own scripts do not count);
- it has no inline `<script>` and no head script besides the shared ones;
- `/a/<page>.js` is wrapped in an IIFE, with nothing declared at its top
  level, binds to the page's own content, and leaves no `window` or
  `document` listener or timer behind. Stop anything that outlives the page
  on the `thingino:page-leave` event.

`assemble_plugins.py` checks the first three points for every listed page
that is in the image, at build time and in `scripts/check-plugins.sh`, and
fails on a page that breaks them. What the page script binds and leaves
behind cannot be checked: read it before listing the page. A page that is
not listed is loaded in full, as before.

## Migrating an existing integration

If your package already has web files in core webui:

1. Create `<name>.webui.json` manifest
2. Move web files from `package/thingino-webui/files/www/` to your package
3. Delete the hardcoded nav item from `navigation.js`
4. Delete the `$(INSTALL)` block from `thingino-webui.mk`
5. Delete any runtime probing from `S48webui-config`
6. Add `DEPENDENCIES += thingino-webui` to your `.mk`
7. Run `scripts/check-plugins.sh`

## Existing plugins (examples)

| Plugin | Package | Manifest |
|--------|---------|----------|
| motors | `thingino-motors` | `package/thingino-motors/files/motors.webui.json` |
| doorbell | `wyze-accessory` | `package/wyze-accessory/files/doorbell.webui.json` |
| daynightd | `thingino-daynightd` | `package/thingino-daynightd/files/daynightd.webui.json` |
