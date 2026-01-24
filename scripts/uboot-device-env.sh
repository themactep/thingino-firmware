#!/bin/bash

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <uenv.txt> <path_to_isvp_common.h>"
	exit 1
fi

UENV_FILE=$1
CONFIG_HEADER=$2

if [ ! -f "$UENV_FILE" ]; then
	echo "Error: $UENV_FILE does not exist, not patching."
	exit 0
fi

if [ ! -f "$CONFIG_HEADER" ]; then
	echo "Error: $CONFIG_HEADER does not exist, not patching."
	exit 0
fi

# Create temporary file with exact format
TEMP_FILE=$(mktemp)
{
	printf '#ifndef CONFIG_DEVICE_ENV\n'
	printf '#define CONFIG_DEVICE_ENV \\\n'
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "$(tail -n1 "$UENV_FILE")" = "$line" ]; then
			printf '"%s\\0"\n' "$line"
		else
			printf '"%s\\0" \\\n' "$line"
		fi
	done < "$UENV_FILE"
	printf '#endif\n'
} > "$TEMP_FILE"

# Replace the existing block
# Match from '#ifndef CONFIG_DEVICE_ENV' to the first '#endif' after it
awk '
/^#ifndef CONFIG_DEVICE_ENV$/ {
	in_block = 1
	system("cat '"$TEMP_FILE"'")
	next
}
in_block && /^#endif$/ {
	in_block = 0
	next
}
in_block { next }
{ print }
' "$CONFIG_HEADER" > "$CONFIG_HEADER.tmp"

mv "$CONFIG_HEADER.tmp" "$CONFIG_HEADER"
rm "$TEMP_FILE"

echo "Successfully updated $CONFIG_HEADER with uenv.txt content."
