#!/bin/sh
# shellcheck disable=SC1091,SC2086
# json-timelapse.cgi - browse/serve the timps timelapse shots. A FILESYSTEM
# helper next to json-recordings.cgi (not a streamer bridge):
#   GET                -> JSON index of shot FOLDERS under <timelapse.dir>/<host>/timelapses
#   GET ?seq=<rel>     -> JSON frame list for ONE folder ("." = the tree root)
#   GET ?file=<rel>    -> serves that one shot as image/jpeg
# Auth-protected; seq/file are guarded against path traversal exactly the way
# json-recordings.cgi guards its file/del (safe() + within_base()).
#
# Why an index of FOLDERS and not of frames: the default name template
# (%Y%m%d/%H/%Y%m%dT%H%M%S) buckets shots into one folder per hour, so at a
# 10 s interval a 7-day tree holds ~60k JPEGs but only ~170 folders. Walking
# every file to build a global index would be the expensive part; the index
# therefore stats no files at all (the per-folder frame count falls out of a
# shell glob, no fork) and the player asks for one folder's frames at a time.

. /var/www/x/auth.sh
require_auth

CONF=/etc/timps.conf
DIR=$(sed -n 's/^[[:space:]]*timelapse\.dir[[:space:]]*=[[:space:]]*"\{0,1\}\([^"#]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \t')
[ -z "$DIR" ] && DIR=/mnt/mmcblk0p1
BASE="$DIR/$(hostname)/timelapses"
# Resolved once, used by within_base() below - if BASE itself doesn't exist
# yet (timelapse never enabled), fall back to the literal path so the index
# branch still reports an empty tree instead of erroring.
REAL_BASE=$(readlink -f "$BASE" 2>/dev/null) || REAL_BASE=$BASE

