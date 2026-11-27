#!/usr/bin/env python3
"""
Assemble Thingino WebUI plugin manifests into static runtime configuration.

Scans TARGET_DIR/var/www/a/plugins/*.webui.json, validates for conflicts,
merges nav contributions, injects scripts/styles/HTML into pages (preserving
existing asset cache-busting timestamps from data-asset-ts).

Also checks the pages listed for in-place navigation (a "router" block in a
manifest, and files/router-pages.json for the webui package's own pages)
against the rule /a/router.js depends on, and writes the list of the ones in
the image to plugins.js.

Usage:
  assemble_plugins.py <staging-dir>            # full assembly
  assemble_plugins.py --check-only <staging-dir>  # validate only, no writes
"""

import json
import os
import re
import sys
from html.parser import HTMLParser
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

# Streamer plugins are mutually exclusive at build time (only one streamer
# package is selected). Source-tree validation may see all of them at once;
# allow page/CGI overlap across distinct streamer feature flags.
STREAMER_FEATURE_FLAGS = frozenset({"prudynt", "raptor", "timps", "strero"})


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

# Regex to extract data-asset-ts from <html> tag
ASSET_TS_RE = re.compile(r'<html\b[^>]*\bdata-asset-ts="([^"]+)"', re.IGNORECASE)


# ---------------------------------------------------------------------------
# Validation
# ---------------------------------------------------------------------------

class PluginError(Exception):
    """Hard error — build should fail."""


class PluginWarning(Exception):
    """Soft warning — printed but build continues."""


def _streamer_flag(manifest: Dict[str, Any]) -> Optional[str]:
    flags = manifest.get("featureFlags") or {}
    for flag in STREAMER_FEATURE_FLAGS:
        if flags.get(flag):
            return flag
    return None


def validate_manifests(
    manifests: List[Dict[str, Any]], manifest_paths: Dict[str, Path]
) -> None:
    """Check for conflicts across all loaded manifests."""
    names: Dict[str, Path] = {}
    pages: Dict[str, str] = {}
    page_streamers: Dict[str, Optional[str]] = {}
    cgi_endpoints: Dict[str, str] = {}
    cgi_streamers: Dict[str, Optional[str]] = {}

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
        streamer = _streamer_flag(m)

        for page in m.get("pages", []):
            if page in pages:
                other = pages[page]
                other_streamer = page_streamers.get(page)
                if (
                    streamer
                    and other_streamer
                    and streamer != other_streamer
                ):
                    # Mutually exclusive streamer plugins may share paths.
                    continue
                raise PluginError(
                    f"Plugin '{name}' declares page '{page}' which is "
                    f"already claimed by plugin '{other}'"
                )
            pages[page] = name
            page_streamers[page] = streamer

        for cgi in m.get("cgi", []):
            if cgi in cgi_endpoints:
                other = cgi_endpoints[cgi]
                other_streamer = cgi_streamers.get(cgi)
                if (
                    streamer
                    and other_streamer
                    and streamer != other_streamer
                ):
                    continue
                print(
                    f"WARNING: Plugin '{name}' declares CGI '{cgi}' which "
                    f"is already claimed by plugin '{other}'",
                    file=sys.stderr,
                )
            else:
                cgi_endpoints[cgi] = name
                cgi_streamers[cgi] = streamer


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

def make_script_tag(src: str, asset_ts: str = "") -> str:
    """Generate a <script> tag for the given source path."""
    ts = f"?ts={asset_ts}" if asset_ts else ""
    return f'<script src="{src}{ts}"></script>'


def make_link_tag(href: str, asset_ts: str = "") -> str:
    """Generate a <link> tag for the given stylesheet path."""
    ts = f"?ts={asset_ts}" if asset_ts else ""
    return f'<link rel="stylesheet" href="{href}{ts}">'


def inject_plugins_js(html_content: str, www_root: Path, asset_ts: str = "") -> str:
    """Insert <script src='/a/plugins.js'> after runtime-config.js."""
    plugin_tag = make_script_tag("/a/plugins.js", asset_ts)

    def replacement(match):
        return match.group(0) + "\n" + plugin_tag

    if RUNTIME_CONFIG_RE.search(html_content):
        return RUNTIME_CONFIG_RE.sub(replacement, html_content, count=1)
    # Fallback: insert before </head>
    return CLOSING_HEAD_RE.sub(
        lambda m: plugin_tag + "\n" + m.group(0), html_content, count=1
    )


