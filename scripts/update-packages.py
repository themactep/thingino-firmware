#!/usr/bin/env python3
"""
Update a Thingino package to a new version and automatically update its
.hash file for release (tarball) packages.

Usage:
    scripts/update-packages.py <package-name> <new-version>
    scripts/update-packages.py --check

For release/tarball packages (those using $(call github,...)), the .hash
file is automatically updated with the new sha256 hash.  For git-based
packages (SITE_METHOD = git), only the version in the .mk file is updated.

--check scans all packages and reports hash mismatches without making changes.
"""

import hashlib
import os
import re
import sys
import tempfile
import urllib.request
from pathlib import Path


FIRMWARE_ROOT = Path(__file__).resolve().parent.parent


def find_package_dir(name: str) -> Path:
    """Return the package directory for *name*."""
    d = FIRMWARE_ROOT / "package" / name
    if d.is_dir():
        return d
    raise SystemExit(f"package '{name}' not found at {d}")


def read_mk(path: Path) -> str:
    return path.read_text()


def parse_mk(text: str) -> dict:
    """Extract key variables from a package .mk file.

    Returns a dict with keys:
      prefix      – uppercase variable prefix (e.g. THINGINO_DFU)
      version     – current version string
      site_method – 'git', 'github', 'url', or None
      git_url     – git clone URL   (when site_method == 'git')
      gh_owner    – github owner    (when site_method == 'github')
      gh_repo     – github repo     (when site_method == 'github')
      gh_tag_expr – tag expression  (when site_method == 'github')
                      e.g. "$(THINGINO_DFU_VERSION)" or "v$(GO2RTC_VERSION)"
      url         – raw tarball URL (when site_method == 'url')
      source      – explicit _SOURCE value, if any
    """

    # Find the package prefix – the first _VERSION assignment
    m = re.search(r'^(\w+)_VERSION\s*[+:?]?=\s*(.+)$', text, re.MULTILINE)
    if not m:
        raise SystemExit("cannot find _VERSION assignment in .mk file")
    prefix = m.group(1)
    version = m.group(2).strip()

    info = {"prefix": prefix, "version": version}

    # _SITE using github helper – must be checked BEFORE generic URL pattern
    m = re.search(
        rf'^{prefix}_SITE\s*[+:?]?=\s*\$\(call\s+github,(\S+),(\S+),(.+)\)',
        text,
    )
    if m:
        info["site_method"] = "github"
        info["gh_owner"] = m.group(1)
        info["gh_repo"] = m.group(2)
        info["gh_tag_expr"] = m.group(3).strip()
        return info

    # _SITE_METHOD
    m = re.search(
        rf'^{prefix}_SITE_METHOD\s*[+:?]?=\s*(\S+)', text, re.MULTILINE
    )
    if m:
        method = m.group(1)
        if method == "git":
            info["site_method"] = "git"
            m2 = re.search(
                rf'^{prefix}_SITE\s*[+:?]?=\s*(\S+)', text, re.MULTILINE
            )
            if m2:
                info["git_url"] = m2.group(1)
            return info

    # _SITE as raw URL (catch-all)
    m = re.search(rf'^{prefix}_SITE\s*[+:?]?=\s*(\S+)', text, re.MULTILINE)
    if m:
        info["site_method"] = "url"
        info["url"] = m.group(1)

    # _SOURCE override
    m = re.search(
        rf'^{prefix}_SOURCE\s*[+:?]?=\s*(\S+)', text, re.MULTILINE
    )
    if m:
        info["source"] = m.group(1)

    return info


def resolve_github_tag(info: dict, new_version: str) -> str:
    """Resolve the actual git tag from the github helper's tag expression."""
    expr = info["gh_tag_expr"]
    # $(PREFIX_VERSION) → literal version
    if re.match(rf'^\$\({info["prefix"]}_VERSION\)$', expr):
        return new_version
    # v$(PREFIX_VERSION) → v + version
    m = re.match(rf'^v\$\({info["prefix"]}_VERSION\)$', expr)
    if m:
        return f"v{new_version}"
    # Something else – try substituting
    result = re.sub(
        rf'\$\({info["prefix"]}_VERSION\)', new_version, expr
    )
    return result


def github_download_url(owner: str, repo: str, tag: str) -> str:
    return f"https://github.com/{owner}/{repo}/archive/refs/tags/{tag}.tar.gz"


def tarball_name(pkg_name: str, version: str) -> str:
    """Buildroot tarball filename for github helper: <pkg>-<version>.tar.gz."""
    return f"{pkg_name}-{version}.tar.gz"


def hash_file_path(pkg_dir: Path, pkg_name: str) -> Path:
    return pkg_dir / f"{pkg_name}.hash"


def extract_tarball_name_from_hash(hash_text: str) -> str | None:
    """Return the tarball basename from a .hash file, or None."""
    m = re.search(r'^sha256\s+[0-9a-f]+\s+(.+\.tar\.gz)', hash_text, re.MULTILINE)
    return m.group(1) if m else None


def download_and_hash(url: str) -> tuple[str, str]:
    """Download a tarball and return (sha256_hex, temp_file_path)."""
    tmp = tempfile.NamedTemporaryFile(suffix=".tar.gz", delete=False)
    try:
        print(f"  downloading {url} ...", file=sys.stderr)
        req = urllib.request.Request(url, headers={"User-Agent": "update-packages.py"})
        with urllib.request.urlopen(req) as resp:
            data = resp.read()
        tmp.write(data)
        tmp.close()
        sha = hashlib.sha256(data).hexdigest()
        return sha, tmp.name
    except Exception:
        tmp.close()
        os.unlink(tmp.name)
        raise


