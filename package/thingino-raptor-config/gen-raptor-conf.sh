#!/bin/sh
# Render raptor.conf from a kconfig .config and conf-map.
# usage: gen-raptor-conf.sh <dotconfig> <conf-map> <raptor.conf> <sensor_qty>
set -e
DOTCONFIG=$1 MAP=$2 CONF=$3 QTY=${4:-1}

# POSIX dot searches PATH when the operand has no slash
case "$DOTCONFIG" in
*/*) . "$DOTCONFIG" ;;
*) . "./$DOTCONFIG" ;;
esac

# Multi-sensor layout: the template ships [sensor] live and the rest commented.
if [ "$QTY" -gt 1 ] 2>/dev/null; then
	sed -i 's/^\[sensor\]/[sensor0]/' "$CONF"
	for s in sensor1 mipi_switch sensor1_image sensor1_stream0 sensor1_stream1; do
		sed -i "s/^# \[$s\]/[$s]/" "$CONF"
	done
fi

rset() {
	[ -n "$3" ] || return 0
	if sed -n "/^\[$1\]/,/^[# ]*\[/p" "$CONF" | grep -qE "^[# ]*$2 = "; then
		sed -i "/^\[$1\]/,/^[# ]*\[/{s|^[# ]*$2 = .*|$2 = $3|;}" "$CONF"
	else
		sed -i "/^\[$1\]/a $2 = $3" "$CONF"
	fi
}

deref() { eval "printf '%s' \"\${$1:-}\""; }

while read -r type section key sym rest; do
	case "$type" in
	'#' | '') continue ;;
	str) val=$(deref "$sym") ;;
	bool)
		if [ "$(deref "${sym}_TRUE")" = y ]; then val=true
		elif [ "$(deref "${sym}_FALSE")" = y ]; then val=false
		else val=; fi
		;;
	enum)
		val=
		for c in $rest; do
			if [ "$(deref "${sym}_${c}")" = y ]; then
				val=$(echo "$c" | tr 'A-Z' 'a-z')
				break
			fi
		done
		;;
	*) continue ;;
	esac
	rset "$section" "$key" "$val"
done < "$MAP"
