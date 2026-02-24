#!/bin/bash

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BASE_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
PACKAGE_DIR="$BASE_DIR/package"
OVERRIDES_DIR="$BASE_DIR/overrides"
LOCAL_MK="$BASE_DIR/local.mk"
FORK_MODE="no"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

usage() {
    cat <<EOF
Usage: $0 [OPTIONS] [PATTERN]

Traverse packages in package/ directory and manage local source overrides.

OPTIONS:
    -h, --help              Show this help message
    -a, --auto              Automatically download all matching packages without prompting
    -f, --fork              Fork GitHub repos before cloning (enables contribution workflow)
    -l, --list              List packages and their override status only
    -r, --remove PACKAGE    Remove override for specified package
    -e, --enable PACKAGE    Enable (uncomment) override for specified package
    -d, --disable PACKAGE   Disable (comment) override for specified package
    -u, --update [PATTERN]  Update override(s) matching pattern (git pull/checkout)
    --all                   Update all overrides (use with -u)
    --clean                 Clean all overrides (prompts for confirmation)

PATTERN:
    Wildcard pattern to match package names (default: *)
    Examples:
        thingino-*          Match all thingino packages
        *streamer*          Match packages containing 'streamer'
        wifi-*              Match all wifi packages
        openimp             Match specific package

EXAMPLES:
    $0 thingino-*           # Interactively setup overrides for thingino packages
    $0 -a openimp           # Auto-download openimp without prompting
    $0 -l wifi-*            # List all wifi packages and their status
    $0 -r thingino-webui    # Remove override for thingino-webui
    $0 -d thingino-button   # Disable override (comment out in local.mk)
    $0 -e thingino-button   # Enable override (uncomment in local.mk)
    $0 -u thingino-button   # Update single package override
    $0 -u thingino-*        # Update all thingino package overrides
    $0 -u --all             # Update all package overrides

EOF
    exit 0
}

# Parse package .mk file to extract git info
parse_package_mk() {
    local mk_file="$1"
    local pkg_upper="$2"

    local site=""
    local version=""
    local method=""
    local branch=""

    # Try to extract from the package .mk file
    if [ -f "$mk_file" ]; then
        site=$(grep "^${pkg_upper}_SITE\s*=" "$mk_file" | head -1 | sed 's/^.*=\s*//' | tr -d ' ')
        method=$(grep "^${pkg_upper}_SITE_METHOD\s*=" "$mk_file" | head -1 | sed 's/^.*=\s*//' | tr -d ' ')
        version=$(grep "^${pkg_upper}_VERSION\s*=" "$mk_file" | head -1 | sed 's/^.*=\s*//' | tr -d ' ')
        branch=$(grep "^${pkg_upper}_SITE_BRANCH\s*=" "$mk_file" | head -1 | sed 's/^.*=\s*//' | tr -d ' ')
    fi

    echo "$method|$site|$version|$branch"
}

# Check if package has override in local.mk
check_override() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        return 1
    fi

    grep -q "^${pkg_upper}_OVERRIDE_SRCDIR" "$LOCAL_MK" 2>/dev/null
}

# Check if package has override but is disabled (commented)
check_override_disabled() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        return 1
    fi

    grep -q "^#\s*${pkg_upper}_OVERRIDE_SRCDIR" "$LOCAL_MK" 2>/dev/null
}

# Get override path from local.mk
get_override_path() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        return 1
    fi

    # Try active override first, then disabled one
    grep "^${pkg_upper}_OVERRIDE_SRCDIR\|^#\s*${pkg_upper}_OVERRIDE_SRCDIR" "$LOCAL_MK" 2>/dev/null | head -1 | sed 's/^#\s*//' | sed 's/^.*=\s*//' | tr -d ' '
}

# Add override to local.mk
add_override() {
    local pkg_upper="$1"
    local override_path="$2"

    # Convert absolute path to relative using $(BR2_EXTERNAL)
    # Remove BASE_DIR prefix and use $(BR2_EXTERNAL) instead
    local relative_path="${override_path#$BASE_DIR/}"
    if [ "$relative_path" != "$override_path" ]; then
        # Path was inside BASE_DIR, make it relative
        override_path="\$(BR2_EXTERNAL)/$relative_path"
    fi

    # Create local.mk if it doesn't exist
    if [ ! -f "$LOCAL_MK" ]; then
        touch "$LOCAL_MK"
        print_info "Created $LOCAL_MK"
    fi

    # Check if override already exists
    if check_override "$pkg_upper"; then
        local existing_path=$(get_override_path "$pkg_upper")
        print_warning "Override already exists: ${pkg_upper}_OVERRIDE_SRCDIR = $existing_path"
        read -p "Replace with new path? [y/N]: " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            return 1
        fi
        # Remove old entry
        sed -i "/^${pkg_upper}_OVERRIDE_SRCDIR/d" "$LOCAL_MK"
    fi

    # Add new override
    echo "${pkg_upper}_OVERRIDE_SRCDIR = $override_path" >> "$LOCAL_MK"
    print_success "Added override: ${pkg_upper}_OVERRIDE_SRCDIR = $override_path"
}

