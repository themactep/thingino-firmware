#!/bin/sh

if [ -z "$1" ]; then
	echo "Usage: $0 <filename>"
	exit 1
fi

file="$1"
if [ ! -f "$file" ]; then
	echo "Cannot find file ${file}"
	exit 2
fi

if [ -z "$(cat "$file")" ]; then
	echo "File ${file} is empty"
	exit 3
fi

url=$(cat "$file" | nc termbin.com 9999)
echo "$url"

exit 0
