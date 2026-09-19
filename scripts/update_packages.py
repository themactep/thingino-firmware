#!/usr/bin/env python3

import hashlib
import os
import re
import signal
import sys
import shutil
import tempfile
import subprocess
import argparse
import fnmatch
from pathlib import Path
from typing import Optional, Tuple, List, Callable

BLUE = "\033[0;34m"
YELLOW = "\033[1;33m"
RED = "\033[0;31m"
GREEN = "\033[0;32m"
NC = "\033[0m"

SCRIPT_DIR = Path(__file__).resolve().parent
PROJECT_ROOT = SCRIPT_DIR.parent
PACKAGE_DIR = PROJECT_ROOT / "package"

TOTAL_PACKAGES_SCANNED = 0
PACKAGES_WITH_UPDATES = 0
PACKAGES_UPDATED = 0
UPDATED_PACKAGES: List[str] = []

# Logging level: INFO=20 (default), DEBUG=10
LOG_LEVEL = 20
# Dry-run mode: when True, do not prompt or modify files
DRY_RUN = False
# When True, resolve a missing _SITE_BRANCH from the remote default branch and
# offer to record it (each write is confirmed, defaulting to No)
INFER_BRANCH = False
# Packages skipped because they pin a commit hash but declare no branch
SKIPPED_NO_BRANCH: List[str] = []

HASH_RE = re.compile(r"^[a-f0-9]{7,40}$")
SOURCE_RE = re.compile(r'\bsource\s+"([^"]*Config\.in\.host)"')
BR2_VAR_RE = re.compile(r'\$\(?BR2_EXTERNAL_\w+\)?')
GITHUB_CALL_RE = re.compile(
    r'^\$\(call\s+github,\s*([^,]+),\s*([^,]+?)(?:\s*,\s*(.+?))?\s*\)$'
)
GITHUB_URL_RE = re.compile(r'github\.com/([^/]+)/([^/]+?)(?:\.git|/|$)')


def log_debug(msg: str) -> None:
    if LOG_LEVEL <= 10:
        print(f"{BLUE}[DEBUG]{NC} {msg}", file=sys.stderr)


def log_info(msg: str) -> None:
    if LOG_LEVEL <= 20:
        print(f"{BLUE}[INFO]{NC} {msg}", file=sys.stderr)


def log_warn(msg: str) -> None:
    print(f"{YELLOW}[WARN]{NC} {msg}", file=sys.stderr)


def log_error(msg: str) -> None:
    print(f"{RED}[ERROR]{NC} {msg}", file=sys.stderr)


def log_success(msg: str) -> None:
    print(f"{GREEN}[SUCCESS]{NC} {msg}", file=sys.stderr)


def run_git(args: List[str], cwd: Optional[Path] = None, timeout: int = 60) -> Tuple[int, str, str]:
    try:
        proc = subprocess.Popen(
            ["git", *args],
            cwd=cwd,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            start_new_session=True,
        )
        try:
            out, err = proc.communicate(timeout=timeout)
        except subprocess.TimeoutExpired:
            # git spawns helper processes (git remote-https, git-remote-https)
            # that inherit our stdout/stderr pipes. Killing only the git
            # parent would leave those helpers holding the write end open, so
            # communicate() would never see EOF and the timeout would be
            # ineffective. Kill the whole process group instead.
            try:
                os.killpg(proc.pid, signal.SIGKILL)
            except ProcessLookupError:
                pass
            out, err = proc.communicate()
            return 124, "", "timeout"
        return proc.returncode, (out or "").strip(), (err or "").strip()
    except FileNotFoundError:
        return 127, "", "git not found"


def is_valid_hash(s: str) -> bool:
    return bool(HASH_RE.match(s))


def hashes_match(lhs: str, rhs: str) -> bool:
    """
    Treat abbreviated and full commit hashes as equal when one is a prefix of the other.
    """
    return lhs == rhs or lhs.startswith(rhs) or rhs.startswith(lhs)


def get_short_hash(h: str) -> str:
    return h[:7]


# ── Release bundle helpers ──────────────────────────────────────────────

def _build_tag_template(version_arg: str) -> str:
    """
    Convert a ``$(call github)`` version argument into a template string
    with ``{v}`` as the version placeholder.
    Examples: ``v$(GO2RTC_VERSION)`` → ``v{v}``,
              ``$(USRSCTP_VERSION)`` → ``{v}``,
              ``v$(THINGINO_WOLFSSL_VERSION)-stable`` → ``v{v}-stable``.
    """
    return re.sub(r'\$\([^)]*_VERSION\)|\$\(VERSION\)', '{v}', version_arg)


def apply_tag_template(template: str, version: str) -> str:
    """Apply a tag template to produce the full git tag."""
    return template.replace('{v}', version)


def extract_version_from_tag(template: str, tag: str) -> Optional[str]:
    """
    Given a tag template (with ``{v}`` placeholder) and a full git tag,
    extract the version portion.
    Returns ``None`` if the tag does not match the template.
    """
    prefix, suffix = template.split('{v}', 1)
    if not tag.startswith(prefix):
        return None
    inner = tag[len(prefix):]
    if suffix:
        if not inner.endswith(suffix):
            return None
        inner = inner[:-len(suffix)]
    return inner


def extract_github_info(site: str, pkg_upper: str, source: Optional[str] = None) -> Optional[Tuple[str, str, str]]:
    """
    Extract (user, repo, tag_template) from a ``_SITE`` value (and optionally
    ``_SOURCE``) for GitHub-hosted projects.

    The tag_template uses ``{v}`` as a placeholder for the version string.
    Returns ``None`` if the site does not appear to be GitHub-hosted.
    """
    m = GITHUB_CALL_RE.match(site)
    if m:
        user = m.group(1).strip()
        repo = m.group(2).strip()
        version_arg = m.group(3).strip() if m.group(3) else None
        if version_arg:
            template = _build_tag_template(version_arg)
        else:
            template = '{v}'
        return user, repo, template

    # Direct GitHub URL (e.g. https://github.com/user/repo)
    m = GITHUB_URL_RE.search(site)
    if m:
        user = m.group(1)
        repo = m.group(2).rstrip('/')
        # If _SOURCE is set, try to derive the template from it
        if source:
            src_template = _build_tag_template(source)
            # Strip .tar.gz / .tar.xz / .zip suffixes
            src_template = re.sub(r'\.(tar\.(gz|bz2|xz|lz)|zip)$', '', src_template)
            if '{v}' in src_template:
                return user, repo, src_template
        return user, repo, '{v}'

    return None


