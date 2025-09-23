#!/bin/bash
# Update buildroot submodule to latest upstream and commit the change
#
# This script updates the buildroot submodule to the latest upstream commit
# and commits that change to the main repository. It does NOT reapply patches.
#
# The process:
# 1. Remove existing patches to get clean upstream state
# 2. Update submodule to latest upstream commit
# 3. Commit the submodule update to main repository
# 4. Push the commit to remote
#
# Usage: scripts/update_buildroot.sh [OPTIONS]
#   -h, --help     Show this help message
#   -n, --dry-run  Show what would be done without making changes
#   -v, --verbose  Enable verbose output
#   -f, --force    Force update even if there are uncommitted changes

set -e  # Exit on any error

# Script configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
BUILDROOT_DIR="$PROJECT_ROOT/buildroot"

# Default options
DRY_RUN=false
VERBOSE=false
FORCE=false

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging functions
log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

log_verbose() {
    if [ "$VERBOSE" = true ]; then
        echo -e "${BLUE}[VERBOSE]${NC} $1"
    fi
}

# Help function
show_help() {
    cat << EOF
Update buildroot submodule to latest upstream and commit the change

This script updates the buildroot submodule to the latest upstream commit
and commits that change to the main repository. Patches are NOT reapplied.

Usage: $0 [OPTIONS]

Options:
    -h, --help     Show this help message and exit
    -n, --dry-run  Show what would be done without making changes
    -v, --verbose  Enable verbose output for debugging
    -f, --force    Force update even if there are uncommitted changes

Examples:
    $0                    # Normal update and commit
    $0 --dry-run          # Preview changes without applying
    $0 --verbose          # Update with detailed logging
    $0 --force            # Force update ignoring uncommitted changes

The update process:
1. Validates environment and checks for uncommitted changes
2. Removes existing patches to restore clean upstream state
3. Updates submodule to latest upstream commit
4. Commits the submodule update to main repository
5. Pushes the commit to remote

Note: This script does NOT reapply patches. Use 'make update' afterwards
to reapply patches if needed.
EOF
}

# Parse command line arguments
parse_args() {
    while [[ $# -gt 0 ]]; do
        case $1 in
            -h|--help)
                show_help
                exit 0
                ;;
            -n|--dry-run)
                DRY_RUN=true
                shift
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -f|--force)
                FORCE=true
                shift
                ;;
            *)
                log_error "Unknown option: $1"
                echo "Use --help for usage information."
                exit 1
                ;;
        esac
    done
}

# Validation functions
validate_environment() {
    log_info "Validating environment..."

    # Check if we're in the right directory
    if [ ! -f "$PROJECT_ROOT/Makefile" ] || [ ! -d "$PROJECT_ROOT/.git" ]; then
        log_error "This script must be run from the thingino-firmware project root"
        exit 1
    fi

    # Check if buildroot submodule exists
    if [ ! -d "$BUILDROOT_DIR" ]; then
        log_error "Buildroot submodule directory not found: $BUILDROOT_DIR"
        log_error "Initialize submodules first: git submodule update --init"
        exit 1
    fi

    # Check if buildroot is a git repository
    if [ ! -e "$BUILDROOT_DIR/.git" ]; then
        log_error "Buildroot directory is not a git repository"
        log_error "Initialize submodules first: git submodule update --init"
        exit 1
    fi

    # Verify we can run git commands in buildroot
    if ! (cd "$BUILDROOT_DIR" && git status >/dev/null 2>&1); then
        log_error "Cannot run git commands in buildroot directory"
        log_error "Initialize submodules first: git submodule update --init"
        exit 1
    fi

    log_success "Environment validation passed"
}

# Check for uncommitted changes in main repository
check_main_repo_changes() {
    log_info "Checking main repository for uncommitted changes..."

    cd "$PROJECT_ROOT"

    if git status --porcelain | grep -q .; then
        if [ "$FORCE" = true ]; then
            log_warning "Main repository has uncommitted changes but --force specified"
            log_warning "Changes will be stashed automatically"
        else
            log_error "Main repository has uncommitted changes"
            log_error "Commit or stash changes first, or use --force to auto-stash"
            git status --short
            exit 1
        fi
    else
        log_success "No uncommitted changes in main repository"
    fi
}

# Check for uncommitted changes in buildroot submodule
check_buildroot_changes() {
    log_info "Checking buildroot submodule for uncommitted changes..."

    cd "$BUILDROOT_DIR"

    if git status --porcelain | grep -q .; then
        if [ "$FORCE" = true ]; then
            log_warning "Buildroot has uncommitted changes but --force specified"
            log_warning "Changes will be stashed automatically"
        else
            log_error "Buildroot submodule has uncommitted changes"
            log_error "Commit or stash changes first, or use --force to auto-stash"
            git status --short
            exit 1
        fi
    else
        log_success "No uncommitted changes in buildroot submodule"
    fi

    cd "$PROJECT_ROOT"
}

