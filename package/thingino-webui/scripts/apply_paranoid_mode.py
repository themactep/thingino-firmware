#!/usr/bin/env python3
"""Rewrite CDN asset references to local /a/vendor/ paths in all HTML files.

This is the inverse of CDN fallback — instead of adding onerror= fallbacks
to CDN links, we replace CDN links entirely with local vendor equivalents.

Triggered by BR2_PACKAGE_THINGINO_WEBUI_PARANOID=y.
"""
import pathlib
import re
import sys

# CDN → local mappings
REPLACEMENTS = [
    # Google Fonts preconnect (remove)
    (re.compile(r'\s*<link rel="preconnect" href="https://fonts\.googleapis\.com">\s*'), ''),
    (re.compile(r'\s*<link rel="preconnect" href="https://fonts\.gstatic\.com" crossorigin>\s*'), ''),

    # Google Fonts stylesheet → local Montserrat
    (re.compile(
        r'<link\s+rel="stylesheet"\s+href="https://fonts\.googleapis\.com/css2\?family=Montserrat:wght@400;500;600;700&display=swap"\s*/?>'
    ), '<link rel="stylesheet" href="/a/vendor/montserrat.css">'),

    # Bootstrap CSS CDN → local
    (re.compile(
        r'<link\s+rel="stylesheet"\s+href="https://cdn\.jsdelivr\.net/npm/bootstrap@5\.3\.\d+/dist/css/bootstrap\.min\.css"\s*\n?\s*integrity="[^"]*"\s+crossorigin="anonymous"\s*/?>'
    ), '<link rel="stylesheet" href="/a/vendor/bootstrap.min.css">'),

    # Bootstrap Icons CSS CDN → local
    (re.compile(
        r'<link\s+rel="stylesheet"\s+href="https://cdn\.jsdelivr\.net/npm/bootstrap-icons@1\.\d+\.\d+/font/bootstrap-icons\.min\.css"\s*/?>'
    ), '<link rel="stylesheet" href="/a/vendor/bootstrap-icons.min.css">'),

    # Bootstrap JS CDN → local
    (re.compile(
        r'<script\s+src="https://cdn\.jsdelivr\.net/npm/bootstrap@5\.3\.\d+/dist/js/bootstrap\.bundle\.min\.js"\s*\n?\s*integrity="[^"]*"\s+crossorigin="anonymous"\s*></script>'
    ), '<script src="/a/vendor/bootstrap.bundle.min.js"></script>'),
]

HTML_EXTENSIONS = {'.html', '.htm'}


def rewrite_file(path: pathlib.Path) -> bool:
    """Rewrite CDN references in a single HTML file. Returns True if changed."""
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

    print(f"thingino-webui: paranoid mode — {count} HTML file(s) rewritten to local assets")
    return 0


if __name__ == '__main__':
    sys.exit(main())