def get_latest_tag(repo_url: str, current_tag: str, template: Optional[str] = None) -> Optional[str]:
    """
    Fetch all tags from a git repo and return the most recent version tag
    that shares a version-number pattern with *current_tag* and matches the
    tag *template* (with ``{v}`` placeholder) when one is provided.

    The template matters because version tags are not always plain
    numbers or ``v``-prefixed: e.g. ``faac-$(FAAC_VERSION)`` produces
    tags like ``faac-2.1``, where the version portion is ``2.1``.
    """
    code, out, err = run_git(["ls-remote", "--tags", repo_url], timeout=120)
    if code != 0:
        log_error(f"Failed to fetch tags for {repo_url}: {err}")
        return None
    if not out:
        return None

    tags: set[str] = set()
    for line in out.splitlines():
        parts = line.split('\t')
        if len(parts) < 2:
            continue
        ref = parts[1]
        m = re.match(r'refs/tags/(.+)$', ref)
        if m:
            tag = m.group(1)
            if tag.endswith('^{}'):
                continue
            tags.add(tag)

    has_v = current_tag.startswith('v')

    candidates = []
    for tag in tags:
        # Keep the same v-prefix consistency as the current tag
        if tag.startswith('v') != has_v:
            continue
        # The version portion is whatever the template pins between its
        # static prefix/suffix; without a template the whole tag is used.
        version = extract_version_from_tag(template, tag) if template else tag
        if version is None:
            continue
        v = version[1:] if version.startswith('v') else version
        if not re.match(r'^\d+(\.\d+)*', v):
            continue
        nums = re.findall(r'\d+', v)
        candidates.append((tuple(int(n) for n in nums), tag))

    if not candidates:
        return None
    candidates.sort(key=lambda c: c[0])
    return candidates[-1][1]


def compare_tags(current: str, latest: str) -> bool:
    """
    Return ``True`` when *latest* is strictly newer than *current* by
    numerical version-component comparison.
    """
    def vtuple(tag: str) -> tuple:
        v = tag[1:] if tag.startswith('v') else tag
        nums = re.findall(r'\d+', v)
        return tuple(int(n) for n in nums)
    return vtuple(latest) > vtuple(current)


def check_git_working_directory() -> bool:
    """
    Check if the Git working directory is clean (no uncommitted changes).
    Returns True if clean, False if there are uncommitted changes.
    """
    log_debug("Checking Git working directory status")

    # Check for staged changes
    code, out, err = run_git(["diff", "--cached", "--quiet"], cwd=PROJECT_ROOT)
    if code != 0:
        log_debug("Found staged changes in working directory")
        return False

    # Check for unstaged changes
    code, out, err = run_git(["diff", "--quiet"], cwd=PROJECT_ROOT)
    if code != 0:
        log_debug("Found unstaged changes in working directory")
        return False

    # Check for untracked files
    code, out, err = run_git(["ls-files", "--others", "--exclude-standard"], cwd=PROJECT_ROOT)
    if code == 0 and out.strip():
        log_debug("Found untracked files in working directory")
        return False

    log_debug("Git working directory is clean")
    return True


def download_release_tarball_hash(repo_url: str, tag: str, package_name: str, version: str) -> Optional[Tuple[str, str]]:
    """
    Download the GitHub release tarball for *tag* and compute its SHA-256.
    Returns ``(sha256_hex, tarball_filename)``, or ``None`` on failure.
    """
    m = re.match(r'https://github\.com/([^/]+)/([^/]+?)(?:\.git)?$', repo_url)
    if not m:
        log_error(f"Cannot parse GitHub URL for tarball download: {repo_url}")
        return None
    user, repo = m.group(1), m.group(2)
    archive_url = f"https://github.com/{user}/{repo}/archive/refs/tags/{tag}.tar.gz"
    tarball_name = f"{package_name}-{version}.tar.gz"
    log_debug(f"Downloading {archive_url} to compute hash...")
    try:
        result = subprocess.run(
            ["curl", "-sL", "--max-time", "60", archive_url],
            capture_output=True, timeout=90,
        )
        if result.returncode != 0:
            log_error(f"Failed to download {archive_url}: {result.stderr.decode(errors='ignore')[:200]}")
            return None
    except Exception as e:
        log_error(f"Failed to download {archive_url}: {e}")
        return None
    sha = hashlib.sha256(result.stdout).hexdigest()
    log_debug(f"Computed SHA-256 for {tarball_name}: {sha}")
    return sha, tarball_name


def update_package_hash_file(mk_path: Path, tarball_name: str, sha256_hash: str) -> bool:
    """
    Add or replace a SHA-256 entry in the package's ``.hash`` file.
    The hash file is expected to live next to the ``.mk`` file with
    the same basename (i.e. ``<pkg>/<pkg>.hash``).
    """
    hash_path = mk_path.parent / f"{mk_path.parent.name}.hash"
    new_entry = f"sha256  {sha256_hash}  {tarball_name}"

    if hash_path.exists():
        try:
            lines = hash_path.read_text(encoding='utf-8', errors='ignore').splitlines()
        except Exception as e:
            log_error(f"Failed to read {hash_path}: {e}")
            return False
    else:
        lines = ["# Locally calculated"]

    # Replace existing entry for the same tarball, if present
    entry_re = re.compile(rf"^sha256\s+[a-f0-9]{{64}}\s+{re.escape(tarball_name)}\s*$")
    for i, line in enumerate(lines):
        if entry_re.match(line):
            lines[i] = new_entry
            try:
                hash_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
                log_success(f"Updated hash in {hash_path.name} for {tarball_name}")
                return True
            except Exception as e:
                log_error(f"Failed to write {hash_path}: {e}")
                return False

    # New entry — insert after the last tarball-hash line (skip license hashes)
    last_idx = -1
    for i, line in enumerate(lines):
        if line.startswith("sha256  ") and "LICENSE" not in line:
            last_idx = i

    if last_idx >= 0:
        lines.insert(last_idx + 1, new_entry)
    else:
        # No existing tarball hashes — insert after the leading comment block
        inserted = False
        for i, line in enumerate(lines):
            if line.strip().startswith("#") and "license" not in line.lower():
                j = i + 1
                while j < len(lines) and not lines[j].strip():
                    j += 1
                lines.insert(j, new_entry)
                inserted = True
                break
        if not inserted:
            lines.append(new_entry)

    try:
        hash_path.write_text('\n'.join(lines) + '\n', encoding='utf-8')
        log_success(f"Added hash to {hash_path.name} for {tarball_name}")
        return True
    except Exception as e:
        log_error(f"Failed to write {hash_path}: {e}")
        return False


