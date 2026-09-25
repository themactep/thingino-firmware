#!/bin/sh
# shellcheck disable=SC1091,SC3043,SC2015
# Replace a firmware file the streamer loads at start. ?kind=iq (sensor IQ .bin) or font (OSD default.ttf).
# GET = info, POST raw file = install into the overlay, POST &reset = drop the overlay copy (stock is back).

. /var/www/x/auth.sh
require_auth

reply() {
	printf 'Status: %s\r\nContent-Type: application/json\r\nCache-Control: no-store\r\n\r\n%s\n' "$1" "$2"
	exit 0
}
fail() { reply "$1" "{\"error\":\"$2\"}"; }

# exact &-delimited param/flag match, not a bare substring (a future param
# whose value merely contains "reset", or a request naming both kinds, must
# not match)
qs_has() {
	case "&$QUERY_STRING&" in *"&$1&"*) return 0 ;; esac
	return 1
}

if qs_has "kind=iq"; then
	SENSOR=$(cat /proc/jz/sensor/sensor0/name 2>/dev/null || cat /proc/jz/sensor/name 2>/dev/null || cat /etc/sensor/model 2>/dev/null)
	SOC=$(soc -f 2>/dev/null)
	[ -n "$SENSOR" ] && [ -n "$SOC" ] || fail "412 Precondition Failed" "sensor or SoC unknown"
	DIR=/etc/sensor NAME="${SENSOR}-${SOC}.bin" MIN=8192 MAX=2097152
elif qs_has "kind=font"; then
	DIR=/usr/share/fonts NAME=default.ttf MIN=1024 MAX=2097152
else
	fail "400 Bad Request" "kind=iq|font"
fi
FILE="$DIR/$NAME"
# the dir may be a symlink (/etc/sensor -> /usr/share/sensor); overlay upper and /rom use the real path
REAL="$(readlink -f "$DIR" 2>/dev/null || echo "$DIR")/$NAME"
UPPER="/overlay$REAL"

magic_ok() {
	if qs_has "kind=iq"; then
		case "$(head -c 4 "$1")" in [0-9].[0-9][0-9]) return 0 ;; esac
	else
		case "$(head -c 4 "$1" | hexdump -e '4/1 "%02x"')" in 00010000 | 4f54544f | 74727565 | 74746366) return 0 ;; esac
	fi
	return 1
}

info() {
	local size=0 md5="" custom=0 stock=0 free
	[ -f "$FILE" ] && size=$(wc -c <"$FILE") && md5=$(md5sum "$FILE" | cut -d' ' -f1)
	[ -f "$UPPER" ] && custom=1
	[ -f "/rom$REAL" ] && stock=1
	free=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
	local list="" f
	if qs_has "kind=font"; then
		for f in "$DIR"/*.ttf "$DIR"/*.otf; do [ -f "$f" ] && list="$list${list:+,}\"${f##*/}\""; done
		list=",\"fonts\":[$list]"
	fi
	reply "200 OK" "{\"file\":\"$FILE\",\"size\":${size:-0},\"md5\":\"$md5\",\"custom\":$custom,\"stock\":$stock,\"overlay_free_kb\":${free:-0}$list}"
}

if [ "$REQUEST_METHOD" != "POST" ]; then
	if qs_has "kind=font"; then
		case "&$QUERY_STRING&" in
			*"&raw="*)
				F=${QUERY_STRING##*raw=}
				F=${F%%&*}
				case "$F" in *[!A-Za-z0-9._-]* | .*) fail "400 Bad Request" "bad name" ;; esac
				[ -f "$DIR/$F" ] || fail "404 Not Found" "no such font"
				printf 'Content-Type: font/ttf\r\nCache-Control: max-age=300\r\n\r\n'
				cat "$DIR/$F"
				exit 0
				;;
		esac
	fi
	info
fi

if qs_has "reset"; then
	[ -f "$UPPER" ] || info
	[ -f "/rom$REAL" ] || fail "409 Conflict" "no stock file to restore"
	# Unlink through the mounted overlay path ($REAL), not the raw upperdir
	# ($UPPER): removing a file directly in the upperdir while the overlay is
	# mounted is undefined - the merged view can keep resolving to the
	# unlinked inode until the dcache is evicted, so "reset" looked like it
	# worked (custom:0) while the daemon kept loading the old file on the
	# next restart. A remount did not reliably fix it either.
	rm -f "$REAL"
	info
fi

LEN=${CONTENT_LENGTH:-0}
case "$LEN" in '' | *[!0-9]*) fail "411 Length Required" "no length" ;; esac
[ "$LEN" -ge "$MIN" ] && [ "$LEN" -le "$MAX" ] || fail "413 Payload Too Large" "size must be $((MIN / 1024)) KB..$((MAX / 1048576)) MB"
FREE=$(df -k /overlay 2>/dev/null | awk 'NR==2{print $4}')
[ $((LEN / 1024 + 64)) -lt "${FREE:-0}" ] || fail "507 Insufficient Storage" "not enough space on the overlay"

TMP=$(mktemp /tmp/upl.XXXXXX) || fail "500 Internal Server Error" "no temp file"
trap 'rm -f "$TMP"' EXIT
head -c "$LEN" >"$TMP"
[ "$(wc -c <"$TMP")" -eq "$LEN" ] || fail "400 Bad Request" "short upload"
magic_ok "$TMP" || fail "415 Unsupported Media Type" "wrong file type"

mkdir -p "$DIR" || fail "500 Internal Server Error" "write failed"
# unique per-request staging name: a fixed "$FILE.new" let two concurrent
# uploads (two tabs, a double-click) truncate each other's copy mid-write
NEW=$(mktemp "$DIR/.upl.XXXXXX") || fail "500 Internal Server Error" "write failed"
cp "$TMP" "$NEW" && chmod 644 "$NEW" && mv "$NEW" "$FILE" && sync || {
	rm -f "$NEW"
	fail "500 Internal Server Error" "write failed"
}
info
