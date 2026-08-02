#!/bin/sh
# json-recordings.cgi - browse/serve the timps SD recordings. This is a
# FILESYSTEM helper (like json-sensor-info.cgi), not a streamer bridge:
#   GET                -> JSON list of segments under <record.dir>/<host>/records
#   GET ?file=<rel>    -> streams that segment as video/mp4 (play/download)
#   GET ?del=<rel>     -> deletes that segment
# Auth-protected; the file/del parameter is guarded against path traversal.

. /var/www/x/auth.sh
require_auth

CONF=/etc/timps.conf
DIR=$(sed -n 's/^[[:space:]]*record\.dir[[:space:]]*=[[:space:]]*"\{0,1\}\([^"#]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \t')
[ -z "$DIR" ] && DIR=/mnt/mmcblk0p1
BASE="$DIR/$(hostname)/records"

qval() { printf '%s' "$QUERY_STRING" | sed -n "s/.*$1=\([^&]*\).*/\1/p"; }
urldec() { printf '%b' "$(printf '%s' "$1" | sed 's/+/ /g; s/%\(..\)/\\x\1/g')"; }

FILE=$(urldec "$(qval file)")
DEL=$(urldec "$(qval del)")

# reject absolute paths and traversal
safe() { case "$1" in "" | /* | *..*) return 1 ;; *) return 0 ;; esac }

if [ -n "$DEL" ]; then
	if safe "$DEL" && [ -f "$BASE/$DEL" ] && [ ! -L "$BASE/$DEL" ]; then
		rm -f "$BASE/$DEL"
		printf 'Content-Type: application/json\r\n\r\n{"ok":true}\n'
	else printf 'Status: 400 Bad Request\r\n\r\n'; fi
	exit 0
fi

if [ -n "$FILE" ]; then
	# reject traversal, missing files, and symlinks (a planted symlink on an
	# ext-formatted SD could otherwise exfiltrate arbitrary files)
	if ! safe "$FILE" || [ ! -f "$BASE/$FILE" ] || [ -L "$BASE/$FILE" ]; then
		printf 'Status: 404 Not Found\r\n\r\n'
		exit 0
	fi
	F="$BASE/$FILE"
	SZ=$(stat -c%s "$F" 2>/dev/null || echo 0)
	printf 'Status: 200 OK\r\n'
	printf 'Content-Type: video/mp4\r\n'
	printf 'Content-Length: %s\r\n' "$SZ"
	printf 'Content-Disposition: inline; filename="%s"\r\n' "$(basename "$F")"
	printf 'Connection: close\r\n\r\n'
	cat "$F"
	exit 0
fi

# ---- listing (newest first) ----
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n\r\n'
if [ ! -d "$BASE" ]; then
	printf '{"base":"%s","files":[]}\n' "$BASE"
	exit 0
fi
printf '{"base":"%s","files":[' "$BASE"
i=0
for f in $(find "$BASE" -type f -name '*.mp4' 2>/dev/null | sort -r); do
	rel=${f#"$BASE"/}
	# JSON-escape the filename (backslash + double-quote) so an odd name on the SD
	# can't break the JSON or inject into the WebUI.
	rel=$(printf '%s' "$rel" | sed 's/\\/\\\\/g; s/"/\\"/g')
	sz=$(stat -c%s "$f" 2>/dev/null || echo 0)
	mt=$(stat -c%Y "$f" 2>/dev/null || echo 0)
	[ $i -gt 0 ] && printf ','
	printf '{"file":"%s","size":%s,"mtime":%s}' "$rel" "$sz" "$mt"
	i=$((i + 1))
done
printf ']}\n'
