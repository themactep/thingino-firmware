#!/usr/bin/env python3
"""
Assemble Thingino WebUI plugin manifests into static runtime configuration.

Scans TARGET_DIR/var/www/a/plugins/*.webui.json, validates for conflicts,
merges nav contributions, injects scripts/styles/HTML into pages, and
re-applies asset tags and CDN fallbacks.

Usage:
  assemble_plugins.py <staging-dir>            # full assembly
  assemble_plugins.py --check-only <staging-dir>  # validate only, no writes
"""

import json
import os
import re
import sys
from pathlib import Path
from typing import Any, Dict, List, Optional, Tuple

# ---------------------------------------------------------------------------
# Constants
# ---------------------------------------------------------------------------

PLUGINS_GLOB = "var/www/a/plugins/*.webui.json"
PLUGINS_OUTPUT = "var/www/a/plugins.js"

# Standard navigation sections and their default item labels (for position
# resolution).  Only labels matter for "after:X"/"before:X" resolution.
KNOWN_SECTIONS = {
    "ddInfo": "Information",
    "ddSettings": "Settings",
    "ddTools": "Tools",
    "ddServices": "Services",
    "ddStreamer": "Streamer",
    "ddHelp": "Help",
}

# HTML pages to process for script/style/preview injection.
HTML_GLOB = "var/www/**/*.html"

# Marker that the assembly script replaces with plugin preview HTML.
PREVIEW_BODY_MARKER = "<!-- THINGINO_PLUGIN_PREVIEW_BODY -->"

# Regex to find <script src="/a/runtime-config.js"> for inserting plugins.js after it.
RUNTIME_CONFIG_RE = re.compile(
    r'(<script\s+src="[^"]*runtime-config\.js"[^>]*>\s*</script>)',
    re.IGNORECASE,
)

# Regex to find </head> for global script/style injection.
CLOSING_HEAD_RE = re.compile(r"</head>", re.IGNORECASE)

# Regex to find </body> for preview script injection.
CLOSING_BODY_RE = re.compile(r"</body>", re.IGNORECASE)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class PluginError(Exception):
    """Hard error — build should fail."""


class PluginWarning(Exception):
    """Soft warning — printed but build continues."""


def validate_manifests(
    manifests: List[Dict[str, Any]], manifest_paths: Dict[str, Path]
) -> None:
    """Check for conflicts across all loaded manifests."""
    names: Dict[str, Path] = {}
    pages: Dict[str, str] = {}
    cgi_endpoints: Dict[str, str] = {}

    for m in manifests:
        name = m.get("name", "")
        if not name:
            raise PluginError("Manifest is missing required 'name' field")
        if not isinstance(name, str) or not re.match(r"^[a-z0-9_-]+$", name):
            raise PluginError(
                f"Plugin name '{name}' must be lowercase alphanumeric "
                f"with hyphens/underscores only"
            )
        if name in names:
            raise PluginError(
                f"Duplicate plugin name '{name}' in manifests "
                f"{names[name]} and {manifest_paths.get(name, 'unknown')}"
            )
        names[name] = manifest_paths.get(name, Path("unknown"))

        for page in m.get("pages", []):
            if page in pages:
                raise PluginError(
                    f"Plugin '{name}' declares page '{page}' which is "
                    f"already claimed by plugin '{pages[page]}'"
                )
            pages[page] = name

        for cgi in m.get("cgi", []):
            if cgi in cgi_endpoints:
                print(
                    f"WARNING: Plugin '{name}' declares CGI '{cgi}' which "
                    f"is already claimed by plugin '{cgi_endpoints[cgi]}'",
                    file=sys.stderr,
                )
            else:
                cgi_endpoints[cgi] = name


# ---------------------------------------------------------------------------
# Nav merging
# ---------------------------------------------------------------------------

def resolve_position(
    position: str, items: List[Dict[str, Any]]
) -> int:
    """Return the 0-based index where new items should be inserted."""
    if not position or position == "append":
        return len(items)
    if position == "prepend":
        return 0
    if position.startswith("index:"):
        try:
            idx = int(position.split(":", 1)[1])
            return max(0, min(idx, len(items)))
        except ValueError:
            print(
                f"WARNING: Invalid position '{position}', appending",
                file=sys.stderr,
            )
            return len(items)
    if position.startswith("after:"):
        label = position.split(":", 1)[1].strip()
        for i, item in enumerate(items):
            if item.get("label") == label:
                return i + 1
        print(
            f"WARNING: Label '{label}' not found for 'after:', appending",
            file=sys.stderr,
        )
        return len(items)
    if position.startswith("before:"):
        label = position.split(":", 1)[1].strip()
        for i, item in enumerate(items):
            if item.get("label") == label:
                return i
        print(
            f"WARNING: Label '{label}' not found for 'before:', appending",
            file=sys.stderr,
        )
        return len(items)
    print(
        f"WARNING: Unknown position '{position}', appending",
        file=sys.stderr,
    )
    return len(items)


