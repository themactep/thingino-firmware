#!/bin/bash

if [ "$#" -ne 2 ]; then
	echo "Usage: $0 <uenv.txt> <path_to_isvp_common.h>"
	exit 1
fi

UENV_FILE=$1
CONFIG_HEADER=$2

if [ ! -f "$UENV_FILE" ]; then
	echo "Error: $UENV_FILE does not exist."
	exit 1
fi

if [ ! -f "$CONFIG_HEADER" ]; then
	echo "Error: $CONFIG_HEADER does not exist."
	exit 1
fi

# Create temporary file with exact format
{
	printf '#define CONFIG_DEVICE_ENV \\\n'
	while IFS= read -r line || [ -n "$line" ]; do
		if [ "$(tail -n1 "$UENV_FILE")" = "$line" ]; then
			printf '"%s\\0"\n\n' "$line"
		else
			printf '"%s\\0" \\\n' "$line"
		fi
	done < "$UENV_FILE"
} > temp.txt

# Replace the existing block
sed -i -e '/#define CONFIG_DEVICE_ENV/,/^$\|^#define/{/#define CONFIG_DEVICE_ENV/r temp.txt
	d
}' -e '/#define CONFIG_DEVICE_ENV/{N;d;}' "$CONFIG_HEADER"

rm temp.txt

echo "Successfully updated $CONFIG_HEADER with uenv.txt content."
