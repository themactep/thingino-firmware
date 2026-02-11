#!/bin/bash

# JSON validation script for configs directory
#
# Prerequisites:
#   - Python 3 with json_repair package (for --fix mode)
#     Install: pacman -S python-json_repair (Arch Linux)
#     Or: pip install json-repair
#
# Usage: ./scripts/validate-json.sh [--fix] [files...]
#
# Validates JSON files and reports only invalid files (valid files are silent).
# If no files provided, validates all .json files in configs/ directory.
#
# Options:
#   --fix    Automatically fix JSON formatting errors (requires json_repair)
#            Fixes: trailing commas, missing commas, unquoted keys, single quotes, etc.
#
# Examples:
#   ./scripts/validate-json.sh                      # Validate all JSON files in configs/
#   ./scripts/validate-json.sh --fix                # Validate and auto-fix all JSON files
#   ./scripts/validate-json.sh file.json            # Validate specific file
#   ./scripts/validate-json.sh --fix file.json      # Validate and fix specific file
#
# Exit codes:
#   0 - All files are valid
#   1 - One or more files have errors

set -e

EXIT_CODE=0
CONFIGS_DIR="configs"
FIX_MODE=0

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

validate_json() {
    local file="$1"
    
    if ! python3 -m json.tool "$file" > /dev/null 2>&1; then
        echo -e "${RED}✗ Invalid JSON:${NC} $file"
        python3 -m json.tool "$file" 2>&1 | head -n 5
        
        if [ $FIX_MODE -eq 1 ]; then
            echo -e "${YELLOW}  Attempting to fix...${NC}"
            if python3 -c "from json_repair import repair_json; import sys, json; content = open('$file').read(); repaired = repair_json(content); print(json.dumps(json.loads(repaired), indent=2))" > "${file}.tmp" 2>/dev/null; then
                mv "${file}.tmp" "$file"
                echo -e "${GREEN}  ✓ Fixed${NC}"
                return 0
            else
                rm -f "${file}.tmp"
                echo -e "${RED}  ✗ Unable to fix automatically${NC}"
                return 1
            fi
        fi
        return 1
    else
        return 0
    fi
}

# Parse arguments
FILES=()
for arg in "$@"; do
    if [[ "$arg" == "--fix" ]]; then
        FIX_MODE=1
    else
        FILES+=("$arg")
    fi
done

# Track statistics
TOTAL_FILES=0
INVALID_FILES=0

# If file arguments provided, validate those files
if [ ${#FILES[@]} -gt 0 ]; then
    for file in "${FILES[@]}"; do
        # Only process .json files
        if [[ "$file" == *.json ]]; then
            TOTAL_FILES=$((TOTAL_FILES + 1))
            if ! validate_json "$file"; then
                EXIT_CODE=1
                INVALID_FILES=$((INVALID_FILES + 1))
            fi
        fi
    done
else
    # No arguments, validate all .json files in configs directory
    if [ ! -d "$CONFIGS_DIR" ]; then
        echo -e "${RED}Error:${NC} Directory '$CONFIGS_DIR' not found"
        exit 1
    fi
    
    # Find all .json files recursively
    while IFS= read -r -d '' file; do
        TOTAL_FILES=$((TOTAL_FILES + 1))
        if ! validate_json "$file"; then
            EXIT_CODE=1
            INVALID_FILES=$((INVALID_FILES + 1))
        fi
    done < <(find "$CONFIGS_DIR" -type f -name "*.json" -print0)
fi

# Summary
if [ $EXIT_CODE -eq 0 ]; then
    echo -e "${GREEN}All $TOTAL_FILES JSON files are valid!${NC}"
else
    echo -e "\n${RED}Found $INVALID_FILES invalid file(s) out of $TOTAL_FILES${NC}"
fi

exit $EXIT_CODE
