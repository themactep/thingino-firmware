#!/bin/bash

#
# Cleanup script for stale BUILD_MEMO files
#
# This script removes BUILD_MEMO files that reference non-existent camera config files.
# This helps prevent the infinite hang issue when profiles are deleted but BUILD_MEMO
# files still reference them.
#

echo "Cleaning up stale BUILD_MEMO files..."

CLEANED=0
TOTAL=0

# Find all BUILD_MEMO files
for memo_file in /tmp/thingino-board.*; do
    if [ -f "$memo_file" ]; then
        TOTAL=$((TOTAL + 1))
        
        # Read the config path from the memo file
        config_path=$(cat "$memo_file" 2>/dev/null)
        
        if [ -n "$config_path" ]; then
            # Check if the config file exists
            if [ ! -f "$config_path" ]; then
                echo "Removing stale BUILD_MEMO: $memo_file (references non-existent: $config_path)"
                rm -f "$memo_file"
                CLEANED=$((CLEANED + 1))
            fi
        else
            echo "Removing empty BUILD_MEMO: $memo_file"
            rm -f "$memo_file"
            CLEANED=$((CLEANED + 1))
        fi
    fi
done

echo "Cleanup completed: $CLEANED out of $TOTAL BUILD_MEMO files removed."

if [ $CLEANED -gt 0 ]; then
    echo "You can now run 'make' without the infinite hang issue."
fi
