#!/usr/bin/env python3
"""apply_cdn_fallback.py - Add onerror local fallback attributes to CDN link/script tags.

Processes every HTML file under <www_root> and rewrites CDN asset references to
include an onerror= attribute that loads a local copy from /a/vendor/ if the CDN
request fails (e.g. no network access).

The source HTML files are left unchanged; this script runs against the already-
installed copy in TARGET_DIR/var/www during the build.

Usage:
    python3 apply_cdn_fallback.py <www_root>
"""

import pathlib
import re
import sys
from typing import Iterable


HTML_EXTENSIONS = {'.html', '.htm'}

# ---------------------------------------------------------------------------
# Patterns and their corresponding local fallback handler strings.
# Each entry is (compiled_regex, onerror_js_body).
#
# The regex must capture:
#   group 1 – everything up to (but not including) the closing > / ></script>
#   group 2 – the closing delimiter  (> or ></script>)
#
# Patterns use [^>]* which naturally spans newlines (no DOTALL needed for [^>]).
# ---------------------------------------------------------------------------
CDN_FALLBACKS = [
    # Google Fonts – Montserrat stylesheet
    (
        re.compile(
            r'(<link\b[^>]*\bhref=["\']https://fonts\.googleapis\.com/[^"\']*["\'][^>]*)(>)',
            re.IGNORECASE,
        ),
        "this.onerror=null;var l=document.createElement('link');l.rel='stylesheet';l.href='/a/vendor/montserrat.css';this.parentNode.insertBefore(l,this.nextSibling)",
    ),
    # Bootstrap CSS (may span two lines due to integrity= attribute)
    (
        re.compile(
            r'(<link\b[^>]*\bhref=["\']https://cdn\.jsdelivr\.net/npm/bootstrap@[^/]+/dist/css/bootstrap(?:\.min)?\.css["\'][^>]*)(>)',
            re.IGNORECASE,
        ),
        "this.onerror=null;var l=document.createElement('link');l.rel='stylesheet';l.href='/a/vendor/bootstrap.min.css';this.parentNode.insertBefore(l,this.nextSibling)",
    ),
    # Bootstrap Icons CSS
    (
        re.compile(
            r'(<link\b[^>]*\bhref=["\']https://cdn\.jsdelivr\.net/npm/bootstrap-icons@[^/]+/font/bootstrap-icons(?:\.min)?\.css["\'][^>]*)(>)',
            re.IGNORECASE,
        ),
        "this.onerror=null;var l=document.createElement('link');l.rel='stylesheet';l.href='/a/vendor/bootstrap-icons.min.css';this.parentNode.insertBefore(l,this.nextSibling)",
    ),
    # Bootstrap JS bundle (closing delimiter is ></script>)
    (
        re.compile(
            r'(<script\b[^>]*\bsrc=["\']https://cdn\.jsdelivr\.net/npm/bootstrap@[^/]+/dist/js/bootstrap(?:\.bundle)?(?:\.min)?\.js["\'][^>]*)(></script>)',
            re.IGNORECASE,
        ),
        "this.onerror=null;var s=document.createElement('script');s.src='/a/vendor/bootstrap.bundle.min.js';document.head.appendChild(s)",
    ),
]


def iter_pages(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for path in root.rglob('*'):
        if path.is_file() and path.suffix.lower() in HTML_EXTENSIONS:
            yield path


def _already_has_onerror(tag_prefix: str) -> bool:
    return bool(re.search(r'\bonerror\b', tag_prefix, re.IGNORECASE))


def _add_onerror(match: re.Match, handler: str) -> str:
    prefix = match.group(1)
    closing = match.group(2)
    if _already_has_onerror(prefix):
        return match.group(0)  # idempotent – skip if already present
    return f'{prefix} onerror="{handler}"{closing}'


def process_file(path: pathlib.Path) -> bool:
    try:
        original = path.read_text(encoding='utf-8')
    except OSError:
        return False

    updated = original
    for pattern, handler in CDN_FALLBACKS:
        updated = pattern.sub(lambda m, h=handler: _add_onerror(m, h), updated)

    if updated == original:
        return False

    try:
        path.write_text(updated, encoding='utf-8')
        return True
    except OSError:
        return False


def main() -> int:
    if len(sys.argv) < 2:
        print(f'Usage: {sys.argv[0]} <www_root>', file=sys.stderr)
        return 1

    root = pathlib.Path(sys.argv[1])
    if not root.exists():
        print(f'thingino-webui: CDN fallback skipped – {root} does not exist',
              file=sys.stderr)
        return 0  # non-fatal so the build does not break

    count = 0
    for path in sorted(iter_pages(root)):
        if process_file(path):
            count += 1

    print(f'thingino-webui: CDN fallback onerror applied to {count} HTML file(s)')
    return 0


if __name__ == '__main__':
    sys.exit(main())
