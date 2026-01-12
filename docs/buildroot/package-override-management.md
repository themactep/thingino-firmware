# Package Override Management

This document describes how to use the `manage-package-overrides.sh` script to manage local source code overrides for Buildroot packages in the Thingino external tree.

## Overview

The package override management script (`scripts/manage-package-overrides.sh`) allows you to:

- Clone package source code locally for development
- Enable/disable overrides without deleting source code
- Update local source code from upstream repositories
- Manage `OVERRIDE_SRCDIR` entries in `local.mk`

This is particularly useful when you want to:
- Develop or debug a specific package
- Test modifications to package source code
- Work with multiple packages simultaneously
- Keep local changes separate from the build system

## Location

```
scripts/manage-package-overrides.sh
```

## Directory Structure

When using this script, the following structure is created:

```
thingino/
├── local.mk                    # Buildroot override configuration
├── overrides/                  # Local source code directory
│   ├── package-name-1/        # Cloned package source
│   ├── package-name-2/        # Cloned package source
│   └── ...
├── package/                    # Package definitions
└── scripts/
    └── manage-package-overrides.sh
```

## Usage

```bash
./scripts/manage-package-overrides.sh [OPTIONS] [PATTERN]
```

### Options

| Option | Description |
|--------|-------------|
| `-h, --help` | Show help message |
| `-a, --auto` | Automatically download all matching packages without prompting |
| `-l, --list` | List packages and their override status |
| `-r, --remove PACKAGE` | Remove override for specified package |
| `-e, --enable PACKAGE` | Enable (uncomment) override for specified package |
| `-d, --disable PACKAGE` | Disable (comment) override for specified package |
| `-u, --update [PATTERN]` | Update override(s) matching pattern (git pull/checkout) |
| `--all` | Update all overrides (use with `-u`) |
| `--clean` | Clean all overrides (prompts for confirmation) |

### Pattern Matching

Patterns use standard shell wildcard syntax:

| Pattern | Matches |
|---------|---------|
| `*` | All packages (default) |
| `thingino-*` | All packages starting with "thingino-" |
| `*streamer*` | Packages containing "streamer" |
| `wifi-*` | All WiFi driver packages |
| `openimp` | Specific package name |

## Common Workflows

### 1. Setting Up Package Overrides

#### Interactive Mode

Browse and selectively clone packages:

```bash
./scripts/manage-package-overrides.sh thingino-*
```

The script will:
1. Find all matching packages
2. Display package information (git URL, branch, version)
3. Prompt to download each package
4. Clone to `overrides/` directory
5. Add `OVERRIDE_SRCDIR` entry to `local.mk`

#### Automatic Mode

Download all matching packages without prompts:

```bash
./scripts/manage-package-overrides.sh -a thingino-streamer
./scripts/manage-package-overrides.sh -a openimp
```

### 2. Listing Package Override Status

View all packages and their override status:

```bash
./scripts/manage-package-overrides.sh -l
```

View specific packages:

```bash
./scripts/manage-package-overrides.sh -l thingino-*
./scripts/manage-package-overrides.sh -l wifi-*
```

Output shows three possible states:
- **YES** (green) - Override is active
- **DISABLED** (yellow) - Override exists but is commented out
- **NO** - No override configured

### 3. Enabling and Disabling Overrides

Temporarily disable an override without deleting source code:

```bash
./scripts/manage-package-overrides.sh -d thingino-button
```

This comments out the override in `local.mk`:
```makefile
# THINGINO_BUTTON_OVERRIDE_SRCDIR = /path/to/overrides/thingino-button
```

Re-enable a disabled override:

```bash
./scripts/manage-package-overrides.sh -e thingino-button
```

**Use Case**: Quickly test with/without local changes during development.

### 4. Updating Package Sources

Update a single package from upstream:

```bash
./scripts/manage-package-overrides.sh -u thingino-button
```

Update all packages matching a pattern:

```bash
./scripts/manage-package-overrides.sh -u thingino-*
```

Update all configured overrides:

```bash
./scripts/manage-package-overrides.sh -u --all
```

