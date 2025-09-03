#!/bin/bash
# Update buildroot submodule with proper patch management and submodule pinning
#
# This script handles the complex process of updating the buildroot submodule
# while maintaining local patches and following Git submodule best practices.
#
# The process:
# 1. Unapply existing patches to get clean upstream state
# 2. Update submodule to its pinned commit (NOT HEAD tracking)
# 3. Reapply patches from package/all-patches/buildroot/
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
PATCHES_DIR="$PROJECT_ROOT/package/all-patches/buildroot"

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
Update buildroot submodule with proper patch management

This script safely updates the buildroot submodule while maintaining local
patches and following Git submodule best practices. It does NOT track HEAD
but respects the pinned commit in the parent repository.

Usage: $0 [OPTIONS]

Options:
    -h, --help     Show this help message and exit
    -n, --dry-run  Show what would be done without making changes
    -v, --verbose  Enable verbose output for debugging
    -f, --force    Force update even if there are uncommitted changes

Examples:
    $0                    # Normal update
    $0 --dry-run          # Preview changes without applying
    $0 --verbose          # Update with detailed logging
    $0 --force            # Force update ignoring uncommitted changes

The update process:
1. Validates environment and checks for uncommitted changes
2. Unapplies existing patches to restore clean upstream state
3. Updates submodule to the commit pinned in parent repository
4. Reapplies patches from package/all-patches/buildroot/

Note: This script maintains submodule pinning and does NOT track upstream HEAD.
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

    # Check if buildroot is a git repository (could be .git directory or .git file for submodules)
    if [ ! -e "$BUILDROOT_DIR/.git" ]; then
        log_error "Buildroot directory is not a git repository"
        log_error "Initialize submodules first: git submodule update --init"
        exit 1
    fi

    # Verify we can actually run git commands in buildroot
    if ! (cd "$BUILDROOT_DIR" && git status >/dev/null 2>&1); then
        log_error "Cannot run git commands in buildroot directory"
        log_error "Initialize submodules first: git submodule update --init"
        exit 1
    fi

    # Check if patches directory exists
    if [ ! -d "$PATCHES_DIR" ]; then
        log_warning "Patches directory not found: $PATCHES_DIR"
        log_warning "No patches will be applied"
    fi

    log_success "Environment validation passed"
}

# Check for uncommitted changes
check_uncommitted_changes() {
    log_info "Checking for uncommitted changes..."

    cd "$BUILDROOT_DIR"

    if git status --porcelain | grep -q .; then
        if [ "$FORCE" = true ]; then
            log_warning "Uncommitted changes detected but --force specified"
            log_warning "Changes will be stashed automatically"
        else
            log_error "Buildroot submodule has uncommitted changes"
            log_error "Commit or stash changes first, or use --force to auto-stash"
            git status --short
            exit 1
        fi
    else
        log_success "No uncommitted changes detected"
    fi

    cd "$PROJECT_ROOT"
}

# Unapply existing patches
unapply_patches() {
    log_info "Unapplying existing patches..."

    cd "$BUILDROOT_DIR"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would unapply patches and reset to clean upstream state"
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Check if there are any applied patches by looking for commits that aren't in upstream
    local upstream_commit
    upstream_commit=$(git rev-parse origin/master 2>/dev/null || echo "")

    if [ -z "$upstream_commit" ]; then
        log_warning "Could not determine upstream commit, fetching..."
        git fetch origin
        upstream_commit=$(git rev-parse origin/master)
    fi

    local current_commit
    current_commit=$(git rev-parse HEAD)

    if [ "$current_commit" = "$upstream_commit" ]; then
        log_success "Already at clean upstream state, no patches to unapply"
    else
        log_verbose "Current commit: $current_commit"
        log_verbose "Upstream commit: $upstream_commit"

        # Stash any uncommitted changes if --force was used
        if git status --porcelain | grep -q .; then
            log_info "Stashing uncommitted changes..."
            git stash push -m "Auto-stash before buildroot update on $(date)"
        fi

        # Reset to clean upstream state
        log_info "Resetting to clean upstream state..."
        git reset --hard "$upstream_commit"
        log_success "Reset to clean upstream state"
    fi

    cd "$PROJECT_ROOT"
}

