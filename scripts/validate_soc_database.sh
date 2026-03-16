#!/bin/bash
# validate_soc_database.sh - Validate SoC database integrity
# Checks for common errors and inconsistencies

set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DB_FILE="$SCRIPT_DIR/soc_database.txt"

echo "=== SoC Database Validation ==="
echo "Database: $DB_FILE"
echo ""

# Check if database exists
if [ ! -f "$DB_FILE" ]; then
    echo "❌ ERROR: Database file not found!"
    exit 1
fi

# Count total entries
TOTAL=$(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | wc -l)
echo "✓ Total SoC models: $TOTAL"

# Check for duplicate models
DUPLICATES=$(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | cut -d',' -f1 | sort | uniq -d)
if [ -n "$DUPLICATES" ]; then
    echo "❌ ERROR: Duplicate SoC models found:"
    echo "$DUPLICATES"
    exit 1
else
    echo "✓ No duplicate models"
fi

# Check field count (should be 6 fields)
INVALID_LINES=$(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' 'NF != 6 {print NR": "$0}')
if [ -n "$INVALID_LINES" ]; then
    echo "❌ ERROR: Lines with incorrect field count:"
    echo "$INVALID_LINES"
    exit 1
else
    echo "✓ All entries have correct field count"
fi

# Check architecture values (should be 1 or 2)
INVALID_ARCH=$(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$3 !~ /^[12]$/ {print NR": "$1" has invalid arch: "$3}')
if [ -n "$INVALID_ARCH" ]; then
    echo "❌ ERROR: Invalid architecture values:"
    echo "$INVALID_ARCH"
    exit 1
else
    echo "✓ All architecture values are valid"
fi

# Check RAM values (should be numeric)
INVALID_RAM=$(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$4 !~ /^[0-9]+$/ {print NR": "$1" has invalid RAM: "$4}')
if [ -n "$INVALID_RAM" ]; then
    echo "❌ ERROR: Invalid RAM values:"
    echo "$INVALID_RAM"
    exit 1
else
    echo "✓ All RAM values are numeric"
fi

# Statistics
echo ""
echo "=== Statistics ==="
echo "XBurst1 SoCs: $(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$3==1' | wc -l)"
echo "XBurst2 SoCs: $(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$3==2' | wc -l)"
echo ""
echo "SoCs by family:"
grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | cut -d',' -f2 | sort | uniq -c | sort -rn
echo ""
echo "RAM configurations:"
grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | cut -d',' -f4 | sort -n | uniq -c | sort -rn
echo ""
echo "NAND support:"
echo "  With NAND: $(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$6 != "-"' | wc -l)"
echo "  NOR only:  $(grep -v '^#' "$DB_FILE" | grep -v '^[[:space:]]*$' | awk -F',' '$6 == "-"' | wc -l)"

echo ""
echo "✅ Database validation passed!"
exit 0
