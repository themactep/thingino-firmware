#!/usr/bin/env python3
"""Add ?ts=<tag> to /a/*.js and /a/*.css references in every HTML page.

usage: apply_asset_tag.py <tag|auto> <www root>

With "auto", the tag is a hash of everything under <www root>/a, so it
changes whenever any asset changes, whichever package installed it.
"""
import hashlib
import pathlib
import re
import sys
from typing import Iterable


ASSET_PATTERN = re.compile(
    r'(?P<attr>(?:src|href))=(?P<quote>["\'])(?P<path>/a/[^"\']+\.(?:js|css))(?:\?[^"\']*)?(?P=quote)',
    re.IGNORECASE,
)
HTML_PATTERN = re.compile(r'<html\b([^>]*)>', re.IGNORECASE)
HTML_ATTR_PATTERN = re.compile(r'\sdata-asset-ts=(["\']).*?\1', re.IGNORECASE)
HTML_EXTENSIONS = {'.html', '.htm'}


def iter_pages(root: pathlib.Path) -> Iterable[pathlib.Path]:
    for path in root.rglob('*'):
        if path.is_file() and path.suffix.lower() in HTML_EXTENSIONS:
            yield path


def content_tag(root: pathlib.Path) -> str:
    digest = hashlib.sha256()
    assets = root / 'a'
    for path in sorted(p for p in assets.rglob('*') if p.is_file()):
        digest.update(path.relative_to(assets).as_posix().encode())
        digest.update(b'\0')
        digest.update(path.read_bytes())
        digest.update(b'\0')
    return digest.hexdigest()[:12]


def main() -> int:
    if len(sys.argv) < 3:
        return 0

    tag = sys.argv[1].strip()
    root = pathlib.Path(sys.argv[2])

    if not tag or not root.exists():
        return 0

    if tag == 'auto':
        tag = content_tag(root)

    for path in sorted(iter_pages(root)):
        try:
            content = path.read_text(encoding='utf-8')
        except OSError:
            continue

        def replace_attr(match: re.Match[str]) -> str:
            return (
                f'{match.group("attr")}={match.group("quote")}'
                f'{match.group("path")}?ts={tag}{match.group("quote")}'
            )

        updated = ASSET_PATTERN.sub(replace_attr, content)

        def inject_html_attr(match: re.Match[str]) -> str:
            attrs = HTML_ATTR_PATTERN.sub('', match.group(1)).rstrip()
            if attrs:
                return f'<html{attrs} data-asset-ts="{tag}">'
            return f'<html data-asset-ts="{tag}">'

        updated = HTML_PATTERN.sub(inject_html_attr, updated, count=1)

        if updated != content:
            try:
                path.write_text(updated, encoding='utf-8')
            except OSError:
                pass

    return 0


if __name__ == '__main__':
    sys.exit(main())