# Remove override from local.mk
remove_override() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        print_error "local.mk does not exist"
        return 1
    fi

    if ! check_override "$pkg_upper" && ! check_override_disabled "$pkg_upper"; then
        print_error "No override found for $pkg_upper"
        return 1
    fi

    local override_path=$(get_override_path "$pkg_upper")
    sed -i "/^${pkg_upper}_OVERRIDE_SRCDIR/d; /^#\s*${pkg_upper}_OVERRIDE_SRCDIR/d" "$LOCAL_MK"
    print_success "Removed override for $pkg_upper (was: $override_path)"
}

# Enable (uncomment) override in local.mk
enable_override() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        print_error "local.mk does not exist"
        return 1
    fi

    if check_override "$pkg_upper"; then
        print_warning "Override for $pkg_upper is already enabled"
        return 0
    fi

    if ! check_override_disabled "$pkg_upper"; then
        print_error "No disabled override found for $pkg_upper"
        return 1
    fi

    # Remove leading # and whitespace
    sed -i "s/^#\s*\(${pkg_upper}_OVERRIDE_SRCDIR\)/\1/" "$LOCAL_MK"
    local override_path=$(get_override_path "$pkg_upper")
    print_success "Enabled override for $pkg_upper: $override_path"
}

# Disable (comment) override in local.mk
disable_override() {
    local pkg_upper="$1"

    if [ ! -f "$LOCAL_MK" ]; then
        print_error "local.mk does not exist"
        return 1
    fi

    if check_override_disabled "$pkg_upper"; then
        print_warning "Override for $pkg_upper is already disabled"
        return 0
    fi

    if ! check_override "$pkg_upper"; then
        print_error "No active override found for $pkg_upper"
        return 1
    fi

    # Add # at the beginning of the line
    sed -i "s/^\(${pkg_upper}_OVERRIDE_SRCDIR\)/# \1/" "$LOCAL_MK"
    local override_path=$(get_override_path "$pkg_upper")
    print_success "Disabled override for $pkg_upper: $override_path"
}

# Update package override source
update_override() {
    local pkg_name="$1"
    local pkg_upper="$2"

    # Check if override exists (enabled or disabled)
    if ! check_override "$pkg_upper" && ! check_override_disabled "$pkg_upper"; then
        print_error "No override found for $pkg_name"
        return 1
    fi

    local override_path=$(get_override_path "$pkg_upper")

    if [ ! -d "$override_path" ]; then
        print_error "Override path does not exist: $override_path"
        return 1
    fi

    # Check if it's a git repository
    if [ ! -d "$override_path/.git" ]; then
        print_warning "$pkg_name is not a git repository, skipping"
        return 1
    fi

    print_info "Updating $pkg_name at $override_path"

    cd "$override_path"

    # Check for uncommitted changes
    if ! git diff-index --quiet HEAD -- 2>/dev/null; then
        print_warning "Uncommitted changes detected in $pkg_name"
        read -p "Stash changes and continue? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git stash save "Auto-stash before update on $(date '+%Y-%m-%d %H:%M:%S')"
            print_info "Changes stashed"
        else
            print_info "Skipping $pkg_name"
            cd - >/dev/null
            return 1
        fi
    fi

    # Get current branch or default branch
    local current_branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)

    # Check if in detached HEAD state
    if [ "$current_branch" = "HEAD" ]; then
        print_warning "Repository is in detached HEAD state"

        # Try to get the default branch from remote
        local default_branch=$(git remote show origin 2>/dev/null | grep 'HEAD branch' | cut -d' ' -f5)

        if [ -z "$default_branch" ]; then
            # Fallback to common defaults
            if git show-ref --verify --quiet refs/heads/master; then
                default_branch="master"
            elif git show-ref --verify --quiet refs/heads/main; then
                default_branch="main"
            else
                print_error "Cannot determine default branch for $pkg_name"
                cd - >/dev/null
                return 1
            fi
        fi

        print_info "Checking out $default_branch branch..."
        if ! git checkout "$default_branch" 2>&1; then
            print_error "Failed to checkout $default_branch"
            cd - >/dev/null
            return 1
        fi
        current_branch="$default_branch"
    fi

    # Fetch latest changes
    print_info "Fetching from remote..."
    if ! git fetch origin 2>&1; then
        print_error "Failed to fetch from remote"
        cd - >/dev/null
        return 1
    fi

    # Pull latest changes
    print_info "Pulling latest changes on $current_branch..."
    if git pull --recurse-submodules --ff-only origin "$current_branch" 2>&1; then
        print_success "Updated $pkg_name successfully"
    else
        print_error "Failed to update $pkg_name (conflicts or non-fast-forward)"
        cd - >/dev/null
        return 1
    fi

    cd - >/dev/null
    return 0
}

