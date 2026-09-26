#!/bin/sh
# shellcheck disable=SC1091,SC2086,SC2012

. /var/www/x/auth.sh
require_auth

CONF=/etc/timps.conf
DIR=$(sed -n 's/^[[:space:]]*timelapse\.dir[[:space:]]*=[[:space:]]*"\{0,1\}\([^"#]*\).*/\1/p' "$CONF" 2>/dev/null | head -n1 | tr -d ' \t')
[ -z "$DIR" ] && DIR=/mnt/mmcblk0p1
BASE="$DIR/$(hostname)/timelapses"
REAL_BASE=$(readlink -f "$BASE" 2>/dev/null) || REAL_BASE=$BASE

qval() { printf '%s' "$QUERY_STRING" | sed -n "s/.*$1=\([^&]*\).*/\1/p"; }
urldec() { printf '%b' "$(printf '%s' "$1" | sed 's/\\/\\\\/g; s/+/ /g; s/%\(..\)/\\x\1/g')"; }

esc() { printf '%s' "$1" | tr -d '\001-\037\177' | sed 's/\\/\\\\/g; s/"/\\"/g'; }

# reject absolute paths and traversal
safe() { case "$1" in "" | /* | *..*) return 1 ;; *) return 0 ;; esac }

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
	printf 'Cache-Control: private, max-age=86400, immutable\r\n'
	printf '\r\n'
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
# -maxdepth bounds the walk to the shapes a name template can plausibly produce.
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