def update_mk_version(mk_path: Path, prefix: str, old_ver: str, new_ver: str):
    """Replace the version in the .mk file."""
    text = mk_path.read_text()
    # Match _VERSION = value (with optional : or + before =)
    pattern = rf'^({prefix}_VERSION\s*[+:?]?=\s*){re.escape(old_ver)}(\s*)$'
    new_text, count = re.subn(pattern, rf'\g<1>{new_ver}\g<3>', text, flags=re.MULTILINE)
    if count != 1:
        raise SystemExit(
            f"expected 1 _VERSION line matching '{old_ver}', found {count}"
        )
    mk_path.write_text(new_text)
    print(f"  updated {mk_path.relative_to(FIRMWARE_ROOT)}: {old_ver} → {new_ver}")


def update_hash_file(
    hash_path: Path,
    old_tarball: str,
    new_tarball: str,
    new_sha: str,
):
    """Update the hash entry for the tarball."""
    if hash_path.exists():
        text = hash_path.read_text()
        # Replace existing entry
        old_pattern = re.escape(old_tarball)
        if old_tarball not in text:
            raise SystemExit(
                f"tarball '{old_tarball}' not found in {hash_path}"
            )
        new_text = text.replace(old_tarball, new_tarball)
        # Also need to update the hash
        new_text = re.sub(
            rf'^(sha256\s+)[0-9a-f]+(\s+{re.escape(new_tarball)})$',
            rf'\g<1>{new_sha}\g<2>',
            new_text,
            flags=re.MULTILINE,
        )
    else:
        new_text = (
            "# Locally calculated\n"
            f"sha256  {new_sha}  {new_tarball}\n"
        )
    hash_path.write_text(new_text)
    print(f"  updated {hash_path.relative_to(FIRMWARE_ROOT)}")


def update_package(name: str, new_version: str):
    """Update a single package to *new_version*."""
    pkg_dir = find_package_dir(name)
    mk_path = pkg_dir / f"{name}.mk"
    if not mk_path.exists():
        raise SystemExit(f"{mk_path} not found")

    mk_text = read_mk(mk_path)
    info = parse_mk(mk_text)
    old_version = info["version"]
    prefix = info["prefix"]

    if old_version == new_version:
        print(f"  {name}: already at {new_version}, nothing to do")
        return

    method = info.get("site_method")
    if method == "git":
        print(f"{name}: git package – updating version only ({old_version} → {new_version})")
        update_mk_version(mk_path, prefix, old_version, new_version)
        return

    if method == "github":
        new_tag = resolve_github_tag(info, new_version)

        hash_path = hash_file_path(pkg_dir, name)
        old_tarball = tarball_name(name, old_version)
        new_tarball = tarball_name(name, new_version)

        # If a .hash exists, use its exact tarball name (case may differ)
        if hash_path.exists():
            existing = extract_tarball_name_from_hash(hash_path.read_text())
            if existing:
                old_tarball = existing
                new_tarball = existing.replace(old_version, new_version)

        url = github_download_url(info["gh_owner"], info["gh_repo"], new_tag)

        print(f"{name}: {old_version} → {new_version} (github tarball, tag={new_tag})")

        try:
            new_sha, tmp_path = download_and_hash(url)
        except Exception as e:
            raise SystemExit(f"failed to download {url}: {e}")

        try:
            update_mk_version(mk_path, prefix, old_version, new_version)
            update_hash_file(hash_path, old_tarball, new_tarball, new_sha)
        finally:
            os.unlink(tmp_path)

        print(f"  sha256: {new_sha}")
        return

    # Unknown or URL-based – update version only, warn about hash
    print(f"{name}: {old_version} → {new_version} (unknown download method '{method}' – hash NOT updated)")
    update_mk_version(mk_path, prefix, old_version, new_version)


def cmd_update(args: list[str]):
    if len(args) != 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <package-name> <new-version>")
    update_package(args[0], args[1])


def cmd_check():
    """Scan all packages for hash mismatches."""
    errors = 0
    pkgs_dir = FIRMWARE_ROOT / "package"
    for pkg_dir in sorted(pkgs_dir.iterdir()):
        if not pkg_dir.is_dir():
            continue
        name = pkg_dir.name
        mk_path = pkg_dir / f"{name}.mk"
        if not mk_path.exists():
            continue

        try:
            info = parse_mk(read_mk(mk_path))
        except SystemExit:
            continue

        method = info.get("site_method")
        if method != "github":
            continue

        hash_path = hash_file_path(pkg_dir, name)
        if not hash_path.exists():
            print(f"MISSING HASH: {name} (version={info['version']})")
            errors += 1
            continue

        tarball_in_hash = extract_tarball_name_from_hash(hash_path.read_text())
        if not tarball_in_hash:
            print(f"NO TARBALL ENTRY: {name} ({hash_path})")
            errors += 1
            continue

        expected = tarball_name(name, info["version"])
        # Allow case-insensitive match
        if tarball_in_hash.lower() != expected.lower():
            print(
                f"MISMATCH: {name} – mk version={info['version']}, "
                f"hash expects={tarball_in_hash}, computed={expected}"
            )
            errors += 1

    if errors:
        print(f"\n{errors} issue(s) found.")
        sys.exit(1)
    else:
        print("All release packages OK.")


def main():
    if len(sys.argv) < 2:
        raise SystemExit(f"Usage: {sys.argv[0]} <package-name> <new-version>")
    if sys.argv[1] == "--check":
        cmd_check()
    else:
        cmd_update(sys.argv[1:])


if __name__ == "__main__":
    main()