def inject_global_scripts(
    html_content: str, manifests: List[Dict[str, Any]], asset_ts: str = ""
) -> str:
    """Inject plugin global scripts and styles before </head>."""
    tags: List[str] = []

    for m in manifests:
        for style in m.get("styles", []):
            tags.append(make_link_tag(style, asset_ts))
        for script in m.get("scripts", []):
            tags.append(make_script_tag(script, asset_ts))

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
    html_content: str, manifests: List[Dict[str, Any]], asset_ts: str = ""
) -> str:
    """Inject preview-specific scripts before </body>."""
    tags: List[str] = []
    for m in manifests:
        preview = m.get("preview", {})
        for script in preview.get("scripts", []):
            tags.append(make_script_tag(script, asset_ts))

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

        # Extract asset timestamp from <html data-asset-ts="...">
        asset_ts = ""
        ts_match = ASSET_TS_RE.search(content)
        if ts_match:
            asset_ts = ts_match.group(1)

        # Inject plugins.js after runtime-config.js (all pages)
        content = inject_plugins_js(content, www_root, asset_ts)

        # Inject global scripts/styles (all pages)
        content = inject_global_scripts(content, manifests, asset_ts)

        # Preview-specific injections
        if is_preview_page(path):
            content = inject_preview_body(content, manifests)
            content = inject_preview_scripts(content, manifests, asset_ts)

        if content != original:
            try:
                path.write_text(content, encoding="utf-8")
            except OSError:
                print(f"ERROR: Failed to write {path}", file=sys.stderr)


# ---------------------------------------------------------------------------
# In-place navigation: the page list and its check
# ---------------------------------------------------------------------------
#
# /a/router.js swaps a page's content in place instead of loading the whole
# page. That is only safe for a page whose one page script, /a/<page>.js, can
# run again against new content. The pages are listed by the packages that own
# them: a "router" block in a plugin's webui.json, and the webui package's own
# list (files/router-pages.json). Every listed page that is in the image is checked
# here, and the list reaches the browser (cfg.routerPages in plugins.js) only
# if all of them pass, so a page cannot drift off the rule unnoticed.

ROUTER_CORE_LIST = Path(__file__).resolve().parent.parent / "files" / "router-pages.json"
ROUTER_PAGE_RE = re.compile(r"^[a-z0-9-]+$")

# Scripts of the shell, present on every page. router.js has the same list.
ROUTER_SHARED_SCRIPTS = frozenset(
    {
        "main.js",
        "runtime-config.js",
        "plugins.js",
        "control-bar.js",
        "navigation.js",
        "footer.js",
        "theme-init.js",
        "router.js",
    }
)

# A "/" after one of these starts a regular expression, not a division.
_JS_REGEX_AFTER = frozenset("(,=:[!&|?{};+-*%<>~^}")
_JS_REGEX_AFTER_WORDS = frozenset(
    {
        "return",
        "typeof",
        "instanceof",
        "in",
        "of",
        "new",
        "delete",
        "void",
        "throw",
        "case",
        "do",
        "else",
        "yield",
        "await",
    }
)