The update process:
1. Checks for uncommitted changes (offers to stash)
2. Handles detached HEAD state (checks out default branch)
3. Fetches from remote
4. Performs fast-forward merge only (safe)
5. Shows summary of updated/skipped/failed packages

### 5. Removing Overrides

Remove an override entry from `local.mk`:

```bash
./scripts/manage-package-overrides.sh -r thingino-webui
```

**Note**: This removes the override configuration but does NOT delete the source code in `overrides/`. To fully clean up, manually delete the directory:

```bash
rm -rf overrides/thingino-webui
```

### 6. Cleaning All Overrides

Remove all package overrides from `local.mk`:

```bash
./scripts/manage-package-overrides.sh --clean
```

This will:
1. Back up `local.mk` to `local.mk.bak`
2. Remove all `*_OVERRIDE_SRCDIR` lines
3. Keep source code in `overrides/` directory intact

## How It Works

### Buildroot OVERRIDE_SRCDIR

Buildroot supports the `<PKG>_OVERRIDE_SRCDIR` variable to use local source code instead of downloading from remote repositories. This is documented in the [Buildroot manual](https://buildroot.org/downloads/manual/manual.html#_advanced_usage).

When you set:
```makefile
THINGINO_BUTTON_OVERRIDE_SRCDIR = /path/to/local/thingino-button
```

Buildroot will:
- Use the local directory instead of downloading/cloning
- Skip version checking
- Rebuild the package when source files change
- Allow you to modify code and test immediately

### Package Detection

The script:
1. Scans the `package/` directory
2. Reads each package's `.mk` file
3. Extracts git repository information:
   - `<PKG>_SITE` - Git repository URL
   - `<PKG>_SITE_METHOD` - Should be "git"
   - `<PKG>_VERSION` - Commit hash or HEAD
   - `<PKG>_SITE_BRANCH` - Branch name

### local.mk File

The `local.mk` file is a Buildroot convention for local build customizations. It's included by the main Makefile but not tracked in git (should be in `.gitignore`).

Example `local.mk`:
```makefile
THINGINO_BUTTON_OVERRIDE_SRCDIR = /home/user/thingino/overrides/thingino-button
OPENIMP_OVERRIDE_SRCDIR = /home/user/thingino/overrides/openimp
# THINGINO_WEBUI_OVERRIDE_SRCDIR = /home/user/thingino/overrides/thingino-webui  # disabled
```

## Examples

### Example 1: Develop on a Single Package

```bash
# Clone the package source
./scripts/manage-package-overrides.sh -a thingino-button

# Make changes to the code
cd overrides/thingino-button
vim thingino-button.c

# Build the package (from main directory)
make thingino-button-rebuild

# Test on device
# ...

# Update from upstream when needed
./scripts/manage-package-overrides.sh -u thingino-button
```

### Example 2: Work on Multiple Related Packages

```bash
# Set up overrides for streamer and related packages
./scripts/manage-package-overrides.sh -a thingino-streamer
./scripts/manage-package-overrides.sh -a libpeer
./scripts/manage-package-overrides.sh -a openimp

# List current status
./scripts/manage-package-overrides.sh -l

# Later, update all
./scripts/manage-package-overrides.sh -u --all
```

### Example 3: Toggle Between Local and Remote Sources

```bash
# Use local version during development
./scripts/manage-package-overrides.sh -e thingino-button
make thingino-button-rebuild

# Test with upstream version (without losing local changes)
./scripts/manage-package-overrides.sh -d thingino-button
make thingino-button-dirclean thingino-button

# Switch back to local
./scripts/manage-package-overrides.sh -e thingino-button
make thingino-button-rebuild
```

### Example 4: Batch Setup for Development

```bash
# Clone all thingino core packages
./scripts/manage-package-overrides.sh -a "thingino-core"
./scripts/manage-package-overrides.sh -a "thingino-system"
./scripts/manage-package-overrides.sh -a "thingino-webui"
./scripts/manage-package-overrides.sh -a "thingino-streamer"

# Verify setup
./scripts/manage-package-overrides.sh -l thingino-*
```

## Tips and Best Practices

### 1. Rebuilding Packages

After modifying override source code, rebuild the package:

```bash
# Rebuild (incremental)
make <package-name>-rebuild

# Clean rebuild
make <package-name>-dirclean <package-name>
```

### 2. Git Workflow in Overrides

The cloned source code is a full git repository:

```bash
cd overrides/thingino-button
git status
git branch my-feature
git commit -am "My changes"
git push origin my-feature  # If you have push access
```

### 3. Handling Uncommitted Changes

When updating, the script detects uncommitted changes:

```
[WARNING] Uncommitted changes detected in thingino-button
Stash changes and continue? [y/N]:
```

Choose:
- **y**: Stash changes, update, then manually `git stash pop`
- **N**: Skip update, commit or handle changes manually

### 4. Detached HEAD State

If a package specifies a specific commit hash, the clone will be in detached HEAD state. The update function automatically:
1. Detects this condition
2. Checks out the default branch (master/main)
3. Pulls latest changes

### 5. Local.mk in Version Control

Add `local.mk` to `.gitignore` as it contains user-specific paths:

```bash
echo "local.mk" >> .gitignore
```

### 6. Cleaning Up

Before committing changes or creating a clean build:

```bash
# Disable all overrides
./scripts/manage-package-overrides.sh --clean

# Or selectively disable
./scripts/manage-package-overrides.sh -d thingino-button
./scripts/manage-package-overrides.sh -d openimp
```

## Troubleshooting

### Package Not Found

```
[ERROR] No packages found matching pattern: xyz
```

**Solution**: Check the package name exists in `package/` directory.

### Git Clone Fails

```
[ERROR] Unsupported site method: X
```

**Solution**: Only git-based packages are supported. Check the package `.mk` file has:
```makefile
<PKG>_SITE_METHOD = git
<PKG>_SITE = https://...
```

### Update Conflicts

```
[ERROR] Failed to update package-name (conflicts or non-fast-forward)
```

**Solution**: 
```bash
cd overrides/package-name
git status
# Resolve conflicts manually
git pull --rebase
```

### Override Not Taking Effect

**Check**:
1. Override is enabled (not commented) in `local.mk`
2. Path in `local.mk` is correct
3. Run `make <package>-dirclean <package>` to force rebuild

### Permission Issues

```
Permission denied
```

**Solution**: Ensure you have write permissions to the `overrides/` directory.

## Advanced Usage

### Custom Override Locations

While the script uses `overrides/`, you can manually edit `local.mk` to use any path:

```makefile
THINGINO_BUTTON_OVERRIDE_SRCDIR = /home/user/projects/thingino-button
```

### Scripting and Automation

The script can be used in automation scripts:

```bash
#!/bin/bash
# Setup development environment
./scripts/manage-package-overrides.sh -a thingino-button
./scripts/manage-package-overrides.sh -a thingino-streamer
./scripts/manage-package-overrides.sh -a openimp

# Daily update
./scripts/manage-package-overrides.sh -u --all
```

### Integration with CI/CD

Disable all overrides before CI builds:

```bash
./scripts/manage-package-overrides.sh --clean
make clean
make
```

## Reference

### Exit Codes

- `0` - Success
- `1` - Error (package not found, git error, etc.)

### Dependencies

The script requires:
- `bash` 4.0+
- `git`
- Standard Unix tools: `grep`, `sed`, `awk`

### File Locations

- **Script**: `scripts/manage-package-overrides.sh`
- **Config**: `local.mk` (root of external tree)
- **Sources**: `overrides/` (created automatically)
- **Package definitions**: `package/*/`

## See Also

- [Buildroot Manual - OVERRIDE_SRCDIR](https://buildroot.org/downloads/manual/manual.html#_advanced_usage)
- [Buildroot Manual - Understanding how to rebuild packages](https://buildroot.org/downloads/manual/manual.html#_understanding_how_to_rebuild_packages)
- Thingino package development documentation

## Version History

- **v1.0** (2026-01-12)
  - Initial release
  - Download/clone packages
  - Enable/disable overrides
  - Update packages
  - List package status
  - Pattern matching support
