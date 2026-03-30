#!/bin/sh

if [ "$#" -lt 1 ]; then
	echo "Usage: $0 <TYPE|GCC|LIBC> [config files...]" >&2
	exit 1
fi

field="$1"
shift

case "$field" in
	TYPE)
		extract_expr='s/^BR2_THINGINO_TOOLCHAIN_TYPE_\([A-Z0-9_]*\)=y$/\1/p'
		default_value='EXTERNAL'
		;;
	GCC)
		extract_expr='s/^BR2_THINGINO_TOOLCHAIN_GCC_\([0-9][0-9]*\)=y$/\1/p'
		default_value='15'
		;;
	LIBC)
		extract_expr='s/^BR2_THINGINO_TOOLCHAIN_LIBC_\([A-Z0-9_]*\)=y$/\1/p'
		default_value='MUSL'
		;;
	*)
		echo "Unknown field: $field" >&2
		exit 1
		;;
esac

resolved_value=''

for config_file in "$@"; do
	[ -f "$config_file" ] || continue
	match=$(sed -n "$extract_expr" "$config_file" | tail -n 1)
	if [ -n "$match" ]; then
		resolved_value="$match"
	fi
done

printf '%s\n' "${resolved_value:-$default_value}"