# Check if a URL points to a GitHub repository
is_github_url() {
    [[ "$1" =~ github\.com ]]
}

# Fork a GitHub repo and echo the fork's clone URL
fork_github_repo() {
    local repo_url="$1"
    local repo_path
    repo_path=$(echo "$repo_url" | sed -E 's|https://github\.com/||; s|git@github\.com:||; s|\.git$||')

    print_info "Forking $repo_path on GitHub..." >&2
    if ! gh repo fork "$repo_path" --clone=false >&2 2>&1; then
        print_error "Failed to fork repository" >&2
        return 1
    fi

    local gh_user
    gh_user=$(gh api user --jq .login 2>/dev/null)
    if [ -z "$gh_user" ]; then
        print_error "Could not determine GitHub username" >&2
        return 1
    fi

    echo "https://github.com/$gh_user/$(basename "$repo_path")"
}

# Clone or download package source
download_package() {
    local pkg_name="$1"
    local pkg_upper="$2"
    local method="$3"
    local site="$4"
    local version="$5"
    local branch="$6"

    local dest_dir="$OVERRIDES_DIR/$pkg_name"

    # Create overrides directory if needed
    mkdir -p "$OVERRIDES_DIR"

    if [ -d "$dest_dir" ]; then
        print_warning "Directory already exists: $dest_dir"
        read -p "Re-clone/update? [y/N]: " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            rm -rf "$dest_dir"
        else
            return 1
        fi
    fi

    if [ "$method" = "git" ]; then
        local clone_url="$site"
        local upstream_url=""

        # Offer to fork GitHub repos for an easier contribution workflow
        if is_github_url "$site"; then
            local do_fork="$FORK_MODE"
            if [ "$do_fork" != "yes" ]; then
                read -p "Fork this GitHub repo before cloning? [y/N]: " -n 1 -r
                echo
                [[ $REPLY =~ ^[Yy]$ ]] && do_fork="yes"
            fi
            if [ "$do_fork" = "yes" ]; then
                local fork_url
                if fork_url=$(fork_github_repo "$site"); then
                    upstream_url="$site"
                    clone_url="$fork_url"
                    print_success "Will clone fork: $clone_url"
                else
                    print_warning "Forking failed, cloning original..."
                fi
            fi
        fi

        print_info "Cloning $clone_url to $dest_dir"

        if [ -n "$branch" ]; then
            if ! git clone --recurse-submodules --branch "$branch" "$clone_url" "$dest_dir"; then
                print_error "Clone failed"
                return 1
            fi
        else
            if ! git clone --recurse-submodules "$clone_url" "$dest_dir"; then
                print_error "Clone failed"
                return 1
            fi
        fi

        # Add upstream remote if we cloned a fork
        if [ -n "$upstream_url" ]; then
            git -C "$dest_dir" remote add upstream "$upstream_url"
            print_info "Added upstream remote: $upstream_url"
        fi

        # Checkout specific version if not HEAD; create a local branch to avoid detached HEAD
        if [ -n "$version" ] && [ "$version" != "HEAD" ]; then
            cd "$dest_dir"
            local local_branch="local-$(echo "$version" | tr '/' '-' | cut -c1-30)"
            if git checkout -b "$local_branch" "$version" 2>/dev/null; then
                print_info "Created local branch '$local_branch' at $version"
            else
                print_warning "Could not create branch at version: $version"
            fi
            cd - >/dev/null
        fi

        print_success "Cloned $pkg_name to $dest_dir"
    else
        print_error "Unsupported site method: $method (only 'git' is supported)"
        return 1
    fi
}

