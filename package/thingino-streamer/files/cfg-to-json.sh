#!/bin/bash

# Simple script to help migrate from libconfig (.cfg) to JSON (.json) format
# This is a basic converter - manual review may be needed for complex configurations

if [ $# -ne 2 ]; then
    echo "Usage: $0 <input.cfg> <output.json>"
    echo "Converts libconfig format to JSON format"
    exit 1
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"

if [ ! -f "$INPUT_FILE" ]; then
    echo "Error: Input file '$INPUT_FILE' not found"
    exit 1
fi

echo "Converting $INPUT_FILE to $OUTPUT_FILE..."

# Basic conversion using sed and awk
# This handles most common cases but may need manual adjustment for complex configs
cat "$INPUT_FILE" | \
    # Remove comments
    sed 's/#.*$//' | \
    # Remove empty lines
    sed '/^\s*$/d' | \
    # Convert assignment operator
    sed 's/\s*=\s*/: /' | \
    # Add quotes around keys
    sed 's/^\s*\([a-zA-Z_][a-zA-Z0-9_]*\)\s*:/"\1":/' | \
    # Add quotes around string values (basic heuristic)
    sed 's/: \([^0-9{}\[\]"][^;]*\);/: "\1",/' | \
    # Handle numeric values
    sed 's/: \([0-9][^;]*\);/: \1,/' | \
    # Handle boolean values
    sed 's/: true;/: true,/' | \
    sed 's/: false;/: false,/' | \
    # Replace semicolons with commas
    sed 's/;/,/' | \
    # Handle object opening
    sed 's/{/{/' | \
    # Handle object closing
    sed 's/}/}/' | \
    # Wrap in root object
    awk 'BEGIN{print "{"} {print} END{print "}"}' | \
    # Clean up trailing commas before closing braces
    sed 's/,\s*}/}/' > "$OUTPUT_FILE"

echo "Conversion complete. Please review $OUTPUT_FILE manually."
echo "Note: This is a basic conversion. Complex configurations may need manual adjustment."
echo ""
echo "Validate the JSON format using: jq . $OUTPUT_FILE"
echo "Or use the thingino JSON config tool: jct $OUTPUT_FILE print"
echo ""
echo "To get/set values use:"
echo "  jct $OUTPUT_FILE get motion.enabled"
echo "  jct $OUTPUT_FILE set motion.enabled true"