def js_top_level_residue(source: str) -> str:
    """Return what a script has at its top level besides bracketed groups.

    Comments, strings, template literals and regular expressions are skipped,
    and everything inside (), [] and {} is dropped. For a script that is one
    or more IIFEs, optionally after a "use strict" directive, what is left is
    only semicolons and string markers ("S"). Anything else is code or a
    declaration at the top level. Raises ValueError when brackets do not
    balance.
    """
    out: List[str] = []
    stack: List[str] = []
    closers = {")": "(", "]": "[", "}": "{"}
    prev = ""  # last significant character in code
    word = ""  # last identifier or keyword in code
    i = 0
    n = len(source)

    def mark(text: str) -> None:
        if not stack:
            out.append(text)

    while i < n:
        c = source[i]
        nxt = source[i + 1] if i + 1 < n else ""

        if stack and stack[-1] == "`":
            # Template text: only \, ` and ${ matter.
            if c == "\\":
                i += 2
            elif c == "`":
                stack.pop()
                prev, word = "S", ""
                mark("S")
                i += 1
            elif c == "$" and nxt == "{":
                stack.append("${")
                prev, word = "{", ""
                i += 2
            else:
                i += 1
            continue

        if c.isspace():
            i += 1
            continue
        if c == "/" and nxt == "/":
            j = source.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == "/" and nxt == "*":
            j = source.find("*/", i + 2)
            if j < 0:
                raise ValueError("unterminated comment")
            i = j + 2
            continue
        if c in "\"'":
            j = i + 1
            while j < n and source[j] != c:
                if source[j] == "\n":
                    raise ValueError("unterminated string")
                j += 2 if source[j] == "\\" else 1
            if j >= n:
                raise ValueError("unterminated string")
            i = j + 1
            prev, word = "S", ""
            mark("S")
            continue
        if c == "`":
            stack.append("`")
            i += 1
            continue
        if c == "/" and (
            prev == "" or prev in _JS_REGEX_AFTER or word in _JS_REGEX_AFTER_WORDS
        ):
            j = i + 1
            in_class = False
            while j < n and source[j] != "\n":
                ch = source[j]
                if ch == "\\":
                    j += 2
                    continue
                if ch == "[":
                    in_class = True
                elif ch == "]":
                    in_class = False
                elif ch == "/" and not in_class:
                    break
                j += 1
            if j < n and source[j] == "/":
                j += 1
                while j < n and (source[j].isalnum() or source[j] == "_"):
                    j += 1
                i = j
                prev, word = "R", ""
                mark("R")
                continue
            # No closing slash on the line: a division after all.
        if c in "([{":
            stack.append(c)
            prev, word = c, ""
            i += 1
            continue
        if c in ")]}":
            if stack and stack[-1] == "${" and c == "}":
                stack.pop()
                i += 1
                continue
            if not stack or stack[-1] != closers[c]:
                raise ValueError(f"unbalanced '{c}'")
            stack.pop()
            prev, word = c, ""
            i += 1
            continue
        if c.isalnum() or c in "_$":
            j = i
            while j < n and (source[j].isalnum() or source[j] in "_$"):
                j += 1
            word = source[i:j]
            prev = "w"
            mark(word)
            i = j
            continue
        prev, word = c, ""
        mark(c)
        i += 1

    if stack:
        raise ValueError(f"unclosed '{stack[-1]}'")
    return "".join(out)


class _ScriptScan(HTMLParser):
    """Collect a page's <script> tags as (section, src, type)."""

    def __init__(self) -> None:
        super().__init__(convert_charrefs=True)
        self.section = ""
        self.scripts: List[Tuple[str, Optional[str], str]] = []

    def handle_starttag(self, tag: str, attrs: List[Tuple[str, Optional[str]]]) -> None:
        if tag in ("head", "body"):
            self.section = tag
        elif tag == "script":
            values = dict(attrs)
            self.scripts.append(
                (self.section, values.get("src"), (values.get("type") or "").lower())
            )


def _router_script_name(src: str) -> Optional[str]:
    """Name of a camera script under /a/ (not /a/vendor/), without its tag."""
    path = src.split("?", 1)[0].split("#", 1)[0]
    if not path.startswith("/a/") or path.startswith("/a/vendor/"):
        return None
    return path[len("/a/"):]


def check_router_page(
    www_root: Path, page: str, plugin_scripts: frozenset
) -> List[str]:
    """Return what keeps a listed page from being swapped in place."""
    problems: List[str] = []
    html_path = www_root / f"{page}.html"
    scan = _ScriptScan()
    scan.feed(html_path.read_text(encoding="utf-8"))
    shared = ROUTER_SHARED_SCRIPTS | plugin_scripts

    page_scripts: List[str] = []
    for section, src, script_type in scan.scripts:
        if src is None:
            if not script_type or "javascript" in script_type or "module" in script_type:
                problems.append(f"an inline script in <{section or 'html'}>")
            continue
        name = _router_script_name(src)
        if section == "head":
            if name is None or name not in shared:
                problems.append(f"a head script that is not shared: {src}")
        elif name is not None and name not in shared:
            page_scripts.append(name)

    if page_scripts != [f"{page}.js"]:
        found = ", ".join(page_scripts) if page_scripts else "none"
        problems.append(f"its page scripts must be exactly {page}.js (found: {found})")
        return problems

    script_path = www_root / "a" / f"{page}.js"
    if not script_path.is_file():
        problems.append(f"a/{page}.js is not in the image")
        return problems
    try:
        residue = js_top_level_residue(script_path.read_text(encoding="utf-8"))
    except ValueError as e:
        problems.append(f"a/{page}.js could not be read as a script: {e}")
        return problems
    leftover = residue.replace("S", "").replace(";", "")
    if leftover:
        problems.append(
            f"a/{page}.js has code outside an IIFE at its top level "
            f"(near '{leftover[:40]}'); wrap the script in (function () {{ ... }})();"
        )
    return problems


