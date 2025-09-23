#!/bin/bash

# Fix AudioWorker buffer warning spam
# This script updates the prudynt configuration to use higher buffer thresholds
# to prevent excessive warning messages in the logs.

set -e

PRUDYNT_CONFIG="/etc/prudynt.json"
BACKUP_CONFIG="/etc/prudynt.json.backup.$(date +%Y%m%d_%H%M%S)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}AudioWorker Buffer Warning Fix Script${NC}"
echo "======================================"
echo

# Check if prudynt config exists
if [ ! -f "$PRUDYNT_CONFIG" ]; then
    echo -e "${RED}Error: $PRUDYNT_CONFIG not found${NC}"
    echo "This script requires a prudynt configuration file to be present."
    exit 1
fi

# Check if jq is available
if ! command -v jq &> /dev/null; then
    echo -e "${RED}Error: jq command not found${NC}"
    echo "This script requires jq for JSON manipulation."
    echo "Install it with: opkg update && opkg install jq"
    exit 1
fi

# Backup original config
echo -e "${YELLOW}Creating backup: $BACKUP_CONFIG${NC}"
cp "$PRUDYNT_CONFIG" "$BACKUP_CONFIG"

# Check current buffer settings
current_warn=$(jq -r '.audio.buffer_warn_frames // "not set"' "$PRUDYNT_CONFIG")
current_cap=$(jq -r '.audio.buffer_cap_frames // "not set"' "$PRUDYNT_CONFIG")

echo "Current buffer settings:"
echo "  buffer_warn_frames: $current_warn"
echo "  buffer_cap_frames: $current_cap"
echo

# Update the configuration
echo -e "${YELLOW}Updating buffer settings...${NC}"

# Use jq to update the configuration
jq '.audio.buffer_warn_frames = 5 | .audio.buffer_cap_frames = 8' "$PRUDYNT_CONFIG" > "${PRUDYNT_CONFIG}.tmp"

# Validate the JSON
if jq empty "${PRUDYNT_CONFIG}.tmp" 2>/dev/null; then
    mv "${PRUDYNT_CONFIG}.tmp" "$PRUDYNT_CONFIG"
    echo -e "${GREEN}✓ Configuration updated successfully${NC}"
else
    echo -e "${RED}✗ JSON validation failed, restoring backup${NC}"
    mv "$BACKUP_CONFIG" "$PRUDYNT_CONFIG"
    rm -f "${PRUDYNT_CONFIG}.tmp"
    exit 1
fi

# Show new settings
new_warn=$(jq -r '.audio.buffer_warn_frames' "$PRUDYNT_CONFIG")
new_cap=$(jq -r '.audio.buffer_cap_frames' "$PRUDYNT_CONFIG")

echo "New buffer settings:"
echo "  buffer_warn_frames: $new_warn (was: $current_warn)"
echo "  buffer_cap_frames: $new_cap (was: $current_cap)"
echo

echo -e "${GREEN}Configuration updated successfully!${NC}"
echo
echo "Changes made:"
echo "• Increased buffer_warn_frames from 3 to 5 (100ms warning threshold)"
echo "• Increased buffer_cap_frames from 5 to 8 (160ms maximum buffer)"
echo "• This should significantly reduce AudioWorker warning messages"
echo
echo -e "${YELLOW}Next steps:${NC}"
echo "1. Restart prudynt to apply the changes:"
echo "   systemctl restart prudynt"
echo "2. Monitor logs to verify warnings are reduced:"
echo "   tail -f /var/log/messages | grep AudioWorker"
echo
echo "If you need to revert the changes:"
echo "  cp $BACKUP_CONFIG $PRUDYNT_CONFIG"
echo "  systemctl restart prudynt"