# Update submodule to pinned commit
update_submodule_to_pinned_commit() {
    log_info "Updating submodule to pinned commit..."

    # Get the commit that the parent repository expects for buildroot
    local pinned_commit
    pinned_commit=$(git ls-tree HEAD buildroot | awk '{print $3}')

    if [ -z "$pinned_commit" ]; then
        log_error "Could not determine pinned commit for buildroot submodule"
        exit 1
    fi

    log_info "Parent repository expects buildroot at commit: $pinned_commit"

    cd "$BUILDROOT_DIR"

    local current_commit
    current_commit=$(git rev-parse HEAD)

    if [ "$current_commit" = "$pinned_commit" ]; then
        log_success "Buildroot is already at the pinned commit"
    else
        if [ "$DRY_RUN" = true ]; then
            log_info "[DRY RUN] Would update buildroot from $current_commit to $pinned_commit"
        else
            log_info "Updating buildroot from $current_commit to $pinned_commit"

            # Fetch to ensure we have the pinned commit
            git fetch origin

            # Checkout the pinned commit
            if git checkout "$pinned_commit"; then
                log_success "Successfully updated to pinned commit: $pinned_commit"
            else
                log_error "Failed to checkout pinned commit: $pinned_commit"
                exit 1
            fi
        fi
    fi

    cd "$PROJECT_ROOT"
}

# Apply patches from package/all-patches/buildroot/
apply_patches() {
    log_info "Applying patches from $PATCHES_DIR..."

    if [ ! -d "$PATCHES_DIR" ]; then
        log_warning "Patches directory not found, skipping patch application"
        return 0
    fi

    cd "$BUILDROOT_DIR"

    # Find all patch files
    local patch_files
    patch_files=($(find "$PATCHES_DIR" -name "*.patch" | sort))

    if [ ${#patch_files[@]} -eq 0 ]; then
        log_warning "No patch files found in $PATCHES_DIR"
        cd "$PROJECT_ROOT"
        return 0
    fi

    log_info "Found ${#patch_files[@]} patch files to apply"

    if [ "$DRY_RUN" = true ]; then
        log_info "[DRY RUN] Would apply the following patches:"
        for patch_file in "${patch_files[@]}"; do
            echo "  - $(basename "$patch_file")"
        done
        cd "$PROJECT_ROOT"
        return 0
    fi

    # Apply patches using git am
    log_verbose "Applying patches with git am..."
    if git am "${patch_files[@]}"; then
        log_success "All ${#patch_files[@]} patches applied successfully"

        # Show final state
        if [ "$VERBOSE" = true ]; then
            log_verbose "Final buildroot state:"
            git log --oneline -10
        fi
    else
        log_error "Failed to apply patches"
        log_error "Aborting patch application..."
        git am --abort
        log_error "Buildroot is in clean upstream state"
        log_error "Please review and fix patches in $PATCHES_DIR"
        exit 1
    fi

    cd "$PROJECT_ROOT"
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
    echo "✓ Buildroot submodule updated successfully"
    echo "✓ Current commit: $current_commit"
    echo "✓ Current state: $current_branch"

    if [ -d "$PATCHES_DIR" ]; then
        local patch_count
        patch_count=$(find "$PATCHES_DIR" -name "*.patch" | wc -l)
        echo "✓ Applied $patch_count patches from package/all-patches/buildroot/"
    fi

    echo ""
    echo "NOTE: Buildroot submodule changes are NOT automatically committed."
    echo "Review the changes and commit if desired:"
    echo "  git status                    # Check repository status"
    echo "  git diff --submodule          # Review submodule changes"
    echo "  git add buildroot             # Stage submodule update"
    echo "  git commit -m 'buildroot: update submodule with patches'"
    echo ""

    cd "$PROJECT_ROOT"
}

# Main function
main() {
    log_info "Starting buildroot submodule update process..."
    echo ""

    if [ "$DRY_RUN" = true ]; then
        log_warning "DRY RUN MODE - No changes will be made"
        echo ""
    fi

    # Step 1: Validate environment
    validate_environment
    echo ""

    # Step 2: Check for uncommitted changes
    check_uncommitted_changes
    echo ""

    # Step 3: Unapply existing patches
    unapply_patches
    echo ""

    # Step 4: Update submodule to pinned commit
    update_submodule_to_pinned_commit
    echo ""

    # Step 5: Apply patches
    apply_patches
    echo ""

    # Step 6: Show summary
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

# Trap to ensure we're always in the project root on exit
cleanup() {
    cd "$PROJECT_ROOT" 2>/dev/null || true
}
trap cleanup EXIT

# Script entry point
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Parse command line arguments
    parse_args "$@"

    # Change to project root
    cd "$PROJECT_ROOT"

    # Run main function
    main
fi