# Remove existing patches from buildroot
remove_patches() {
    log_info "Removing existing patches from buildroot..."

    cd "$BUILDROOT_DIR"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would remove patches and reset to clean upstream state"
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Stash any uncommitted changes if --force was used
    if git status --porcelain | grep -q .; then
        log_info "Stashing uncommitted changes..."
        git stash push -m "Auto-stash before buildroot update on $(date)"
    fi

    # Fetch latest from origin
    log_info "Fetching latest from upstream..."
    git fetch origin

    # Reset to clean upstream state (origin/master)
    log_info "Resetting to clean upstream state..."
    git reset --hard origin/master
    log_success "Reset to clean upstream state"

    cd "$PROJECT_ROOT"
}

# Update submodule to latest upstream
update_to_latest_upstream() {
    log_info "Updating buildroot submodule to latest upstream..."

    cd "$BUILDROOT_DIR"

    # Get current and latest commits
    local current_commit
    current_commit=$(git rev-parse HEAD)

    local latest_commit
    latest_commit=$(git rev-parse origin/master)

    log_info "Current commit: $current_commit"
    log_info "Latest upstream commit: $latest_commit"

    if [ "$current_commit" = "$latest_commit" ]; then
        log_success "Buildroot is already at the latest upstream commit"
        cd "$PROJECT_ROOT"
        return 0
    fi

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would update buildroot from $current_commit to $latest_commit"
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Update to latest upstream
    log_info "Updating to latest upstream commit: $latest_commit"
    git checkout "$latest_commit"
    log_success "Successfully updated to latest upstream commit"

    cd "$PROJECT_ROOT"
}

# Commit the submodule update
commit_submodule_update() {
    log_info "Committing submodule update to main repository..."

    cd "$PROJECT_ROOT"

    # Check if there are changes to commit
    if ! git diff --quiet buildroot; then
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would commit submodule update"
            git diff --submodule buildroot
            return 0
        fi

        # Stash any uncommitted changes in main repo if --force was used
        if git status --porcelain | grep -v "^M  buildroot" | grep -q .; then
            log_info "Stashing uncommitted changes in main repository..."
            git stash push -m "Auto-stash before buildroot submodule update on $(date)"
        fi

        # Get buildroot commit info for commit message
        local buildroot_commit
        buildroot_commit=$(cd "$BUILDROOT_DIR" && git rev-parse --short HEAD)

        local buildroot_date
        buildroot_date=$(cd "$BUILDROOT_DIR" && git log -1 --format="%ci" | cut -d' ' -f1)

        # Add and commit the submodule update
        git add buildroot
        git commit -m "buildroot: update submodule to latest upstream

Updated buildroot submodule to commit $buildroot_commit ($buildroot_date)

This update removes all local patches. Use 'make update' to reapply
patches if needed."

        log_success "Committed submodule update"
    else
        log_info "No submodule changes to commit"
    fi
}

# Push to remote
push_to_remote() {
    log_info "Pushing commit to remote repository..."

    cd "$PROJECT_ROOT"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would push commit to remote"
        return 0
    fi

    # Get current branch
    local current_branch
    current_branch=$(git branch --show-current)

    if [ -z "$current_branch" ]; then
        log_error "Not on a branch, cannot push"
        exit 1
    fi

    log_info "Pushing to origin/$current_branch..."

    if git push origin "$current_branch"; then
        log_success "Successfully pushed to remote"
    else
        log_error "Failed to push to remote"
        log_error "You may need to pull first or resolve conflicts"
        exit 1
    fi
}

# Show summary of changes
show_summary() {
    log_info "Update summary:"

    cd "$BUILDROOT_DIR"

    local current_commit
    current_commit=$(git rev-parse HEAD)
    local current_branch
    current_branch=$(git describe --always --tags 2>/dev/null || echo "unknown")

    echo ""
    echo "=== BUILDROOT UPDATE SUMMARY ==="
    echo "✓ Buildroot submodule updated to latest upstream"
    echo "✓ Current commit: $current_commit"
    echo "✓ Current state: $current_branch"
    echo "✓ Submodule update committed to main repository"
    echo "✓ Changes pushed to remote repository"
    echo ""
    echo "NOTE: All patches have been removed from buildroot."
    echo "To reapply patches, run:"
    echo "  make update"
    echo ""

    cd "$PROJECT_ROOT"
}

# Main function
main() {
    log_info "Starting buildroot submodule update to latest upstream..."
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Step 1: Validate environment
    validate_environment
    echo ""

    # Step 2: Check for uncommitted changes
    check_main_repo_changes
    echo ""
    check_buildroot_changes
    echo ""

    # Step 3: Remove existing patches
    remove_patches
    echo ""

    # Step 4: Update to latest upstream
    update_to_latest_upstream
    echo ""

    # Step 5: Commit submodule update
    commit_submodule_update
    echo ""

    # Step 6: Push to remote
    push_to_remote
    echo ""

    # Step 7: Show summary
    if [ "$DRY_RUN" = false ]; then
        show_summary
    else
        log_info "DRY RUN completed - no changes were made"
        echo ""
        echo "To perform the actual update, run:"
        echo "  $0"
        echo ""
    fi
}

# Parse arguments and run main function
parse_args "$@"
main