#!/bin/bash

# Git Package Hash Update Checker for Thingino Firmware
# This script scans all packages in the package/ directory and checks for hash updates
# in packages that use Git repositories as their source.

set -euo pipefail

# Configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$PROJECT_ROOT/package"
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" >&2
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1" >&2
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1" >&2
}

# Function to parse makefile variables from a package .mk file
parse_package_makefile() {
    local mk_file="$1"
    local package_name="$2"

    # Convert package name to uppercase for variable names
    local pkg_upper=$(echo "$package_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

    # Extract variables using grep and sed - be more specific with patterns
    local site_method=$(grep "^${pkg_upper}_SITE_METHOD[[:space:]]*=" "$mk_file" 2>/dev/null | sed 's/.*=[[:space:]]*//' || echo "")
    local site=$(grep "^${pkg_upper}_SITE[[:space:]]*=" "$mk_file" 2>/dev/null | grep -v "_SITE_METHOD\|_SITE_BRANCH" | head -1 | sed 's/.*=[[:space:]]*//' || echo "")
    local branch=$(grep "^${pkg_upper}_SITE_BRANCH[[:space:]]*=" "$mk_file" 2>/dev/null | sed 's/.*=[[:space:]]*//' || echo "")
    local version=$(grep "^${pkg_upper}_VERSION[[:space:]]*=" "$mk_file" 2>/dev/null | head -1 | sed 's/.*=[[:space:]]*//' || echo "")

    # Clean up variables (remove quotes and shell expansions)
    site=$(echo "$site" | sed 's/^"\(.*\)"$/\1/' | sed 's/\$(.*)//')
    branch=$(echo "$branch" | sed 's/^"\(.*\)"$/\1/')
    version=$(echo "$version" | sed 's/^"\(.*\)"$/\1/' | sed 's/\$(.*)//')

    # Only process if it's a git package with static version
    if [[ "$site_method" == "git" && -n "$site" && -n "$version" && ! "$version" =~ \$\( ]]; then
        echo "$package_name|$site|$branch|$version"
    fi
}

# Function to get the latest commit hash from a remote Git repository
get_remote_hash() {
    local repo_url="$1"
    local branch="${2:-master}"

    log_info "Checking remote hash for $repo_url (branch: $branch)"

    # Try to get the remote hash
    local remote_hash
    if remote_hash=$(git ls-remote "$repo_url" "$branch" 2>/dev/null | head -1 | cut -f1); then
        if [[ -n "$remote_hash" ]]; then
            echo "$remote_hash"
            return 0
        fi
    fi

    # If branch-specific lookup failed, try HEAD
    if [[ "$branch" != "HEAD" ]]; then
        if remote_hash=$(git ls-remote "$repo_url" HEAD 2>/dev/null | head -1 | cut -f1); then
            if [[ -n "$remote_hash" ]]; then
                log_warn "Branch '$branch' not found, using HEAD: $remote_hash"
                echo "$remote_hash"
                return 0
            fi
        fi
    fi

    log_error "Failed to get remote hash for $repo_url"
    return 1
}

# Function to get commit log between two hashes
get_commit_log() {
    local repo_url="$1"
    local old_hash="$2"
    local new_hash="$3"
    local temp_repo="$TEMP_DIR/$(basename "$repo_url" .git)"

    log_info "Getting commit log for $repo_url from $old_hash to $new_hash"

    # Clone repository to temporary directory
    if ! git clone --quiet "$repo_url" "$temp_repo" 2>/dev/null; then
        log_error "Failed to clone repository $repo_url"
        return 1
    fi

    cd "$temp_repo"

    # Get commit log between hashes
    if git log --oneline --reverse "${old_hash}..${new_hash}" 2>/dev/null; then
        cd - >/dev/null
        return 0
    else
        log_error "Failed to get commit log between $old_hash and $new_hash"
        cd - >/dev/null
        return 1
    fi
}

# Function to check if a hash is valid (40 character hex string)
is_valid_hash() {
    local hash="$1"
    [[ "$hash" =~ ^[a-f0-9]{40}$ ]]
}

# Function to process a single package
process_package() {
    local package_info="$1"
    IFS='|' read -r package_name repo_url branch current_hash <<< "$package_info"

    # Set default branch if empty
    [[ -z "$branch" ]] && branch="master"

    log_info "Processing package: $package_name"
    log_info "  Repository: $repo_url"
    log_info "  Branch: $branch"
    log_info "  Current hash: $current_hash"

    # Validate current hash
    if ! is_valid_hash "$current_hash"; then
        log_warn "Invalid current hash for $package_name: $current_hash"
        return 1
    fi

    # Get remote hash
    local remote_hash
    if ! remote_hash=$(get_remote_hash "$repo_url" "$branch"); then
        log_error "Failed to get remote hash for $package_name"
        return 1
    fi

    # Validate remote hash
    if ! is_valid_hash "$remote_hash"; then
        log_warn "Invalid remote hash for $package_name: $remote_hash"
        return 1
    fi

    log_info "  Remote hash: $remote_hash"

    # Compare hashes
    if [[ "$current_hash" != "$remote_hash" ]]; then
        log_success "Update available for $package_name"

        # Output package information
        echo "$package_name"
        echo "---------------"
        echo "$repo_url"
        echo "- $current_hash"
        echo "+ $remote_hash"

        # Get and display commit log
        if commit_log=$(get_commit_log "$repo_url" "$current_hash" "$remote_hash"); then
            echo "$commit_log" | while read -r line; do
                if [[ -n "$line" ]]; then
                    echo "* $line"
                fi
            done
        else
            echo "* (Failed to retrieve commit log)"
        fi
        echo

        return 0
    else
        log_info "Package $package_name is up to date"
        return 1
    fi
}

# Main function
main() {
    local updates_found=0

    log_info "Starting Git package hash update check"
    log_info "Scanning packages in: $PACKAGE_DIR"

    # Check if package directory exists
    if [[ ! -d "$PACKAGE_DIR" ]]; then
        log_error "Package directory not found: $PACKAGE_DIR"
        exit 1
    fi

    # Find all package directories with .mk files
    while IFS= read -r -d '' mk_file; do
        # Extract package name from file path
        local package_dir=$(dirname "$mk_file")
        local package_name=$(basename "$package_dir")
        local mk_filename=$(basename "$mk_file")

        # Skip if the .mk file doesn't match the package name pattern
        if [[ "$mk_filename" != "${package_name}.mk" ]]; then
            continue
        fi

        log_info "Examining package: $package_name"

        # Parse the makefile
        if package_info=$(parse_package_makefile "$mk_file" "$package_name"); then
            if [[ -n "$package_info" ]]; then
                log_info "Found Git package: $package_name"

                # Process the package
                if process_package "$package_info"; then
                    ((updates_found++))
                fi
            fi
        fi
    done < <(find "$PACKAGE_DIR" -name "*.mk" -type f -print0)

    log_info "Scan complete. Found $updates_found package(s) with updates available."

    if [[ $updates_found -eq 0 ]]; then
        log_info "All Git packages are up to date."
    fi
}

# Run main function
main "$@"
