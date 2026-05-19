#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

json_escape() {
	printf '%s' "$1" | sed \
		-e 's/\\/\\\\/g' \
		-e 's/"/\\"/g' \
		-e "s/\r/\\r/g" \
		-e "s/\n/\\n/g"
}

send_json() {
	status="${2:-200 OK}"
	printf 'Status: %s\n' "$status"
	cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$1
EOF
	exit 0
}

json_error() {
	code="${1:-400}"
	message="$2"
	send_json "{\"error\":{\"code\":$code,\"message\":\"$(json_escape "$message")\"}}" "${3:-400 Bad Request}"
}

urldecode() {
	printf '%b' "$(echo "$1" | sed 's/+/ /g; s/%\([0-9A-Fa-f][0-9A-Fa-f]\)/\\x\1/g')"
}

get_param() {
	local key="$1" qs="$QUERY_STRING" pair value
	[ -z "$qs" ] && return 1

	local oldifs="$IFS"
	IFS='&'
	for pair in $qs; do
		IFS="$oldifs"
		case "$pair" in
			"$key"=*)
				value="${pair#*=}"
				urldecode "$value"
				IFS="$oldifs"
				return 0
				;;
			"$key")
				printf ''
				IFS="$oldifs"
				return 0
				;;
		esac
		IFS='&'
	done
	IFS="$oldifs"
	return 1
}

handle_range_response() {
	local file="$1"
	if [ ! -f "$file" ]; then
		printf 'Status: 404 Not Found\r\n'
		printf 'Content-Type: text/plain\r\n\r\n'
		printf 'File %s not found' "$file"
		exit 0
	fi

	local length start end blocksize
	length=$(stat -c%s "$file") || length=0

	if ! env | grep -q '^HTTP_RANGE'; then
		printf 'Status: 200 OK\r\n'
		printf 'Content-Type: video/mp4\r\n'
		printf 'Accept-Ranges: bytes\r\n'
		printf 'Content-Length: %s\r\n' "$length"
		printf 'Content-Disposition: attachment; filename=%s\r\n' "$(basename "$file")"
		printf 'Cache-Control: no-store\r\n'
		printf 'Pragma: no-cache\r\n'
		printf '\r\n'
		cat "$file"
		exit 0
	fi

	start=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $3}')
	[ -z "$start" ] && start=0

	if [ "$start" -gt "$length" ]; then
		printf 'HTTP/1.1 416 Requested Range Not Satisfiable\r\n'
		printf 'Content-Range: bytes */%s\r\n' "$length"
		printf '\r\n'
		exit 0
	fi

	end=$(env | awk -F'[=-]' '/^HTTP_RANGE=/{print $4}')
	[ -z "$end" ] && end=$((length - 1))
	blocksize=$((end - start + 1))

	printf 'Status: 206 Partial Content\r\n'
	printf 'Content-Range: bytes %s-%s/%s\r\n' "$start" "$end" "$length"
	printf 'Content-Length: %s\r\n' "$blocksize"
	printf 'Content-Type: video/mp4\r\n'
	printf 'Accept-Ranges: bytes\r\n'
	printf 'Content-Disposition: attachment; filename=%s\r\n' "$(basename "$file")"
	printf 'Cache-Control: no-store\r\n'
	printf 'Pragma: no-cache\r\n'
	printf '\r\n'
	dd if="$file" skip=$start bs=$blocksize count=1 iflag=skip_bytes 2>/dev/null
	exit 0
}

handle_download() {
	local file="$1"
	if [ ! -f "$file" ]; then
		printf 'Status: 404 Not Found\r\n'
		printf 'Content-Type: text/plain\r\n\r\n'
		printf 'File %s not found' "$file"
		exit 0
	fi

	local length modified timestamp server
	length=$(stat -c%s "$file") || length=0
	modified=$(stat -c%Y "$file") || modified=0
	timestamp=$(TZ=GMT0 date +"%a, %d %b %Y %T %Z" --date="@$modified")
	server="${SERVER_SOFTWARE:-thingino}"

	printf 'Status: 200 OK\r\n'
	printf 'Date: %s\r\n' "$timestamp"
	printf 'Server: %s\r\n' "$server"
	printf 'Content-Type: application/octet-stream\r\n'
	printf 'Content-Length: %s\r\n' "$length"
	printf 'Content-Disposition: attachment; filename=%s\r\n' "$(basename "$file")"
	printf 'Cache-Control: no-store\r\n'
	printf 'Pragma: no-cache\r\n'
	printf '\r\n'
	cat "$file"
	exit 0
}

