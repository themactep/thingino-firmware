#!/usr/bin/env python3
"""Point the web UI at the bundled reduced vendor assets instead of CDNs.

The main UI pulls Bootstrap, Bootstrap Icons and a Google font from CDNs. In AP
mode the camera has no uplink, so those requests fail and the UI renders
unstyled / non-functional. This rewrites the core tags to the local reduced set
installed at /a/vendor (bootstrap css + used-plugins js; see
scripts/optimize-offline-vendor.sh), so the full UI works offline.

The patterns match the whole tag regardless of attribute order, so they also
match after apply_cdn_fallback.py has appended onerror= handlers (the fallback
runs at install time, this runs later at rootfs time); the rewritten tag drops
those attributes.

Not bundled: the Montserrat webfont (link dropped, system font used), Chart.js
(sensor-data page only; tag left on the CDN, and tool-sensor-data.js degrades
gracefully without it), and the icon font (its subset lacked glyphs that the
streamer/preview pages use, which rendered as tofu, so the stylesheet is dropped
and the icon elements are hidden).
"""
import pathlib
import re
import sys

REPLACEMENTS = [
    # Google Fonts preconnect hints and stylesheet: drop entirely (system font)
    (re.compile(r'\s*<link\b[^>]*href="https://fonts\.googleapis\.com"[^>]*>', re.IGNORECASE), ''),
    (re.compile(r'\s*<link\b[^>]*href="https://fonts\.gstatic\.com"[^>]*>', re.IGNORECASE), ''),
    (re.compile(r'\s*<link\b[^>]*href="https://fonts\.googleapis\.com/css2[^"]*"[^>]*>', re.IGNORECASE), ''),

    # Bootstrap CSS CDN -> local
    (re.compile(
        r'<link\b[^>]*href="https://cdn\.jsdelivr\.net/npm/bootstrap@[^"]*?/dist/css/bootstrap(?:\.min)?\.css"[^>]*>',
        re.IGNORECASE,
    ), '<link rel="stylesheet" href="/a/vendor/bootstrap.min.css">'),

    # Bootstrap Icons: the bundled subset only carried the glyphs thingino-webui
    # uses, so streamer/preview pages showed missing glyphs (tofu). Drop the
    # stylesheet and hide the icon elements instead.
    (re.compile(
        r'\s*<link\b[^>]*href="https://cdn\.jsdelivr\.net/npm/bootstrap-icons@[^"]*?/font/bootstrap-icons(?:\.min)?\.css"[^>]*>',
        re.IGNORECASE,
    ), '\n<style>.bi,[class^="bi-"],[class*=" bi-"]{display:none!important}</style>'),

    # Bootstrap JS bundle CDN -> local
    (re.compile(
        r'<script\b[^>]*src="https://cdn\.jsdelivr\.net/npm/bootstrap@[^"]*?/dist/js/bootstrap(?:\.bundle)?(?:\.min)?\.js"[^>]*></script>',
        re.IGNORECASE,
    ), '<script src="/a/vendor/bootstrap.bundle.min.js"></script>'),
]


def rewrite_file(path: pathlib.Path) -> bool:
    try:
        content = path.read_text(encoding='utf-8')
    except OSError:
        return False
    original = content
    for pattern, replacement in REPLACEMENTS:
        content = pattern.sub(replacement, content)
    if content != original:
        try:
            path.write_text(content, encoding='utf-8')
            return True
        except OSError:
            pass
    return False


def main() -> int:
    if len(sys.argv) < 2:
        print(f"Usage: {sys.argv[0]} <target-var-www-dir>", file=sys.stderr)
        return 1
    root = pathlib.Path(sys.argv[1])
    if not root.is_dir():
        print(f"ERROR: {root} is not a directory", file=sys.stderr)
        return 1
    count = 0
    for path in sorted(root.rglob('*.html')):
        if rewrite_file(path):
            count += 1
    print(f"thingino-webui: offline assets - {count} HTML file(s) rewritten to local /a/vendor")
    return 0


if __name__ == '__main__':
    sys.exit(main())