# List packages and their status
list_packages() {
    local pattern="$1"

    printf "%-40s %-10s %-50s\n" "PACKAGE" "OVERRIDE" "PATH"
    printf "%s\n" "$(printf '=%.0s' {1..110})"

    for pkg_dir in "$PACKAGE_DIR"/$pattern/; do
        [ -d "$pkg_dir" ] || continue

        local pkg_name=$(basename "$pkg_dir")
        local pkg_upper=$(echo "$pkg_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        local mk_file="$pkg_dir/$pkg_name.mk"

        # Skip if .mk file doesn't exist
        [ -f "$mk_file" ] || continue

        local status="NO"
        local path="-"

        if check_override "$pkg_upper"; then
            status="${GREEN}YES${NC}"
            path=$(get_override_path "$pkg_upper")
        elif check_override_disabled "$pkg_upper"; then
            status="${YELLOW}DISABLED${NC}"
            path=$(get_override_path "$pkg_upper")
        fi

        printf "%-40s %-20s %-50s\n" "$pkg_name" "$(echo -e $status)" "$path"
    done
}

# Main interactive processing
process_packages() {
    local pattern="$1"
    local auto_mode="$2"

    local count=0
    local processed=0

    # Count packages first
    for pkg_dir in "$PACKAGE_DIR"/$pattern/; do
        [ -d "$pkg_dir" ] || continue
        local pkg_name=$(basename "$pkg_dir")
        local mk_file="$pkg_dir/$pkg_name.mk"
        [ -f "$mk_file" ] && count=$((count + 1))
    done

    if [ $count -eq 0 ]; then
        print_error "No packages found matching pattern: $pattern"
        exit 1
    fi

    print_info "Found $count package(s) matching pattern: $pattern"
    echo

    for pkg_dir in "$PACKAGE_DIR"/$pattern/; do
        [ -d "$pkg_dir" ] || continue

        local pkg_name=$(basename "$pkg_dir")
        local pkg_upper=$(echo "$pkg_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
        local mk_file="$pkg_dir/$pkg_name.mk"

        # Skip if .mk file doesn't exist
        [ -f "$mk_file" ] || continue

        processed=$((processed + 1))

        echo -e "${BLUE}[$processed/$count]${NC} Processing: ${GREEN}$pkg_name${NC}"

        # Check if already has override
        if check_override "$pkg_upper"; then
            local override_path=$(get_override_path "$pkg_upper")
            print_info "Already has override: $override_path"

            if [ "$auto_mode" != "yes" ]; then
                read -p "Skip? [Y/n]: " -n 1 -r
                echo
                if [[ ! $REPLY =~ ^[Nn]$ ]]; then
                    echo
                    continue
                fi
            else
                echo
                continue
            fi
        fi

        # Parse package info
        IFS='|' read -r method site version branch <<< "$(parse_package_mk "$mk_file" "$pkg_upper")"

        if [ -z "$method" ] || [ -z "$site" ]; then
            print_warning "Could not extract git info from $mk_file"
            echo
            continue
        fi

        print_info "Method: $method"
        print_info "Site: $site"
        print_info "Version: $version"
        [ -n "$branch" ] && print_info "Branch: $branch"

        local do_download="no"

        if [ "$auto_mode" = "yes" ]; then
            do_download="yes"
        else
            read -p "Download/clone this package? [y/N]: " -n 1 -r
            echo
            [[ $REPLY =~ ^[Yy]$ ]] && do_download="yes"
        fi

        if [ "$do_download" = "yes" ]; then
            if download_package "$pkg_name" "$pkg_upper" "$method" "$site" "$version" "$branch"; then
                add_override "$pkg_upper" "$OVERRIDES_DIR/$pkg_name"
            fi
        fi

        echo
    done

    print_success "Processed $processed package(s)"
}

# Clean all overrides
clean_overrides() {
    if [ ! -f "$LOCAL_MK" ]; then
        print_info "No local.mk file found"
        return 0
    fi

    print_warning "This will remove ALL package overrides from local.mk"
    read -p "Are you sure? [y/N]: " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_info "Cancelled"
        return 0
    fi

    # Backup local.mk
    cp "$LOCAL_MK" "$LOCAL_MK.bak"
    print_info "Backed up local.mk to local.mk.bak"

    # Remove all OVERRIDE_SRCDIR lines
    sed -i '/_OVERRIDE_SRCDIR/d' "$LOCAL_MK"
    print_success "Cleaned all overrides from local.mk"
}

# Update overrides matching pattern
update_overrides() {
    local pattern="$1"
    local update_all="$2"

    local count=0
    local updated=0
    local failed=0
    local skipped=0

    # If updating all, get list from local.mk
    if [ "$update_all" = "yes" ]; then
        if [ ! -f "$LOCAL_MK" ]; then
            print_error "No local.mk file found"
            exit 1
        fi

        print_info "Updating all package overrides..."
        echo

        # Extract all package names from local.mk
        while IFS= read -r line; do
            if [[ "$line" =~ ^#?[[:space:]]*([A-Z_]+)_OVERRIDE_SRCDIR ]]; then
                local pkg_upper="${BASH_REMATCH[1]}"
                local pkg_name=$(echo "$pkg_upper" | tr '[:upper:]' '[:lower:]' | tr '_' '-')

                count=$((count + 1))
                echo -e "${BLUE}[$count]${NC} Updating: ${GREEN}$pkg_name${NC}"

                if update_override "$pkg_name" "$pkg_upper"; then
                    updated=$((updated + 1))
                else
                    if [ $? -eq 1 ]; then
                        skipped=$((skipped + 1))
                    else
                        failed=$((failed + 1))
                    fi
                fi
                echo
            fi
        done < "$LOCAL_MK"
    else
        # Update packages matching pattern
        for pkg_dir in "$PACKAGE_DIR"/$pattern/; do
            [ -d "$pkg_dir" ] || continue

            local pkg_name=$(basename "$pkg_dir")
            local pkg_upper=$(echo "$pkg_name" | tr '[:lower:]' '[:upper:]' | tr '-' '_')

            # Check if this package has an override
            if ! check_override "$pkg_upper" && ! check_override_disabled "$pkg_upper"; then
                continue
            fi

            count=$((count + 1))
            echo -e "${BLUE}[$count]${NC} Updating: ${GREEN}$pkg_name${NC}"

            if update_override "$pkg_name" "$pkg_upper"; then
                updated=$((updated + 1))
            else
                if [ $? -eq 1 ]; then
                    skipped=$((skipped + 1))
                else
                    failed=$((failed + 1))
                fi
            fi
            echo
        done
    fi

    if [ $count -eq 0 ]; then
        print_error "No package overrides found matching pattern: $pattern"
        exit 1
    fi

    echo "================================"
    print_info "Update summary:"
    print_success "  Updated: $updated"
    [ $skipped -gt 0 ] && print_warning "  Skipped: $skipped"
    [ $failed -gt 0 ] && print_error "  Failed: $failed"
    print_info "  Total: $count"
}

# Main script
main() {
    local pattern="*"
    local mode="interactive"
    local auto_mode="no"
    local remove_pkg=""
    local enable_pkg=""
    local disable_pkg=""
    local update_mode="no"
    local update_all="no"

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -h|--help)
                usage
                ;;
            -a|--auto)
                auto_mode="yes"
                shift
                ;;
            -f|--fork)
                FORK_MODE="yes"
                shift
                ;;
            -l|--list)
                mode="list"
                shift
                ;;
            -r|--remove)
                mode="remove"
                remove_pkg="$2"
                shift 2
                ;;
            -e|--enable)
                mode="enable"
                enable_pkg="$2"
                shift 2
                ;;
            -d|--disable)
                mode="disable"
                disable_pkg="$2"
                shift 2
                ;;
            -u|--update)
                mode="update"
                update_mode="yes"
                shift
                # Check if next arg is --all or a pattern
                if [[ $# -gt 0 ]] && [[ "$1" != "--all" ]] && [[ "$1" != -* ]]; then
                    pattern="$1"
                    shift
                fi
                ;;
            --all)
                update_all="yes"
                shift
                ;;
            --clean)
                mode="clean"
                shift
                ;;
            *)
                pattern="$1"
                shift
                ;;
        esac
    done

    case "$mode" in
        list)
            list_packages "$pattern"
            ;;
        remove)
            if [ -z "$remove_pkg" ]; then
                print_error "Package name required for --remove"
                exit 1
            fi
            local pkg_upper=$(echo "$remove_pkg" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            remove_override "$pkg_upper"
            ;;
        enable)
            if [ -z "$enable_pkg" ]; then
                print_error "Package name required for --enable"
                exit 1
            fi
            local pkg_upper=$(echo "$enable_pkg" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            enable_override "$pkg_upper"
            ;;
        disable)
            if [ -z "$disable_pkg" ]; then
                print_error "Package name required for --disable"
                exit 1
            fi
            local pkg_upper=$(echo "$disable_pkg" | tr '[:lower:]' '[:upper:]' | tr '-' '_')
            disable_override "$pkg_upper"
            ;;
        update)
            update_overrides "$pattern" "$update_all"
            ;;
        clean)
            clean_overrides
            ;;
        interactive)
            process_packages "$pattern" "$auto_mode"
            ;;
    esac
}

main "$@"