build_breadcrumbs() {
	local path="$1" json='[{"label":"Home","path":"/"}' accum=""
	local rel="${path#/}"
	[ -z "$rel" ] && {
		printf '%s]' "$json"
		return
	}

	local oldifs="$IFS"
	IFS='/'
	for part in $rel; do
		[ -z "$part" ] && continue
		accum="$accum/$part"
		json="$json,{\"label\":\"$(json_escape "$part")\",\"path\":\"$(json_escape "$accum")\"}"
	done
	IFS="$oldifs"
	printf '%s]' "$json"
}

list_entries() {
	local target="$1" json
	[ -d "$target" ] || return 1

	json=$(LC_ALL=C ls -lnA "$target" 2>/dev/null | awk -v base="$target" '
BEGIN {
  dir_count = 0
  file_count = 0
}
function escape(str) {
  gsub(/\\/, "\\\\", str)
  gsub(/"/, "\\\"", str)
  gsub(/\r/, "\\r", str)
  gsub(/\n/, "\\n", str)
  return str
}
$1 == "total" { next }
{
  perm = $1
  size = $5
  timestamp = $6 " " $7 " " $8
  name = ""
  for (i = 9; i <= NF; i++) {
    name = name (i == 9 ? "" : OFS) $i
  }
  if (name == "") next

  link_target = ""
  if (substr(perm, 1, 1) == "l") {
    split(name, parts, / -> /)
    name = parts[1]
    if (length(parts) > 1) {
      link_target = parts[2]
    }
  }

  path = base "/" name
  gsub(/\/+/, "/", path)

  is_dir = substr(perm, 1, 1) == "d" ? "true" : "false"
  is_link = substr(perm, 1, 1) == "l" ? "true" : "false"
  if (is_dir == "true") size = "-"

  record = sprintf("{\"name\":\"%s\",\"path\":\"%s\",\"size\":\"%s\",\"perm\":\"%s\",\"time\":\"%s\",\"is_dir\":%s,\"is_link\":%s,\"link_target\":\"%s\",\"deletable\":%s}", escape(name), escape(path), escape(size), escape(perm), escape(timestamp), is_dir, is_link, escape(link_target), (path ~ /^\/(mnt|media)\//) ? "true" : "false")

  if (is_dir == "true") {
    dirs[++dir_count] = record
  } else {
    files[++file_count] = record
  }
}
END {
  count = 0
  for (i = 1; i <= dir_count; i++) {
    if (count++) printf(",")
    printf("%s", dirs[i])
  }
  for (i = 1; i <= file_count; i++) {
    if (count++) printf(",")
    printf("%s", files[i])
  }
}
') || return 1

	printf '[%s]' "$json"
}

play_param=$(get_param "play")
if [ -n "$play_param" ]; then
	handle_range_response "$play_param"
fi

dl_param=$(get_param "dl")
if [ -n "$dl_param" ]; then
	handle_download "$dl_param"
fi

rm_param=$(get_param "rm")
if [ -n "$rm_param" ]; then
	if [ "$REQUEST_METHOD" != "POST" ]; then
		json_error 405 "Method not allowed" "405 Method Not Allowed"
	fi
	resolved_file=$(cd "$(dirname "$rm_param")" 2>/dev/null && echo "$(pwd -P)/$(basename "$rm_param")") || json_error 404 "File not found" "404 Not Found"
	case "$resolved_file" in
		/mnt/* | /media/*) ;;
		*) json_error 403 "Deletion only allowed on mounted partitions" "403 Forbidden" ;;
	esac
	if [ ! -e "$resolved_file" ]; then
		json_error 404 "File not found" "404 Not Found"
	fi
	if rm -f "$resolved_file" 2>/dev/null; then
		send_json '{"result":"ok"}'
	else
		json_error 500 "Failed to delete file"
	fi
fi

if [ -n "$REQUEST_METHOD" ] && [ "$REQUEST_METHOD" != "GET" ]; then
	json_error 405 "Method not allowed" "405 Method Not Allowed"
fi

cd_param=$(get_param "cd")
target_dir="${cd_param:-/}"

resolved_dir=$(cd "$target_dir" 2>/dev/null && pwd -P) || json_error 404 "Directory not found" "404 Not Found"
dir=$(printf '%s' "$resolved_dir" | sed 's#///*#/#g')

entries_json=$(list_entries "$dir") || json_error 500 "Unable to list directory"
breadcrumbs_json=$(build_breadcrumbs "$dir")
parent=$(dirname "$dir")
[ -n "$parent" ] || parent="/"

payload=$(
	cat <<EOF
{
  "directory": "$(json_escape "$dir")",
  "parent": "$(json_escape "$parent")",
  "breadcrumbs": $breadcrumbs_json,
  "entries": $entries_json
}
EOF
)

send_json "$payload"