qval() { printf '%s' "$QUERY_STRING" | sed -n "s/.*$1=\([^&]*\).*/\1/p"; }
# Backslashes are doubled BEFORE the %XX -> \xHH substitution so printf '%b'
# folds an already-present literal backslash back to one instead of reading
# it as one of its own escapes (e.g. \c, "stop all output now") and
# truncating the value - same fix as json-recordings.cgi's urldec.
urldec() { printf '%b' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/+/ /g; s/%\(..\)/\\x\1/g')"; }

# JSON-escape a name that came off the SD card: backslash + double-quote, and
# drop control characters outright so an odd filename can neither break the
# JSON nor inject into the WebUI.
esc() { printf '%s' "$1" | tr -d '\001-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# reject absolute paths and traversal
safe() { case "$1" in "" | /* | *..*) return 1 ;; *) return 0 ;; esac }

# A leaf-only symlink check (-L on the requested path) catches a symlinked
# FILE but walks straight past a symlinked DIRECTORY planted anywhere under
# BASE (e.g. "timelapses/x -> /etc"), since the leaf is then an ordinary
# file. Resolving the whole path and requiring it to still be under BASE
# closes that. within_base_dir also accepts BASE itself, which is the "."
# sequence (a flat name template writes shots straight into the root).
within_base() {
	resolved=$(readlink -f "$1" 2>/dev/null) || return 1
	case "$resolved" in
		"$REAL_BASE"/*) return 0 ;;
		*) return 1 ;;
	esac
}
within_base_dir() {
	resolved=$(readlink -f "$1" 2>/dev/null) || return 1
	[ "$resolved" = "$REAL_BASE" ] && return 0
	case "$resolved" in
		"$REAL_BASE"/*) return 0 ;;
		*) return 1 ;;
	esac
}

not_found() {
	printf 'Status: 404 Not Found\r\n\r\n'
	exit 0
}

FILE=$(urldec "$(qval file)")
SEQ=$(urldec "$(qval seq)")

# ---- one shot (the hot path: the player asks for these back to back) ----
if [ -n "$FILE" ]; then
	# extension whitelist on top of within_base: even inside the tree this
	# endpoint can only ever hand out a JPEG.
	case "$FILE" in *.jpg | *.JPG | *.jpeg | *.JPEG) ;; *) not_found ;; esac
	if ! safe "$FILE" || [ ! -f "$BASE/$FILE" ] || [ -L "$BASE/$FILE" ] || ! within_base "$BASE/$FILE"; then
		not_found
	fi
	F="$BASE/$FILE"
	SZ=$(stat -c%s "$F" 2>/dev/null || echo 0)
	printf 'Status: 200 OK\r\n'
	printf 'Content-Type: image/jpeg\r\n'
	printf 'Content-Length: %s\r\n' "$SZ"
	printf 'Content-Disposition: inline; filename="%s"\r\n' "$(basename "$F")"
	# Shots are write-once (timps writes to .tmp and renames, and retention
	# only ever DELETES), so they are safely cacheable - which is what makes
	# the player's look-ahead prefetch free: the <img> src swap then hits the
	# browser cache instead of the SD card. "private" keeps an intermediary
	# from storing an auth-protected image.
	printf 'Cache-Control: private, max-age=86400, immutable\r\n'
	printf 'Connection: close\r\n\r\n'
	cat "$F"
	exit 0
fi

# ---- frames of ONE folder ----
if [ -n "$SEQ" ]; then
	D="$BASE/$SEQ"
	if ! safe "$SEQ" || [ ! -d "$D" ] || ! within_base_dir "$D"; then
		not_found
	fi
	printf 'Content-Type: application/json\r\n'
	printf 'Cache-Control: no-store\r\n\r\n'
	printf '{"base":"%s","seq":"%s","frames":[' "$(esc "$BASE")" "$(esc "$SEQ")"
	# ONE ls fork for the whole folder, whatever the frame count: a per-file
	# stat would be ~1440 forks for an hour at the default interval. Sizes
	# come out of the same listing; the player derives each frame's timestamp
	# from its name, so no mtime is needed. Names are sorted again client
	# side, so ls's own ordering is not relied upon.
	LC_ALL=C ls -lnA "$D" 2>/dev/null | awk '
function escape(str) {
  gsub(/\\/, "\\\\", str)
  gsub(/"/, "\\\"", str)
  gsub(/[\001-\037\177]/, "", str)
  return str
}
$1 == "total" { next }
substr($1, 1, 1) != "-" { next }
{
  name = ""
  for (i = 9; i <= NF; i++) name = name (i == 9 ? "" : OFS) $i
  if (name !~ /\.[Jj][Pp][Ee]?[Gg]$/) next
  if (n++) printf(",")
  printf("{\"f\":\"%s\",\"s\":%s}", escape(name), $5 + 0)
}'
	printf ']}\n'
	exit 0
fi

# ---- index: folders that actually hold shots ----
printf 'Content-Type: application/json\r\n'
printf 'Cache-Control: no-store\r\n\r\n'
if [ ! -d "$BASE" ]; then
	printf '{"base":"%s","exists":false,"seqs":[]}\n' "$(esc "$BASE")"
	exit 0
fi
printf '{"base":"%s","exists":true,"seqs":[' "$(esc "$BASE")"
# -maxdepth bounds the walk to the shapes a name template can plausibly
# produce. The `set --` glob both tests "does this folder hold shots" and
# yields the count in $# without a single fork; a `while read` (rather than
# `for d in $(find ...)`) keeps folder names with spaces intact.
find "$BASE" -maxdepth 4 -type d 2>/dev/null | sort | (
	i=0
	while IFS= read -r d; do
		# Match the same 4 case variants ?file=/?seq= already accept. No
		# nullglob in busybox ash, so count via builtin -e tests, not $#.
		set -- "$d"/*.jpg "$d"/*.JPG "$d"/*.jpeg "$d"/*.JPEG
		n=0
		for f in "$@"; do
			[ -e "$f" ] && n=$((n + 1))
		done
		[ "$n" -gt 0 ] || continue
		rel=${d#"$BASE"}
		rel=${rel#/}
		[ -z "$rel" ] && rel="."
		[ $i -gt 0 ] && printf ','
		printf '{"seq":"%s","frames":%s}' "$(esc "$rel")" "$n"
		i=$((i + 1))
	done
)
printf ']}\n'