def apply_nav_contribution(
    section_id: str,
    section: Dict[str, Any],
    contribution: Dict[str, Any],
) -> Dict[str, Any]:
    """Apply a single nav contribution to a section, returning updated section."""
    items = list(section.get("items", []))
    position = contribution.get("position", "append")
    new_items = contribution.get("items", [])

    if not new_items:
        return section

    idx = resolve_position(position, items)
    for i, item in enumerate(new_items):
        items.insert(idx + i, item)

    return {**section, "items": items}


def merge_nav(
    menu: List[Dict[str, Any]], manifests: List[Dict[str, Any]]
) -> List[Dict[str, Any]]:
    """Apply all plugin nav contributions to the menu structure."""
    # Build a lookup of section-id -> index in the menu list
    section_index: Dict[str, int] = {}
    for i, entry in enumerate(menu):
        if entry.get("type") == "dropdown" and entry.get("id"):
            section_index[entry["id"]] = i

    # Process each manifest's nav contributions in order
    for m in manifests:
        for contribution in m.get("nav", []):
            section_id = contribution.get("section", "")
            if not section_id:
                print(
                    f"WARNING: Plugin '{m['name']}' has nav contribution "
                    f"without 'section', skipping",
                    file=sys.stderr,
                )
                continue
            if section_id not in section_index:
                print(
                    f"WARNING: Plugin '{m['name']}' targets unknown "
                    f"section '{section_id}', skipping",
                    file=sys.stderr,
                )
                continue
            idx = section_index[section_id]
            menu[idx] = apply_nav_contribution(
                section_id, menu[idx], contribution
            )

    return menu


# ---------------------------------------------------------------------------
# HTML injection
# ---------------------------------------------------------------------------

def make_script_tag(src: str) -> str:
    """Generate a <script> tag for the given source path."""
    return f'<script src="{src}"></script>'


def make_link_tag(href: str) -> str:
    """Generate a <link> tag for the given stylesheet path."""
    return f'<link rel="stylesheet" href="{href}">'


def inject_plugins_js(html_content: str, www_root: Path) -> str:
    """Insert <script src='/a/plugins.js'> after runtime-config.js."""
    plugin_tag = make_script_tag("/a/plugins.js")

    def replacement(match):
        return match.group(0) + "\n" + plugin_tag

    if RUNTIME_CONFIG_RE.search(html_content):
        return RUNTIME_CONFIG_RE.sub(replacement, html_content, count=1)
    # Fallback: insert before </head>
    return CLOSING_HEAD_RE.sub(
        lambda m: plugin_tag + "\n" + m.group(0), html_content, count=1
    )


def inject_global_scripts(
    html_content: str, manifests: List[Dict[str, Any]]
) -> str:
    """Inject plugin global scripts and styles before </head>."""
    tags: List[str] = []

    for m in manifests:
        for style in m.get("styles", []):
            tags.append(make_link_tag(style))
        for script in m.get("scripts", []):
            tags.append(make_script_tag(script))

    if not tags:
        return html_content

    injection = "\n".join(tags)
    return CLOSING_HEAD_RE.sub(
        lambda m: injection + "\n" + m.group(0), html_content, count=1
    )


def inject_preview_body(
    html_content: str, manifests: List[Dict[str, Any]]
) -> str:
    """Replace the preview body marker with plugin HTML snippets."""
    snippets: List[str] = []
    for m in manifests:
        preview = m.get("preview", {})
        html = preview.get("html")
        if html:
            snippets.append(html.strip())

    replacement = "\n".join(snippets) if snippets else ""
    if PREVIEW_BODY_MARKER in html_content:
        return html_content.replace(PREVIEW_BODY_MARKER, replacement)
    return html_content


def inject_preview_scripts(
    html_content: str, manifests: List[Dict[str, Any]]
) -> str:
    """Inject preview-specific scripts before </body>."""
    tags: List[str] = []
    for m in manifests:
        preview = m.get("preview", {})
        for script in preview.get("scripts", []):
            tags.append(make_script_tag(script))

    if not tags:
        return html_content

    injection = "\n".join(tags)
    return CLOSING_BODY_RE.sub(
        lambda m: injection + "\n" + m.group(0), html_content, count=1
    )


def is_preview_page(path: Path) -> bool:
    """Check if an HTML file is a preview page variant."""
    name = path.name.lower()
    return name.startswith("preview") and name.endswith(".html")


