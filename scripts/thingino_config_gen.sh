#!/bin/bash

#
# Thingino Configuration Generator
#
# This script generates the /etc/thingino.json file by merging multiple
# configuration sources with proper key override behavior.
#
# Usage: thingino_config_gen.sh <output_file> <br2_external> <camera_subdir> <camera>
#

# Check arguments
if [ $# -ne 4 ]; then
	echo "Usage: $0 <output_file> <br2_external> <camera_subdir> <camera>"
	echo "  output_file    Path to the output thingino.json file"
	echo "  br2_external   Path to BR2_EXTERNAL directory"
	echo "  camera_subdir  Camera subdirectory (e.g., configs/cameras)"
	echo "  camera         Camera name"
	exit 1
fi

OUTPUT_FILE="$1"
BR2_EXTERNAL="$2"
CAMERA_SUBDIR="$3"
CAMERA="$4"

[ -f "$OUTPUT_FILE" ] || echo '{}' > "$OUTPUT_FILE"

# Add system-wide config file
if [ -f "${BR2_EXTERNAL}/configs/thingino.json" ]; then
	jct "$OUTPUT_FILE" import "${BR2_EXTERNAL}/configs/thingino.json"
fi

# Add camera-specific override file
if [ -f "${BR2_EXTERNAL}/${CAMERA_SUBDIR}/${CAMERA}/thingino-override.json" ]; then
	jct "$OUTPUT_FILE" import "${BR2_EXTERNAL}/${CAMERA_SUBDIR}/${CAMERA}/thingino-override.json"
fi

# Add local.json if it exists
if [ -f "${BR2_EXTERNAL}/configs/thingino-local.json" ]; then
	jct "$OUTPUT_FILE" import "${BR2_EXTERNAL}/configs/thingino-local.json"
fi

echo "Successfully generated $OUTPUT_FILE" >&2