def listed_router_pages(manifests: List[Dict[str, Any]]) -> Dict[str, str]:
    """Return {page: who listed it} for every page a package lists for the router."""
    listed: Dict[str, str] = {}
    streamers: Dict[str, Optional[str]] = {}

    def add(page: Any, source: str, streamer: Optional[str]) -> None:
        if not isinstance(page, str) or not ROUTER_PAGE_RE.match(page):
            raise PluginError(
                f"{source}: router page {page!r} must be a page name such as "
                f"'config-time' (lowercase letters, digits and hyphens, no .html)"
            )
        if page in listed:
            other = streamers.get(page)
            if streamer and other and streamer != other:
                return
            raise PluginError(
                f"{source}: router page '{page}' is already listed by {listed[page]}"
            )
        listed[page] = source
        streamers[page] = streamer

    core = ROUTER_CORE_LIST
    if core.is_file():
        try:
            data = json.loads(core.read_text(encoding="utf-8"))
        except json.JSONDecodeError as e:
            raise PluginError(f"Invalid JSON in {core}: {e}") from e
        pages = data.get("pages") if isinstance(data, dict) else None
        if not isinstance(pages, list):
            raise PluginError(f"{core}: expected an object with a 'pages' list")
        for page in pages:
            add(page, "the webui package's list", None)

    for m in manifests:
        block = m.get("router")
        if block is None:
            continue
        source = f"plugin '{m.get('name', '?')}'"
        pages = block.get("pages") if isinstance(block, dict) else None
        if not isinstance(pages, list):
            raise PluginError(f"{source}: 'router' must be an object with a 'pages' list")
        for page in pages:
            add(page, source, _streamer_flag(m))
    return listed


def collect_router_pages(
    www_root: Path, manifests: List[Dict[str, Any]]
) -> List[str]:
    """Check every listed page that is in the image; return the ones to offer."""
    listed = listed_router_pages(manifests)
    plugin_scripts = set()
    for m in manifests:
        for src in list(m.get("scripts", [])) + list(m.get("preview", {}).get("scripts", [])):
            name = _router_script_name(src)
            if name:
                plugin_scripts.add(name)

    pages: List[str] = []
    failures: List[str] = []
    for page in sorted(listed):
        if not (www_root / f"{page}.html").is_file():
            continue
        problems = check_router_page(www_root, page, frozenset(plugin_scripts))
        if problems:
            failures.extend(
                f"{page}.html (listed by {listed[page]}): {p}" for p in problems
            )
        else:
            pages.append(page)

    if failures:
        raise PluginError(
            "Pages listed for in-place navigation break its rule:\n  "
            + "\n  ".join(failures)
            + "\n  Fix the page, or take it off the list."
        )
    if listed:
        print(f"  Router: {len(pages)} of {len(listed)} listed page(s) are in this image and pass")
    return pages


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
    www_root: Path,
    manifests: List[Dict[str, Any]],
    router_pages: Optional[List[str]] = None,
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
        "  // Pages /a/router.js may swap in place (checked at build time)",
        f"  cfg.routerPages = {json.dumps(sorted(router_pages or []))};",
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
        router_pages = collect_router_pages(www_root, manifests)
    except PluginError as e:
        print(f"ERROR: {e}", file=sys.stderr)
        return 1

    if check_only:
        print("  Validation passed (--check-only)")
        return 0

    # Generate plugins.js with merged config
    write_plugins_js(www_root, manifests, router_pages)

    # Inject scripts, styles, and preview HTML into HTML pages
    process_html_files(www_root, manifests)

    return 0


if __name__ == "__main__":
    sys.exit(main())
