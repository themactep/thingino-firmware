#!/usr/bin/env python3

import re
import sys
import shutil
import tempfile
import subprocess
import argparse
import fnmatch
from pathlib import Path
from typing import Optional, Tuple, List

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
# Git commit mode: when True, create commits for package updates
GIT_COMMIT = False
# Stash reference for temporarily saving uncommitted changes
STASH_REF: Optional[str] = None
STASH_SHA: Optional[str] = None

HASH_RE = re.compile(r"^[a-f0-9]{40}$")


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
        proc = subprocess.run(["git", *args], cwd=cwd, capture_output=True, text=True, timeout=timeout)
        return proc.returncode, proc.stdout.strip(), proc.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", "timeout"
    except FileNotFoundError:
        return 127, "", "git not found"


def is_valid_hash(s: str) -> bool:
    return bool(HASH_RE.match(s))


def get_short_hash(h: str) -> str:
    return h[:7]


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


def stash_uncommitted_changes() -> Optional[str]:
    """
    Stash any uncommitted changes in the working directory.
    Returns the stash reference if successful, None if failed or no changes to stash.
    """
    global STASH_REF, STASH_SHA

    if check_git_working_directory():
        log_debug("No uncommitted changes to stash")
        return None

    log_info("Stashing uncommitted changes to ensure clean working directory")

    # Create a stash with a descriptive message
    stash_message = f"check-git-package-updates.py auto-stash at {subprocess.run(['date', '+%Y-%m-%d %H:%M:%S'], capture_output=True, text=True).stdout.strip()}"

    code, out, err = run_git(["stash", "push", "-u", "-m", stash_message], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to stash uncommitted changes: {err}")
        return None

    # Get the stash reference
    code, out, err = run_git(["stash", "list", "--format=%H %gd", "-n", "1"], cwd=PROJECT_ROOT)
    if code != 0 or not out.strip():
        log_error("Failed to get stash reference")
        return None

    try:
        sha, ref = out.strip().split(maxsplit=1)
    except ValueError:
        log_error("Unexpected format when reading stash reference")
        return None

    STASH_SHA = sha
    STASH_REF = ref  # e.g., 'stash@{0}'
    log_success(f"Successfully stashed changes with reference: {ref}")
    return ref


def restore_stashed_changes() -> bool:
    """
    Restore previously stashed changes.
    Returns True if successful or no stash to restore, False if failed.
    """
    global STASH_REF, STASH_SHA

    if not STASH_REF:
        log_debug("No stashed changes to restore")
        return True

    log_info("Restoring previously stashed changes")

    # Apply and drop the stash
    code, out, err = run_git(["stash", "pop", STASH_REF], cwd=PROJECT_ROOT)

    # Determine whether the stash still exists (by SHA) regardless of exit code
    still_exists = False
    if STASH_SHA:
        ls_code, ls_out, ls_err = run_git(["stash", "list", "--format=%H"], cwd=PROJECT_ROOT)
        if ls_code == 0 and STASH_SHA in ls_out.splitlines():
            still_exists = True

    if code != 0 and still_exists:
        # Include stdout and stderr to aid diagnosis
        details = (out + ("\n" if out and err else "") + err).strip()
        log_error(f"Failed to restore stashed changes: {details}")
        log_warn(f"You may need to manually restore stash {STASH_REF}")
        return False

    # Consider success if the stash no longer exists (it may have applied with warnings/conflicts)
    if code != 0 and not still_exists:
        details = (out + ("\n" if out and err else "") + err).strip()
        if details:
            log_warn(f"Stash restored with warnings: {details}")
        log_success("Successfully restored stashed changes")
        STASH_REF = None
        STASH_SHA = None
        return True

    # code == 0
    log_success("Successfully restored stashed changes")
    STASH_REF = None
    STASH_SHA = None
    return True


def create_package_commit(package_name: str, mk_path: Path, old_hash: str, new_hash: str, commit_log: List[str]) -> bool:
    """
    Create a Git commit for a package update.
    Returns True if successful, False if failed.
    """
    if not GIT_COMMIT:
        return True

    log_debug(f"Creating Git commit for package {package_name}")

    # Stage the modified .mk file
    relative_mk_path = mk_path.relative_to(PROJECT_ROOT)
    code, out, err = run_git(["add", str(relative_mk_path)], cwd=PROJECT_ROOT)
    if code != 0:
        log_error(f"Failed to stage {relative_mk_path}: {err}")
        return False

    # Create commit message
    old_short = get_short_hash(old_hash)
    new_short = get_short_hash(new_hash)

    commit_title = f"package/{package_name}: update to {new_short}"

    commit_body_lines = [
        "",
        f"Update {package_name} from {old_short} to {new_short}",
        "",
        f"Hash change: {old_hash} -> {new_hash}",
        ""
    ]

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


def parse_mk_file(mk_path: Path) -> Optional[Tuple[str, str, str, str]]:
    """
    Return (package_name, repo_url, branch, version_hash) if git-sourced with static hash, else None.
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

    # Default to HEAD if branch is unspecified to respect the remote's default branch
    return package_name, site, (branch or 'HEAD'), version


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


def get_commit_log(repo_url: str, old_hash: str, new_hash: str) -> List[str]:
    log_debug(f"Getting commit log for {repo_url} from {old_hash} to {new_hash}")
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
        # Fetch both commits with shallow depth and without blobs for speed
        run_git(["fetch", "--quiet", "--depth=200", "--filter=blob:none", "origin", old_hash], cwd=tmpdir, timeout=180)
        run_git(["fetch", "--quiet", "--depth=200", "--filter=blob:none", "origin", new_hash], cwd=tmpdir, timeout=180)
        code, out, err = run_git([
            "log", "--pretty=format:%h: %s", "--reverse", f"{old_hash}..{new_hash}"
        ], cwd=tmpdir, timeout=90)
        if code == 0:
            return [line for line in out.splitlines() if line.strip()]
        else:
            log_error(f"Failed to get commit log between {old_hash} and {new_hash}: {err}")
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

    backup = mk_path.with_suffix(mk_path.suffix + ".backup")
    try:
        backup.write_text(text, encoding='utf-8')
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


def prompt_yes_no(package_name: str, old_hash: str, new_hash: str) -> bool:
    old_short = get_short_hash(old_hash)
    new_short = get_short_hash(new_hash)
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


def print_summary() -> None:
    print("", file=sys.stderr)
    print(f"{BLUE}=== SUMMARY REPORT ==={NC}", file=sys.stderr)
    print(f"{BLUE}Total packages scanned:{NC} {TOTAL_PACKAGES_SCANNED}", file=sys.stderr)
    print(f"{BLUE}Packages with updates available:{NC} {PACKAGES_WITH_UPDATES}", file=sys.stderr)
    print(f"{BLUE}Packages actually updated:{NC} {PACKAGES_UPDATED}", file=sys.stderr)
    if UPDATED_PACKAGES:
        print("", file=sys.stderr)
        print(f"{GREEN}Updated packages:{NC}", file=sys.stderr)
        for u in UPDATED_PACKAGES:
            print(f"  {GREEN}\u2713{NC} {u}", file=sys.stderr)
    print("", file=sys.stderr)


def process_package(mk_path: Path) -> None:
    global PACKAGES_WITH_UPDATES, PACKAGES_UPDATED

    parsed = parse_mk_file(mk_path)
    if not parsed:
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

    if current_hash == remote_hash:
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
    log_lines = get_commit_log(repo_url, current_hash, remote_hash)
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


def main() -> int:
    global TOTAL_PACKAGES_SCANNED, LOG_LEVEL, DRY_RUN, GIT_COMMIT

    parser = argparse.ArgumentParser(description="Check Git-sourced package hashes and interactively update.")
    parser.add_argument("patterns", nargs="*", help="Optional package name patterns (glob), e.g., wifi-* thingino-*")
    parser.add_argument("--debug", action="store_true", help="Enable debug logging")
    parser.add_argument("--dry-run", action="store_true", help="Only check for updates; do not prompt or modify files")
    parser.add_argument("--git-commit", action="store_true", help="Create Git commits for package updates")
    args = parser.parse_args()
    if args.debug:
        LOG_LEVEL = 10
    DRY_RUN = args.dry_run
    GIT_COMMIT = args.git_commit

    log_info("Starting Git package hash update check")
    if args.patterns:
        log_info(f"Processing packages matching: {' '.join(args.patterns)}")
    else:
        log_info(f"Scanning packages in: {PACKAGE_DIR}")

    if GIT_COMMIT:
        log_info("Git commit mode enabled - will create commits for package updates")

    if not PACKAGE_DIR.is_dir():
        log_error(f"Package directory not found: {PACKAGE_DIR}")
        return 1

    # Stash uncommitted changes if Git commit mode is enabled and not in dry-run
    if GIT_COMMIT and not DRY_RUN:
        stash_uncommitted_changes()

    # Find .mk files whose filename matches the package directory name
    mk_files: List[Path] = []
    if args.patterns:
        # Filter packages by provided glob patterns against package directory names
        for mk_path in PACKAGE_DIR.rglob('*.mk'):
            pkg_dir = mk_path.parent
            if mk_path.name != f"{pkg_dir.name}.mk":
                continue
            name = pkg_dir.name
            if any(fnmatch.fnmatch(name, pat) for pat in args.patterns):
                mk_files.append(mk_path)
        if not mk_files:
            log_error(f"No packages matched patterns: {' '.join(args.patterns)}")
            return 1
    else:
        for mk_path in PACKAGE_DIR.rglob('*.mk'):
            pkg_dir = mk_path.parent
            if mk_path.name == f"{pkg_dir.name}.mk":
                mk_files.append(mk_path)

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

    # Restore stashed changes if any were stashed
    if GIT_COMMIT and not DRY_RUN:
        if not restore_stashed_changes():
            log_warn("Failed to restore stashed changes - please check manually")
            return 1

    return 0


if __name__ == '__main__':
    try:
        sys.exit(main())
    except KeyboardInterrupt:
        print("", file=sys.stderr)
        log_warn("Interrupted by user")
        # Try to restore stashed changes if interrupted
        if GIT_COMMIT and not DRY_RUN and STASH_REF:
            log_info("Attempting to restore stashed changes before exit...")
            restore_stashed_changes()
        sys.exit(130)
    except Exception as e:
        log_error(f"Unexpected error: {e}")
        # Try to restore stashed changes on unexpected error
        if GIT_COMMIT and not DRY_RUN and STASH_REF:
            log_info("Attempting to restore stashed changes before exit...")
            restore_stashed_changes()
        sys.exit(1)

