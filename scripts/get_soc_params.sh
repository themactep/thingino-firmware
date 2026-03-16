#!/bin/bash
# get_soc_params.sh - Query SoC parameters from database
# Usage: get_soc_params.sh <soc_model> <param> [flash_type]
#
# Parameters:
#   soc_model: SoC model name (e.g., t31x, t40n)
#   param: One of: family, arch, ram, uboot
#   flash_type: (optional, only for uboot param) "nand" or "nor" (default: nor)

set -e

SOC_MODEL=$(echo "$1" | tr -d '"')
PARAM="$2"
FLASH_TYPE="${3:-nor}"

if [ -z "$SOC_MODEL" ] || [ -z "$PARAM" ]; then
    echo "Usage: $0 <soc_model> <param> [flash_type]" >&2
    echo "  param: family, arch, ram, uboot" >&2
    exit 1
fi

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/soc_database.txt"

if [ ! -f "$DB_FILE" ]; then
    echo "Error: Database file not found: $DB_FILE" >&2
    exit 1
fi

# Convert model to lowercase for case-insensitive lookup
SOC_MODEL_LOWER=$(echo "$SOC_MODEL" | tr '[:upper:]' '[:lower:]')

# Query database
RESULT=$(awk -F',' -v model="$SOC_MODEL_LOWER" -v param="$PARAM" -v flash="$FLASH_TYPE" '
    # Skip comments and empty lines
    /^#/ || /^[[:space:]]*$/ { next }
    
    # Match SoC model (case-insensitive)
    tolower($1) == model {
        if (param == "family") {
            print $2
        } else if (param == "arch") {
            print $3
        } else if (param == "ram") {
            print $4
        } else if (param == "uboot") {
            # Field 5 = NOR, Field 6 = NAND
            if (flash == "nand") {
                # If NAND field is "-", fall back to NOR
                if ($6 == "-" || $6 == "") {
                    print $5
                } else {
                    print $6
                }
            } else {
                print $5
            }
        }
        exit
    }
' "$DB_FILE")

if [ -z "$RESULT" ]; then
    echo "Error: SoC model '$SOC_MODEL' not found in database" >&2
    exit 1
fi

echo "$RESULT"
