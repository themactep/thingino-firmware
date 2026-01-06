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
#SYSTEM_CONFIG="${BR2_EXTERNAL}/configs/thingino.json"
#if [ -f "$SYSTEM_CONFIG" ]; then
#	jct "$OUTPUT_FILE" import "$SYSTEM_CONFIG"
#fi

# Add camera-specific json file
CAMERA_CONFIG="${BR2_EXTERNAL}/${CAMERA_SUBDIR}/${CAMERA}/thingino-camera.json"
if [ -f "$CAMERA_CONFIG" ]; then
	jct "$OUTPUT_FILE" import "$CAMERA_CONFIG"
fi

# Add local.json if it exists
USER_CONFIG="${BR2_EXTERNAL}/configs/thingino-local.json"
if [ -f "$USER_CONFIG" ]; then
	jct "$OUTPUT_FILE" import "$USER_CONFIG"
fi

echo "Successfully generated $OUTPUT_FILE" >&2