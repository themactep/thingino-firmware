#!/bin/sh

. /usr/share/common

# Parse query string
if [ -n "$QUERY_STRING" ]; then
  eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

# Get referer for redirect back
referer="${HTTP_REFERER:-/}"

# Validate file parameter
if [ -z "$f" ]; then
  printf 'Status: 302 Found\n'
  printf 'Location: %s?error=%s\n\n' "$referer" "$(echo 'Nothing to restore.' | sed 's/ /%20/g')"
  exit 1
fi

file="$f"

# Check if file exists in ROM
if [ ! -f "/rom/$file" ]; then
  printf 'Status: 302 Found\n'
  printf 'Location: %s?error=%s\n\n' "$referer" "$(echo "File /rom/$file not found!" | sed 's/ /%20/g;s/\//%2F/g')"
  exit 1
fi

# Restore file from ROM
cp "/rom/$file" "$file"

if [ $? -eq 0 ]; then
  printf 'Status: 302 Found\n'
  printf 'Location: %s?success=%s\n\n' "$referer" "$(echo "File $file restored from ROM." | sed 's/ /%20/g')"
else
  printf 'Status: 302 Found\n'
  printf 'Location: %s?error=%s\n\n' "$referer" "$(echo "Cannot restore $file!" | sed 's/ /%20/g;s/!/%21/g')"
fi