def create_package_commit(package_name: str, mk_path: Path, old_hash: str, new_hash: str, commit_log: List[str],
                          note: Optional[str] = None) -> bool:
    """
    Create a Git commit for a package update.
    Returns True if successful, False if failed.
    """

    log_debug(f"Creating Git commit for package {package_name}")

    # Stage the modified .mk file
    relative_mk_path = mk_path.relative_to(PROJECT_ROOT)
    code, out, err = run_git(["add", str(relative_mk_path)], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to stage {relative_mk_path}: {err}")
        return False

    # Stage the .hash file if it exists (may have been updated with a new tarball hash)
    hash_path = mk_path.parent / f"{mk_path.parent.name}.hash"
    if hash_path.exists():
        relative_hash_path = hash_path.relative_to(PROJECT_ROOT)
        run_git(["add", str(relative_hash_path)], cwd=PROJECT_ROOT)

    # Create commit message
    old_short = get_short_hash(old_hash) if is_valid_hash(old_hash) else old_hash
    new_short = get_short_hash(new_hash) if is_valid_hash(new_hash) else new_hash

    commit_title = f"package/{package_name}: update to {new_short}"

    commit_body_lines = [
        "",
        f"Update {package_name} from {old_short} to {new_short}",
        "",
        f"Hash change: {old_hash} -> {new_hash}",
        ""
    ]

    if note:
        commit_body_lines.extend([note, ""])

    if commit_log:
        commit_body_lines.extend([
            "Changelog:",
            ""
        ])
        for line in commit_log:
            commit_body_lines.append(f"  {line}")
    else:
        commit_body_lines.append("(No changelog available)")

    commit_message = commit_title + "\n" + "\n".join(commit_body_lines)

    # Create the commit
    code, out, err = run_git(["commit", "-m", commit_message], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to create commit for {package_name}: {err}")
        # Unstage the file
        run_git(["reset", "HEAD", str(relative_mk_path)], cwd=PROJECT_ROOT)
        return False

    log_success(f"Created commit for {package_name}: {commit_title}")
    return True


def create_branch_only_commit(package_name: str, mk_path: Path, branch: str) -> bool:
    """Commit a _SITE_BRANCH-only change (the pinned hash was already at the tip)."""
    relative_mk_path = mk_path.relative_to(PROJECT_ROOT)
    code, out, err = run_git(["add", str(relative_mk_path)], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to stage {relative_mk_path}: {err}")
        return False

    commit_title = f"package/{package_name}: track branch {branch}"
    commit_message = (
        f"{commit_title}\n\n"
        f"Add _SITE_BRANCH = {branch} so updates are visible to the package update script.\n"
    )
    code, out, err = run_git(["commit", "-m", commit_message], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to create commit for {package_name}: {err}")
        run_git(["reset", "HEAD", str(relative_mk_path)], cwd=PROJECT_ROOT)
        return False

    log_success(f"Created commit for {package_name}: {commit_title}")
    return True


def parse_mk_file(mk_path: Path) -> Optional[Tuple[str, str, str, str]]:
    """
    Return (package_name, repo_url, branch, version_hash) if git-sourced with
    static hash and an explicit branch (rolling commit), else None.
    """
    pkg_dir = mk_path.parent
    package_name = pkg_dir.name
    pkg_upper = package_name.upper().replace('-', '_')

    site_method = None
    site = None
    branch = None
    version = None

    try:
        with mk_path.open('r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        log_warn(f"Failed to read {mk_path}: {e}")
        return None

    # Regexes
    re_site_method = re.compile(rf"^{re.escape(pkg_upper)}_SITE_METHOD\s*=\s*(.+)$")
    re_site = re.compile(rf"^{re.escape(pkg_upper)}_SITE\s*=\s*(.+)$")
    re_site_branch = re.compile(rf"^{re.escape(pkg_upper)}_SITE_BRANCH\s*=\s*(.+)$")
    re_branch_alt = re.compile(rf"^{re.escape(pkg_upper)}_BRANCH\s*=\s*(.+)$")
    re_version = re.compile(rf"^{re.escape(pkg_upper)}_VERSION\s*=\s*(.+)$")

    for line in lines:
        line = line.rstrip('\n')
        m = re_site_method.match(line)
        if m:
            site_method = m.group(1).strip().strip('"')
            continue
        m = re_site_branch.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue
        m = re_branch_alt.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue
        m = re_version.match(line)
        if m and version is None:
            v = m.group(1).strip().strip('"')
            version = v
            continue
        m = re_site.match(line)
        if m and site is None:
            site = m.group(1).strip().strip('"')
            continue

    # Handle $(call github,user,repo[,version]) helper
    if site_method != 'git' and site and site.startswith('$('):
        m = re.match(r'^\$\(call\s+github,\s*([^,]+),\s*([^,]+)', site)
        if m:
            site_method = 'git'
            site = f"https://github.com/{m.group(1).strip()}/{m.group(2).strip()}.git"

    # Filter conditions
    if site_method != 'git':
        return None
    if not site or not version:
        return None
    if '$(' in version:  # dynamic shell usage
        return None
    # Some packages use tags like v0.86; only process true commit hashes
    if not is_valid_hash(version):
        return None

    # Only consider packages that explicitly set a branch (rolling commits)
    if branch is None:
        return None
    return package_name, site, branch, version


def parse_mk_file_no_branch(mk_path: Path) -> Optional[Tuple[str, str, str]]:
    """
    Return (package_name, repo_url, version_hash) for a git-sourced package
    that pins a bare commit hash but declares no branch. These are invisible
    to parse_mk_file() and were previously skipped without any notice.
    """
    pkg_dir = mk_path.parent
    package_name = pkg_dir.name
    pkg_upper = package_name.upper().replace('-', '_')

    site_method = None
    site = None
    branch = None
    version = None

    try:
        with mk_path.open('r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception:
        return None

    re_site_method = re.compile(rf"^{re.escape(pkg_upper)}_SITE_METHOD\s*=\s*(.+)$")
    re_site = re.compile(rf"^{re.escape(pkg_upper)}_SITE\s*=\s*(.+)$")
    re_site_branch = re.compile(rf"^{re.escape(pkg_upper)}_SITE_BRANCH\s*=\s*(.+)$")
    re_branch_alt = re.compile(rf"^{re.escape(pkg_upper)}_BRANCH\s*=\s*(.+)$")
    re_version = re.compile(rf"^{re.escape(pkg_upper)}_VERSION\s*=\s*(.+)$")

    for line in lines:
        line = line.rstrip('\n')
        m = re_site_method.match(line)
        if m:
            site_method = m.group(1).strip().strip('"')
            continue
        m = re_site_branch.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue
        m = re_branch_alt.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue
        m = re_version.match(line)
        if m and version is None:
            version = m.group(1).strip().strip('"')
            continue
        m = re_site.match(line)
        if m and site is None:
            site = m.group(1).strip().strip('"')
            continue

    if site_method != 'git' and site and site.startswith('$('):
        m = re.match(r'^\$\(call\s+github,\s*([^,]+),\s*([^,]+)', site)
        if m:
            site_method = 'git'
            site = f"https://github.com/{m.group(1).strip()}/{m.group(2).strip()}.git"

    if site_method != 'git' or not site or not version:
        return None
    if '$(' in version or not is_valid_hash(version):
        return None
    if branch is not None:
        return None
    return package_name, site, version


def looks_like_release_branch(branch: str) -> bool:
    """
    Heuristic: release/version refs (v5.3.9, 1.2, release-3.4, stable-2024) are
    typically pinned, not tracked. Development branches (master, main, dev,
    next, openwrt-23.05) are named descriptively.
    """
    if re.match(r'^v?\d+\.\d+', branch):
        return True
    if re.match(r'^(release|stable)[-_]?\d*\.?\d*$', branch, re.IGNORECASE):
        return True
    return False


def get_remote_default_branch(repo_url: str) -> Optional[str]:
    """
    Resolve the remote's default branch from the HEAD symref.
    Returns None when HEAD is detached or the symref is unavailable, so
    callers do not guess a branch name.
    """
    log_debug(f"Resolving default branch for {repo_url}")
    code, out, err = run_git(["ls-remote", "--symref", repo_url, "HEAD"])
    if code != 0 or not out:
        log_warn(f"Could not resolve default branch for {repo_url}: {err.strip()}")
        return None
    for line in out.splitlines():
        m = re.match(r'^ref:\s+refs/heads/(\S+)\s+HEAD$', line.strip())
        if m:
            return m.group(1)
    log_warn(f"Remote HEAD is not a branch symref for {repo_url} (detached or tagged)")
    return None


def hash_on_branch(repo_url: str, branch: str, commit_hash: str) -> bool:
    """Return True if commit_hash is reachable from the branch tip."""
    code, out, err = run_git(["ls-remote", repo_url, f"refs/heads/{branch}"])
    if code != 0 or not out:
        return False
    remote_hash = out.splitlines()[0].split('\t')[0]
    if hashes_match(commit_hash, remote_hash):
        return True
    # The pinned commit may be an ancestor; a shallow fetch is the cheap check.
    tmpdir = Path(tempfile.mkdtemp(prefix='up-check-'))
    try:
        run_git(["init", "--quiet"], cwd=tmpdir)
        run_git(["remote", "add", "origin", repo_url], cwd=tmpdir)
        code, _, err = run_git(
            ["fetch", "--quiet", "--depth=200", "--filter=blob:none", "origin", branch],
            cwd=tmpdir, timeout=180,
        )
        if code != 0:
            log_debug(f"  fetch of {branch} failed: {err.strip()}")
            return False
        code, _, _ = run_git(
            ["merge-base", "--is-ancestor", commit_hash, "FETCH_HEAD"], cwd=tmpdir, timeout=60,
        )
        return code == 0
    except Exception as e:
        log_debug(f"  ancestry check failed: {e}")
        return False
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def add_site_branch(mk_path: Path, package_name: str, branch: str) -> bool:
    """Insert <PKG>_SITE_BRANCH = <branch> after the _SITE_METHOD = git line."""
    pkg_upper = package_name.upper().replace('-', '_')
    try:
        text = mk_path.read_text(encoding='utf-8', errors='ignore')
    except Exception as e:
        log_error(f"Failed to read {mk_path}: {e}")
        return False

    method_re = re.compile(
        rf"^(?P<indent>[ \t]*)(?P<var>{re.escape(pkg_upper)}_SITE_METHOD\s*=\s*git)[ \t]*$",
        re.MULTILINE,
    )
    m = method_re.search(text)
    if not m:
        log_error(f"No '{pkg_upper}_SITE_METHOD = git' line found in {mk_path}")
        return False

    new_text = text[:m.end()] + f"\n{m.group('indent')}{pkg_upper}_SITE_BRANCH = {branch}" + text[m.end():]
    try:
        mk_path.write_text(new_text, encoding='utf-8')
        log_success(f"Added {pkg_upper}_SITE_BRANCH = {branch} to {mk_path}")
        return True
    except Exception as e:
        log_error(f"Failed to write {mk_path}: {e}")
        try:
            mk_path.write_text(text, encoding='utf-8')  # restore
        except Exception:
            pass
        return False


def confirm(prompt: str) -> bool:
    """Ask a yes/no question, defaulting to No when not interactive."""
    try:
        if sys.stdin.isatty():
            print(prompt, end="", file=sys.stdout, flush=True)
            resp = input()
        else:
            with open("/dev/tty", "r") as tty_in, open("/dev/tty", "w") as tty_out:
                print(prompt, end="", file=tty_out, flush=True)
                resp = tty_in.readline()
        return resp.strip().lower() in ("y", "yes")
    except Exception:
        return False


def get_remote_hash(repo_url: str, branch: str) -> Optional[str]:
    log_debug(f"Checking remote hash for {repo_url} (branch: {branch})")
    code, out, err = run_git(["ls-remote", repo_url, branch])
    if code == 0 and out:
        first = out.splitlines()[0]
        rh = first.split('\t')[0]
        if is_valid_hash(rh):
            return rh
    # fallback to HEAD
    if branch != 'HEAD':
        code, out, err = run_git(["ls-remote", repo_url, "HEAD"])
        if code == 0 and out:
            first = out.splitlines()[0]
            rh = first.split('\t')[0]
            if is_valid_hash(rh):
                log_warn(f"Branch '{branch}' not found, using HEAD: {rh}")
                return rh
    log_error(f"Failed to get remote hash for {repo_url}: {err}")
    return None


def resolve_commit_hash(repo_dir: Path, commitish: str) -> Optional[str]:
    """
    Resolve commitish to a full 40-char commit hash in repo_dir.
    """
    code, out, err = run_git(["rev-parse", "--verify", f"{commitish}^{{commit}}"], cwd=repo_dir)
    if code == 0 and is_valid_hash(out) and len(out) == 40:
        return out

    if is_valid_hash(commitish) and len(commitish) < 40:
        code, out, err = run_git(["rev-list", "--all"], cwd=repo_dir, timeout=180)
        if code == 0:
            matches = [line for line in out.splitlines() if line.startswith(commitish)]
            if len(matches) == 1:
                return matches[0]
            if len(matches) > 1:
                log_warn(f"Abbreviated hash '{commitish}' is ambiguous in fetched history")
    return None


def get_commit_log(repo_url: str, old_hash: str, new_hash: str, branch: str = "HEAD") -> List[str]:
    log_debug(f"Getting commit log for {repo_url} from {old_hash} to {new_hash} (branch: {branch})")
    tmpdir = Path(tempfile.mkdtemp(prefix="pkg-git-"))
    try:
        # Lightweight repo: init + fetch only required commits
        code, out, err = run_git(["init", "-q"], cwd=tmpdir)
        if code != 0:
            log_error(f"Failed to init git repo in {tmpdir}: {err}")
            return []
        code, out, err = run_git(["remote", "add", "origin", repo_url], cwd=tmpdir)
        if code != 0:
            log_error(f"Failed to add remote: {err}")
            return []

        # Fetch branch history and the remote tip without blobs for speed.
        # This gives us enough history to resolve abbreviated hashes locally.
        run_git(["fetch", "--quiet", "--depth=200", "--filter=blob:none", "origin", branch], cwd=tmpdir, timeout=180)
        run_git(["fetch", "--quiet", "--depth=200", "--filter=blob:none", "origin", new_hash], cwd=tmpdir, timeout=180)

        resolved_new_hash = resolve_commit_hash(tmpdir, new_hash)
        if not resolved_new_hash:
            log_error(f"Failed to resolve new hash '{new_hash}' in fetched history")
            return []

        resolved_old_hash = resolve_commit_hash(tmpdir, old_hash)
        if not resolved_old_hash:
            # Short hashes may point to commits older than the initial shallow depth.
            # Deepen progressively to avoid cloning the full history in the common case.
            for deepen in [400, 800, 1600, 3200, 6400]:
                run_git(["fetch", "--quiet", f"--deepen={deepen}", "--filter=blob:none", "origin", branch], cwd=tmpdir, timeout=180)
                resolved_old_hash = resolve_commit_hash(tmpdir, old_hash)
                if resolved_old_hash:
                    break

        if not resolved_old_hash:
            if is_valid_hash(old_hash) and len(old_hash) == 40:
                run_git(["fetch", "--quiet", "--filter=blob:none", "origin", old_hash], cwd=tmpdir, timeout=180)
                resolved_old_hash = resolve_commit_hash(tmpdir, old_hash)

        if not resolved_old_hash:
            log_warn(
                f"Could not resolve old hash '{old_hash}' in fetched history; showing recent commits up to {get_short_hash(resolved_new_hash)}"
            )
            code, out, err = run_git([
                "log", "--pretty=format:%h: %s", "--reverse", "-n", "30", resolved_new_hash
            ], cwd=tmpdir, timeout=90)
            if code == 0:
                lines = [line for line in out.splitlines() if line.strip()]
                if lines:
                    return [f"(old hash {old_hash} not found; showing latest {len(lines)} commits)"] + lines
            return []

        code, out, err = run_git([
            "log", "--pretty=format:%h: %s", "--reverse", f"{resolved_old_hash}..{resolved_new_hash}"
        ], cwd=tmpdir, timeout=90)
        if code == 0:
            return [line for line in out.splitlines() if line.strip()]
        else:
            log_error(f"Failed to get commit log between {resolved_old_hash} and {resolved_new_hash}: {err}")
            return []
    finally:
        shutil.rmtree(tmpdir, ignore_errors=True)


def update_package_mk(mk_path: Path, package_name: str, old_hash: str, new_hash: str) -> bool:
    pkg_upper = package_name.upper().replace('-', '_')
    try:
        text = mk_path.read_text(encoding='utf-8', errors='ignore')
    except Exception as e:
        log_error(f"Failed to read {mk_path}: {e}")
        return False

    # Replace only the hash value on the VERSION line
    # Match: ^PKG_VERSION\s*=\s*OLDHASH(\s*(#.*)?)$
    pattern = re.compile(rf"^(?P<prefix>{re.escape(pkg_upper)}_VERSION\s*=\s*){re.escape(old_hash)}(?P<suffix>\s*(#.*)?)$", re.MULTILINE)
    new_text, n = pattern.subn(rf"\g<prefix>{new_hash}\g<suffix>", text, count=1)
    if n == 0:
        log_error(f"Did not find a VERSION line with the old hash in {mk_path}")
        return False

    try:
        mk_path.write_text(new_text, encoding='utf-8')
        log_success(f"Updated {mk_path} with new hash: {new_hash}")
        return True
    except Exception as e:
        log_error(f"Failed to write update to {mk_path}: {e}")
        try:
            mk_path.write_text(text, encoding='utf-8')  # restore
        except Exception:
            pass
        return False


def parse_mk_file_release(mk_path: Path) -> Optional[Tuple[str, str, str, str, str, str]]:
    """
    Return ``(package_name, repo_url, tag_template, current_tag, raw_version, branch)``
    if the package fetches a GitHub release bundle (via ``$(call github)``,
    ``_SITE_METHOD = git`` with a tag, or a direct GitHub archive URL).

    Returns ``None`` for packages that use commit hashes (handled by
    ``parse_mk_file``), non-GitHub URLs, or packages that cannot be parsed.
    """
    pkg_dir = mk_path.parent
    package_name = pkg_dir.name
    pkg_upper = package_name.upper().replace('-', '_')

    site_method = None
    site = None
    version = None
    source = None
    branch = None

    try:
        with mk_path.open('r', encoding='utf-8', errors='ignore') as f:
            lines = f.readlines()
    except Exception as e:
        log_warn(f"Failed to read {mk_path}: {e}")
        return None

    re_site_method = re.compile(rf"^{re.escape(pkg_upper)}_SITE_METHOD\s*=\s*(.+)$")
    re_site = re.compile(rf"^{re.escape(pkg_upper)}_SITE\s*=\s*(.+)$")
    re_version = re.compile(rf"^{re.escape(pkg_upper)}_VERSION\s*=\s*(.+)$")
    re_source = re.compile(rf"^{re.escape(pkg_upper)}_SOURCE\s*=\s*(.+)$")
    re_site_branch = re.compile(rf"^{re.escape(pkg_upper)}_SITE_BRANCH\s*=\s*(.+)$")
    re_branch_alt = re.compile(rf"^{re.escape(pkg_upper)}_BRANCH\s*=\s*(.+)$")

    for line in lines:
        line = line.rstrip('\n')
        m = re_site_method.match(line)
        if m:
            site_method = m.group(1).strip().strip('"')
            continue
        m = re_site.match(line)
        if m and site is None:
            site = m.group(1).strip().strip('"')
            continue
        m = re_version.match(line)
        if m and version is None:
            v = m.group(1).strip().strip('"')
            version = v
            continue
        m = re_source.match(line)
        if m and source is None:
            source = m.group(1).strip().strip('"')
            continue
        m = re_site_branch.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue
        m = re_branch_alt.match(line)
        if m and branch is None:
            branch = m.group(1).strip().strip('"')
            continue

    if not site or not version:
        return None
    if '$(' in version:
        return None

    # Skip git packages with commit hashes — handled by parse_mk_file()
    if site_method == 'git' and is_valid_hash(version):
        return None

    # Skip local packages
    if site_method == 'local':
        return None

    gh_info = extract_github_info(site, pkg_upper, source)
    if not gh_info:
        return None

    user, repo, tag_template = gh_info
    repo_url = f"https://github.com/{user}/{repo}.git"
    current_tag = apply_tag_template(tag_template, version)

    return package_name, repo_url, tag_template, current_tag, version, (branch or 'HEAD')


def prompt_yes_no(package_name: str, old_hash: str, new_hash: str) -> bool:
    old_short = get_short_hash(old_hash) if is_valid_hash(old_hash) else old_hash
    new_short = get_short_hash(new_hash) if is_valid_hash(new_hash) else new_hash
    prompt = (
        f"{YELLOW}Update package {BLUE}{package_name}{YELLOW} from {RED}{old_short}{YELLOW} "
        f"to {GREEN}{new_short}{YELLOW}? [y/N]: {NC}"
    )
    # Prefer reading/writing to the controlling TTY so prompts work even if stdin is piped
    try:
        if sys.stdin.isatty():
            # Keep prompt on STDOUT to appear after the update block
            print(prompt, end="", file=sys.stdout, flush=True)
            resp = input()
        else:
            with open("/dev/tty", "r") as tty_in, open("/dev/tty", "w") as tty_out:
                print(prompt, end="", file=tty_out, flush=True)
                resp = tty_in.readline()
        return resp.strip().lower() in ("y", "yes")
    except Exception:
        # Non-interactive environment; default to "No"
        return False


def process_package_release(mk_path: Path, package_name: str, repo_url: str,
                            tag_template: str, current_tag: str, raw_version: str,
                            branch: str = 'HEAD') -> None:
    global PACKAGES_WITH_UPDATES, PACKAGES_UPDATED

    log_info(f"Processing package (release bundle): {package_name}")
    log_debug(f"  Repository: {repo_url}")
    log_debug(f"  Current tag: {current_tag}")

    latest_tag = get_latest_tag(repo_url, current_tag, tag_template)
    if not latest_tag:
        # No tags found — fall back to hash-based comparison if version is a commit hash
        if is_valid_hash(raw_version) and raw_version != 'HEAD':
            log_warn(f"No version tags found for {package_name}, falling back to hash comparison")
            remote_hash = get_remote_hash(repo_url, branch)
            if not remote_hash:
                log_error(f"Failed to get remote hash for {package_name}")
                return

            log_debug(f"  Remote hash: {remote_hash}")

            if hashes_match(raw_version, remote_hash):
                print(package_name)
                print("---------------")
                print(repo_url)
                print(f"= {raw_version} (up to date)")
                print()
                log_debug(f"Package {package_name} is up to date")
                return

            PACKAGES_WITH_UPDATES += 1

            print(package_name)
            print("---------------")
            print(repo_url)
            print(f"- {raw_version}")
            print(f"+ {remote_hash}")
            print()
            sys.stdout.flush()

            if DRY_RUN:
                return

            if prompt_yes_no(package_name, raw_version, remote_hash):
                if update_package_mk(mk_path, package_name, raw_version, remote_hash):
                    # Rolling-commit (git repo) packages must NOT get a .hash file.
                    # buildroot validates git archives by the -git<N> archive name
                    # (BR_FMT_VERSION_git), which never matches a hash recorded here
                    # as <pkg>-<version>.tar.gz - a hash entry with a git commit as
                    # the version is meaningless and breaks the download step.
                    # Only release-tarball (tag) packages get a hash (see the
                    # download_release_tarball_hash call in the tag branch above).
                    log_lines = get_commit_log(repo_url, raw_version, remote_hash, branch)
                    if create_package_commit(package_name, mk_path, raw_version, remote_hash, log_lines):
                        PACKAGES_UPDATED += 1
                        UPDATED_PACKAGES.append(f"{package_name}:{get_short_hash(raw_version)}->{get_short_hash(remote_hash)}")
            return

        log_warn(f"No version tags found for {package_name} (repo may use rolling commits)")
        return

    log_debug(f"  Latest tag: {latest_tag}")

    if hashes_match(current_tag, latest_tag):
        print(package_name)
        print("---------------")
        print(repo_url)
        print(f"= {current_tag} (up to date)")
        print()
        log_debug(f"Package {package_name} is up to date")
        return

    if not compare_tags(current_tag, latest_tag):
        log_debug(f"Package {package_name} {current_tag} is not older than {latest_tag}")
        return

    PACKAGES_WITH_UPDATES += 1

    print(package_name)
    print("---------------")
    print(repo_url)
    print(f"- {current_tag}")
    print(f"+ {latest_tag}")
    print()
    sys.stdout.flush()

    if DRY_RUN:
        return

    if prompt_yes_no(f"{package_name} ({current_tag} → {latest_tag})", current_tag, latest_tag):
        new_version = extract_version_from_tag(tag_template, latest_tag)
        if new_version is None:
            log_error(f"Cannot extract version from tag '{latest_tag}' using template '{tag_template}'")
            return

        if update_package_mk_version(mk_path, package_name, raw_version, new_version):
            # Compute and record the tarball hash for the new version
            hash_result = download_release_tarball_hash(repo_url, latest_tag, package_name, new_version)
            if hash_result:
                sha, tarball = hash_result
                update_package_hash_file(mk_path, tarball, sha)
            else:
                log_warn(f"Could not compute tarball hash for {package_name} {new_version}; .hash file not updated")
            log_lines: List[str] = []
            if create_package_commit(package_name, mk_path, current_tag, latest_tag, log_lines):
                PACKAGES_UPDATED += 1
                UPDATED_PACKAGES.append(f"{package_name}:{current_tag}->{latest_tag}")
        else:
            log_error(f"Failed to update package {package_name}")


def update_package_mk_version(mk_path: Path, package_name: str, old_version: str, new_version: str) -> bool:
    """
    Replace the ``_VERSION`` value in a ``.mk`` file.
    Separate helper because ``update_package_mk`` logs about hashes.
    """
    pkg_upper = package_name.upper().replace('-', '_')
    try:
        text = mk_path.read_text(encoding='utf-8', errors='ignore')
    except Exception as e:
        log_error(f"Failed to read {mk_path}: {e}")
        return False

    pattern = re.compile(
        rf"^(?P<prefix>{re.escape(pkg_upper)}_VERSION\s*=\s*){re.escape(old_version)}(?P<suffix>\s*(#.*)?)$",
        re.MULTILINE,
    )
    new_text, n = pattern.subn(rf"\g<prefix>{new_version}\g<suffix>", text, count=1)
    if n == 0:
        log_error(f"Did not find a VERSION line with '{old_version}' in {mk_path}")
        return False

    try:
        mk_path.write_text(new_text, encoding='utf-8')
        log_success(f"Updated {mk_path}: {old_version} → {new_version}")
        return True
    except Exception as e:
        log_error(f"Failed to write update to {mk_path}: {e}")
        try:
            mk_path.write_text(text, encoding='utf-8')
        except Exception:
            pass
        return False


def print_summary() -> None:
    print("", file=sys.stderr)
    print(f"{BLUE}=== SUMMARY REPORT ==={NC}", file=sys.stderr)
    print(f"{BLUE}Total packages scanned:{NC} {TOTAL_PACKAGES_SCANNED}", file=sys.stderr)
    print(f"{BLUE}Packages with updates available:{NC} {PACKAGES_WITH_UPDATES}", file=sys.stderr)
    print(f"{BLUE}Packages actually updated:{NC} {PACKAGES_UPDATED}", file=sys.stderr)
    if SKIPPED_NO_BRANCH:
        print(
            f"{YELLOW}Skipped (pinned commit, no _SITE_BRANCH):{NC} "
            f"{len(SKIPPED_NO_BRANCH)}",
            file=sys.stderr,
        )
        for name in SKIPPED_NO_BRANCH:
            print(f"  {YELLOW}!{NC} {name}", file=sys.stderr)
        print(
            f"  Re-run with {GREEN}--infer-branch{NC} to resolve these branches.",
            file=sys.stderr,
        )
    if UPDATED_PACKAGES:
        print("", file=sys.stderr)
        print(f"{GREEN}Updated packages:{NC}", file=sys.stderr)
        for u in UPDATED_PACKAGES:
            print(f"  {GREEN}\u2713{NC} {u}", file=sys.stderr)
    print("", file=sys.stderr)


def process_package_no_branch(mk_path: Path, package_name: str, repo_url: str, current_hash: str) -> None:
    """
    A git package pins a commit hash but declares no _SITE_BRANCH, so its
    updates are invisible to the remote-tracking comparison. Report it loudly
    and, when --infer-branch is set, offer to resolve and record the branch.
    """
    global PACKAGES_WITH_UPDATES, PACKAGES_UPDATED

    log_warn(
        f"Package {package_name} pins a commit hash but has no _SITE_BRANCH; "
        "updates cannot be tracked"
    )
    SKIPPED_NO_BRANCH.append(package_name)

    if not INFER_BRANCH:
        log_info(
            f"  Re-run with --infer-branch to resolve the branch for {package_name}"
        )
        return

    branch = get_remote_default_branch(repo_url)
    if not branch:
        log_warn(f"  Could not determine a default branch for {package_name}; leaving as-is")
        return

    if looks_like_release_branch(branch):
        log_warn(
            f"  Remote default branch '{branch}' for {package_name} looks like a "
            "release ref, not a development branch. Set _SITE_BRANCH manually if "
            "it really is a rolling branch."
        )
        return

    if not hash_on_branch(repo_url, branch, current_hash):
        log_warn(
            f"  Pinned hash {get_short_hash(current_hash)} is not an ancestor of "
            f"'{branch}' for {package_name}; this looks like a pinned release, not a "
            "rolling branch. Set _SITE_BRANCH manually if it really is one."
        )
        return

    remote_hash = get_remote_hash(repo_url, branch)
    behind = bool(remote_hash) and not hashes_match(current_hash, remote_hash)
    pkg_upper = package_name.upper().replace('-', '_')

    print(package_name)
    print("---------------")
    print(repo_url)
    print(f"+ {pkg_upper}_SITE_BRANCH = {branch}")
    if behind:
        print(f"- {pkg_upper}_VERSION = {current_hash}")
        print(f"+ {pkg_upper}_VERSION = {remote_hash}")
    print()
    sys.stdout.flush()

    if DRY_RUN:
        log_debug(f"Dry-run: not updating {package_name}")
        return

    if behind:
        question = (
            f"  Add _SITE_BRANCH = {branch} and update {package_name} "
            f"{get_short_hash(current_hash)} -> {get_short_hash(remote_hash)}?"
        )
    else:
        question = f"  Add _SITE_BRANCH = {branch} to {package_name}?"

    if not confirm(f"{YELLOW}{question} [y/N]: {NC}"):
        log_debug(f"Declined branch resolution for {package_name}")
        return

    if not add_site_branch(mk_path, package_name, branch):
        return

    if behind:
        if update_package_mk(mk_path, package_name, current_hash, remote_hash):
            PACKAGES_WITH_UPDATES += 1
            if create_package_commit(
                package_name, mk_path, current_hash, remote_hash, [],
                note=f"Add _SITE_BRANCH = {branch}",
            ):
                PACKAGES_UPDATED += 1
                UPDATED_PACKAGES.append(
                    f"{package_name}:{get_short_hash(current_hash)}->{get_short_hash(remote_hash)}"
                )
            else:
                log_error(f"Failed to create commit for package {package_name}")
                return
        else:
            log_error(f"Failed to update {package_name} to {get_short_hash(remote_hash)}")
            return
    elif not create_branch_only_commit(package_name, mk_path, branch):
        log_error(f"Failed to create commit for package {package_name}")
        return

    log_success(f"Resolved {package_name} to track '{branch}'")


def process_package(mk_path: Path) -> None:
    global PACKAGES_WITH_UPDATES, PACKAGES_UPDATED

    parsed = parse_mk_file(mk_path)
    if not parsed:
        release_parsed = parse_mk_file_release(mk_path)
        if release_parsed:
            process_package_release(mk_path, *release_parsed)
            return
        no_branch = parse_mk_file_no_branch(mk_path)
        if no_branch:
            process_package_no_branch(mk_path, *no_branch)
        return

    package_name, repo_url, branch, current_hash = parsed

    log_info(f"Processing package: {package_name}")
    log_debug(f"  Repository: {repo_url}")
    log_debug(f"  Branch: {branch}")
    log_debug(f"  Current hash: {current_hash}")

    remote_hash = get_remote_hash(repo_url, branch)
    if not remote_hash:
        log_error(f"Failed to get remote hash for {package_name}")
        return

    log_debug(f"  Remote hash: {remote_hash}")

    if hashes_match(current_hash, remote_hash):
        print(package_name)
        print("---------------")
        print(repo_url)
        print(f"= {current_hash} (up to date)")
        print()
        log_debug(f"Package {package_name} is up to date")
        return

    PACKAGES_WITH_UPDATES += 1
    log_debug(f"Update available for {package_name}")

    # Output package information in the requested format
    print(package_name)
    print("---------------")
    print(repo_url)
    print(f"- {current_hash}")
    print(f"+ {remote_hash}")

    # Commit log
    log_lines = get_commit_log(repo_url, current_hash, remote_hash, branch)
    if log_lines:
        for line in log_lines:
            print(f"* {line}")
    else:
        print("* (Failed to retrieve commit log)")
    print()
    # Ensure all output above is visible before prompting
    sys.stdout.flush()

    # In dry-run mode, do not prompt or modify files
    if DRY_RUN:
        log_debug(f"Dry-run: skipping update for package {package_name}")
        return

    # Prompt and update
    if prompt_yes_no(package_name, current_hash, remote_hash):
        if update_package_mk(mk_path, package_name, current_hash, remote_hash):
            # Create Git commit if enabled
            if create_package_commit(package_name, mk_path, current_hash, remote_hash, log_lines):
                PACKAGES_UPDATED += 1
                UPDATED_PACKAGES.append(f"{package_name}:{get_short_hash(current_hash)}->{get_short_hash(remote_hash)}")
                log_debug(f"Package {package_name} updated successfully")
            else:
                log_error(f"Failed to create commit for package {package_name}")
        else:
            log_error(f"Failed to update package {package_name}")
    else:
        log_debug(f"Skipping update for package {package_name}")


def resolve_source_path(path_str: str, config_file_dir: Path) -> Optional[Path]:
    """
    Resolve a Kconfig ``source`` path to a real filesystem path.
    Handles ``$BR2_EXTERNAL_*`` variables and relative references
    rooted at either the config file's directory, the project root,
    or ``buildroot/``.
    """
    # Strip shell variable references like $BR2_EXTERNAL_THINGINO_PATH
    # or ${BR2_EXTERNAL_THINGINO_PATH}
    resolved = BR2_VAR_RE.sub(str(PROJECT_ROOT), path_str)

    candidate = Path(resolved)
    if candidate.is_absolute():
        return candidate if candidate.exists() else None

    # Try relative to the containing Config.in.host
    candidate = (config_file_dir / resolved).resolve()
    if candidate.exists():
        return candidate

    # Try relative to project root
    candidate = (PROJECT_ROOT / resolved).resolve()
    if candidate.exists():
        return candidate

    # Try relative to buildroot directory
    candidate = (PROJECT_ROOT / "buildroot" / resolved).resolve()
    if candidate.exists():
        return candidate

    return None


def find_mk_from_host_config() -> List[Path]:
    """
    Discover package ``.mk`` files by scanning ``Config.in.host``
    ``source`` directives.

    Returns a list of ``.mk`` paths whose directory name matches the
    file name (same filter as the glob-based discovery in ``main()``).
    """
    seen: set[Path] = set()
    mk_files: List[Path] = []

    host_configs: List[Path] = [
        PROJECT_ROOT / "Config.in.host",
    ]
    host_configs.extend(PACKAGE_DIR.rglob("Config.in.host"))

    for cfg in host_configs:
        if not cfg.is_file():
            continue
        try:
            text = cfg.read_text(encoding="utf-8", errors="ignore")
        except Exception:
            continue

        cfg_dir = cfg.parent
        for m in SOURCE_RE.finditer(text):
            target = resolve_source_path(m.group(1), cfg_dir)
            if target is None:
                continue

            pkg_dir = target.parent
            if not pkg_dir.is_dir():
                continue

            # Apply the same naming heuristic as the glob-based discovery
            expected_mk = pkg_dir / f"{pkg_dir.name}.mk"
            if expected_mk.is_file() and expected_mk not in seen:
                seen.add(expected_mk)
                mk_files.append(expected_mk)

    return mk_files


def main() -> int:
    global TOTAL_PACKAGES_SCANNED, LOG_LEVEL, DRY_RUN, INFER_BRANCH

    parser = argparse.ArgumentParser(description="Check Git-sourced package hashes and GitHub release-bundle versions, then interactively update.")
    parser.add_argument("patterns", nargs="*", help="Optional package name patterns (glob), e.g., wifi-* thingino-*")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--dry-run", action="store_true", help="Only check for updates; do not prompt or modify files")
    parser.add_argument(
        "--infer-branch",
        action="store_true",
        help="For packages that pin a commit hash but declare no _SITE_BRANCH, "
             "resolve the remote default branch and offer to record it "
             "(confirmation defaults to No)",
    )
    args = parser.parse_args()
    if args.debug:
        LOG_LEVEL = 10
    DRY_RUN = args.dry_run
    INFER_BRANCH = args.infer_branch

    log_info("Starting Git package hash update check")
    if args.patterns:
        log_info(f"Processing packages matching: {' '.join(args.patterns)}")
    else:
        log_info(f"Scanning packages in: {PACKAGE_DIR}")

    if not PACKAGE_DIR.is_dir():
        log_error(f"Package directory not found: {PACKAGE_DIR}")
        return 1

    # Refuse to run on a dirty tree: the script edits .mk files and creates
    # commits, and an uncommitted change could be silently overwritten or
    # committed alongside ours.
    if not DRY_RUN and not check_git_working_directory():
        log_error("Working directory has uncommitted changes.")
        log_error("Commit or stash them first, or re-run with --dry-run.")
        code, out, err = run_git(
            ["status", "--short", "--", str(PACKAGE_DIR.relative_to(PROJECT_ROOT))],
            cwd=PROJECT_ROOT,
        )
        if code == 0 and out.strip():
            for line in out.strip().splitlines():
                print(f"  {line}", file=sys.stderr)
        return 1

    # Find .mk files whose filename matches the package directory name
    seen: set[Path] = set()
    mk_files: List[Path] = []
    if args.patterns:
        # Filter packages by provided glob patterns against package directory names
        for mk_path in PACKAGE_DIR.rglob('*.mk'):
            pkg_dir = mk_path.parent
            if mk_path.name != f"{pkg_dir.name}.mk":
                continue
            name = pkg_dir.name
            if any(fnmatch.fnmatch(name, pat) for pat in args.patterns):
                if mk_path not in seen:
                    seen.add(mk_path)
                    mk_files.append(mk_path)
        if not mk_files:
            log_error(f"No packages matched patterns: {' '.join(args.patterns)}")
            return 1
    else:
        for mk_path in PACKAGE_DIR.rglob('*.mk'):
            pkg_dir = mk_path.parent
            if mk_path.name == f"{pkg_dir.name}.mk":
                if mk_path not in seen:
                    seen.add(mk_path)
                    mk_files.append(mk_path)

    # Additionally discover packages from Config.in.host source directives
    host_mk = find_mk_from_host_config()
    for mk in host_mk:
        if mk not in seen:
            seen.add(mk)
            if not args.patterns or any(fnmatch.fnmatch(mk.parent.name, pat) for pat in args.patterns):
                mk_files.append(mk)

    for mk in sorted(mk_files):
        log_debug(f"Examining package: {mk.parent.name}")
        TOTAL_PACKAGES_SCANNED += 1
        process_package(mk)

    print_summary()

    if PACKAGES_WITH_UPDATES == 0:
        log_info("All Git packages are up to date.")
    else:
        log_info(f"Scan complete. Found {PACKAGES_WITH_UPDATES} package(s) with updates available.")
        if PACKAGES_UPDATED > 0:
            log_success(f"Successfully updated {PACKAGES_UPDATED} package(s).")

    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("", file=sys.stderr)
        log_warn("Interrupted by user")
        sys.exit(130)
    except Exception as e:
        log_error(f"Unexpected error: {e}")
        sys.exit(1)