def process_html_files(
    www_root: Path, manifests: List[Dict[str, Any]]
) -> None:
    """Walk all HTML files and apply injections."""
    html_files = list(www_root.glob("**/*.html"))
    if not html_files:
        print("WARNING: No HTML files found in www root", file=sys.stderr)
        return

    for path in sorted(html_files):
        try:
            content = path.read_text(encoding="utf-8")
        except OSError:
            continue

        original = content

        # Inject plugins.js after runtime-config.js (all pages)
        content = inject_plugins_js(content, www_root)

        # Inject global scripts/styles (all pages)
        content = inject_global_scripts(content, manifests)

        # Preview-specific injections
        if is_preview_page(path):
            content = inject_preview_body(content, manifests)
            content = inject_preview_scripts(content, manifests)

        if content != original:
            try:
                path.write_text(content, encoding="utf-8")
            except OSError:
                print(f"ERROR: Failed to write {path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# Plugins.js generation
# ---------------------------------------------------------------------------

def build_plugins_config(
    manifests: List[Dict[str, Any]],
) -> Dict[str, Any]:
    """Build the merged plugins configuration object."""
    plugins: Dict[str, Any] = {}
    feature_flags: Dict[str, bool] = {}

    for m in manifests:
        name = m["name"]
        entry: Dict[str, Any] = {
            "name": name,
        }
        if m.get("label"):
            entry["label"] = m["label"]
        if m.get("nav"):
            entry["nav"] = m["nav"]
        if m.get("preview", {}).get("scripts"):
            entry["previewScripts"] = m["preview"]["scripts"]
        if m.get("scripts"):
            entry["scripts"] = m["scripts"]

        plugins[name] = entry

        for flag, value in m.get("featureFlags", {}).items():
            feature_flags[flag] = bool(value)

    return {"plugins": plugins, "featureFlags": feature_flags}


def write_plugins_js(
    www_root: Path, manifests: List[Dict[str, Any]]
) -> None:
    """Generate /var/www/a/plugins.js with merged plugin configuration."""
    config = build_plugins_config(manifests)
    plugins_dir = www_root / "a"
    plugins_dir.mkdir(parents=True, exist_ok=True)

    js_lines = [
        "// Generated by assemble_plugins.py — do not edit by hand",
        "(function(){",
        '  "use strict";',
        "  var cfg = window.thinginoUIConfig || {};",
        "  window.thinginoUIConfig = cfg;",
        "",
        f"  cfg.plugins = {json.dumps(config['plugins'], indent=2, sort_keys=True)};",
        "",
        "  // Merge feature flags into cfg.device",
        "  cfg.device = cfg.device || {};",
    ]

    for flag, value in sorted(config["featureFlags"].items()):
        js_lines.append(f'  cfg.device["{flag}"] = {json.dumps(value)};')

    js_lines.append("})();")
    js_lines.append("")

    output_path = www_root / "a" / "plugins.js"
    output_path.write_text("\n".join(js_lines), encoding="utf-8")
    print(f"  Generated: {output_path}")


# ---------------------------------------------------------------------------
# Main
# ---------------------------------------------------------------------------

def load_manifests(staging_dir: Path) -> List[Tuple[Dict[str, Any], Path]]:
    """Load all plugin manifests from the staging directory."""
    manifests: List[Tuple[Dict[str, Any], Path]] = []
    plugin_dir = staging_dir / "var" / "www" / "a" / "plugins"

    if not plugin_dir.is_dir():
        print(f"  No plugins directory at {plugin_dir}, skipping")
        return manifests

    for path in sorted(plugin_dir.glob("*.webui.json")):
        try:
            data = json.loads(path.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise PluginError(f"Invalid JSON in {path}: {e}") from e
        manifests.append((data, path))

    return manifests


def main() -> int:
    check_only = False
    args = sys.argv[1:]

    if "--check-only" in args:
        check_only = True
        args.remove("--check-only")

    if len(args) < 1:
        print(f"Usage: {sys.argv[0]} [--check-only] <staging-dir>", file=sys.stderr)
        return 1

    staging_dir = Path(args[0]).resolve()
    if not staging_dir.is_dir():
        print(f"ERROR: Staging directory not found: {staging_dir}", file=sys.stderr)
        return 1

    www_root = staging_dir / "var" / "www"
    if not www_root.is_dir():
        print(f"  No www directory at {www_root}, nothing to assemble")
        return 0

    try:
        raw_manifests = load_manifests(staging_dir)
    except PluginError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if not raw_manifests:
        print("  No plugin manifests found, nothing to assemble")
        return 0

    manifests = [m[0] for m in raw_manifests]
    manifest_paths = {m[0]["name"]: m[1] for m in raw_manifests}

    print(f"Found {len(manifests)} plugin(s): {', '.join(m['name'] for m in manifests)}")

    try:
        validate_manifests(manifests, manifest_paths)
    except PluginError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if check_only:
        print("  Validation passed (--check-only)")
        return 0

    # Generate plugins.js with merged config
    write_plugins_js(www_root, manifests)

    # Inject scripts, styles, and preview HTML into HTML pages
    process_html_files(www_root, manifests)

    return 0


if __name__ == "__main__":
    sys.exit(main())
