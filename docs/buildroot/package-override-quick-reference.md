# Package Override Quick Reference

Quick reference for the `manage-package-overrides.sh` script.

## Quick Commands

```bash
# Setup - Clone package for local development
./scripts/manage-package-overrides.sh -a <package-name>

# List - Show override status
./scripts/manage-package-overrides.sh -l [pattern]

# Update - Pull latest changes from upstream
./scripts/manage-package-overrides.sh -u <package-name>
./scripts/manage-package-overrides.sh -u --all

# Enable/Disable - Toggle overrides
./scripts/manage-package-overrides.sh -e <package-name>
./scripts/manage-package-overrides.sh -d <package-name>

# Remove - Delete override configuration
./scripts/manage-package-overrides.sh -r <package-name>

# Clean - Remove all overrides
./scripts/manage-package-overrides.sh --clean
```

## Common Patterns

```bash
thingino-*      # All thingino packages
wifi-*          # All WiFi drivers
*streamer*      # Packages containing 'streamer'
openimp         # Specific package
*               # All packages (default)
```

## Workflow Examples

### Start Development on a Package
```bash
./scripts/manage-package-overrides.sh -a thingino-button
cd overrides/thingino-button
# Make changes...
cd ../..
make thingino-button-rebuild
```

### Quick Test - Use Upstream vs Local
```bash
# Use upstream
./scripts/manage-package-overrides.sh -d thingino-button
make thingino-button-dirclean thingino-button

# Use local
./scripts/manage-package-overrides.sh -e thingino-button
make thingino-button-rebuild
```

### Keep Overrides Updated
```bash
./scripts/manage-package-overrides.sh -u --all
```

## Override States

| State | Description | Color |
|-------|-------------|-------|
| YES | Active override | Green |
| DISABLED | Override exists but commented | Yellow |
| NO | No override configured | - |

## Files

- **Script**: `scripts/manage-package-overrides.sh`
- **Config**: `local.mk`
- **Sources**: `overrides/<package-name>/`

## See Also

Full documentation: `docs/buildroot/package-override-management.md`
