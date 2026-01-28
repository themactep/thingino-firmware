#!/bin/sh

# Source common functions if available (for thingino environment)
[ -f /usr/share/common ] && . /usr/share/common

json_escape() {
  # Simple but effective JSON escaping using printf and sed
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/	/\\t/g' \
    -e 's/\r/\\r/g' \
    -e ':a;N;$!ba;s/\n/\\n/g'
}

send_json() {
  status="${2:-200 OK}"
  printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

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
  local data="$1"
  # Replace + with space using sed
  data=$(printf '%s' "$data" | sed 's/+/ /g')
  # Decode %XX sequences using a loop
  local result="" char
  while [ -n "$data" ]; do
    case "$data" in
      %[0-9A-Fa-f][0-9A-Fa-f]*)
        # Extract hex digits and convert to character
        hex="${data#%}"
        hex="${hex%"${hex#??}"}"
        char=$(printf "\\$(printf '%03o' "0x$hex")" 2>/dev/null || printf '%')
        result="$result$char"
        data="${data#%??}"
        ;;
      *)
        # Take first character
        char="${data%"${data#?}"}"
        result="$result$char"
        data="${data#?}"
        ;;
    esac
  done
  printf '%s' "$result"
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

# Check if file is likely a text file
is_text_file() {
  local file="$1"

  # Check by extension first
  case "${file##*.}" in
    txt|log|conf|config|cfg|ini|json|xml|html|htm|css|js|sh|py|pl|rb|c|cpp|h|hpp|java|md|rst|csv|sql|yaml|yml|service|mount|target)
      return 0
      ;;
  esac

  # For files without extension or unknown extensions, do a more thorough check
  if command -v file >/dev/null 2>&1; then
    file_type=$(file -b "$file" 2>/dev/null)
    case "$file_type" in
      *"text"*|*"ASCII"*|*"UTF-8"*|*"empty"*|*"script"*)
        return 0
        ;;
    esac
  fi

  # Check file size - refuse very large files that might cause issues
  local size
  size=$(stat -c%s "$file" 2>/dev/null) || size=0
  [ "$size" -eq 0 ] && return 0  # Empty files are text
  [ "$size" -gt 1048576 ] && return 1  # Files > 1MB are likely binary

  # Final fallback: check first 512 bytes for null bytes or too many non-printable chars
  if command -v head >/dev/null 2>&1; then
    local sample null_count nonprint_count total_count
    sample=$(head -c 512 "$file" 2>/dev/null) || return 1
    total_count=$(printf '%s' "$sample" | wc -c)
    [ "$total_count" -eq 0 ] && return 0

    null_count=$(printf '%s' "$sample" | tr -cd '\000' | wc -c)
    [ "$null_count" -gt 0 ] && return 1

    nonprint_count=$(printf '%s' "$sample" | tr -cd '[:cntrl:]' | tr -d '\n\t\r' | wc -c)
    # Allow up to 5% non-printable characters
    [ "$nonprint_count" -gt $((total_count / 20)) ] && return 1
  fi

  return 0
}

# Handle file reading
handle_read() {
  local file="$1"

  if [ ! -f "$file" ]; then
    json_error 404 "File not found"
  fi

  if [ ! -r "$file" ]; then
    json_error 403 "Permission denied reading file"
  fi

  if ! is_text_file "$file"; then
    json_error 400 "File appears to be binary and cannot be edited as text"
  fi

  local size lines content
  size=$(stat -c%s "$file" 2>/dev/null) || size=0

  # Limit file size for editing (1MB max)
  if [ "$size" -gt 1048576 ]; then
    json_error 413 "File too large for editing (max 1MB)"
  fi

  # Read file content with better error handling
  if ! content=$(cat "$file" 2>/dev/null); then
    json_error 500 "Failed to read file content"
  fi

  # Double-check for null bytes in content which would break JSON
  if printf '%s' "$content" | tr -cd '\000' | wc -c | grep -q '^[1-9]'; then
    json_error 400 "File contains binary data and cannot be edited as text"
  fi

  # Encode content as base64 to avoid JSON escaping issues
  content_base64=$(printf '%s' "$content" | base64 -w 0)

  lines=$(printf '%s' "$content" | wc -l)
  [ -z "$content" ] && lines=0

  send_json "{
    \"file\": \"$(json_escape "$file")\",
    \"content\": \"$content_base64\",
    \"content_encoding\": \"base64\",
    \"size\": $size,
    \"lines\": $lines,
    \"writable\": $([ -w "$file" ] && echo true || echo false)
  }"
}

# Handle backup download
handle_backup() {
  local file="$1"

  if [ ! -f "$file" ]; then
    printf 'Status: 404 Not Found\r\n'
    printf 'Content-Type: text/plain\r\n\r\n'
    printf 'File %s not found' "$file"
    exit 0
  fi

  if [ ! -r "$file" ]; then
    printf 'Status: 403 Forbidden\r\n'
    printf 'Content-Type: text/plain\r\n\r\n'
    printf 'Permission denied reading file %s' "$file"
    exit 0
  fi

  local length modified timestamp server filename
  length=$(stat -c%s "$file" 2>/dev/null) || length=0
  modified=$(stat -c%Y "$file") || modified=$(date +%s)
  timestamp=$(date +"%Y%m%d_%H%M%S" --date="@$modified")
  server="${SERVER_SOFTWARE:-thingino}"
  filename="$(basename "$file").backup_${timestamp}"

  printf 'Status: 200 OK\r\n'
  printf 'Server: %s\r\n' "$server"
  printf 'Content-Type: application/octet-stream\r\n'
  printf 'Content-Length: %s\r\n' "$length"
  printf 'Content-Disposition: attachment; filename=%s\r\n' "$filename"
  printf 'Cache-Control: no-store\r\n'
  printf 'Pragma: no-cache\r\n'
  printf '\r\n'
  cat "$file"
  exit 0
}

# Handle file writing
handle_write() {
  local file="$1"

  if [ ! -f "$file" ]; then
    json_error 404 "File not found"
  fi

  if [ ! -w "$file" ]; then
    json_error 403 "Permission denied writing to file"
  fi

  # Read the content from POST data
  local content
  content=$(cat)

  # Write new content directly (no backup on device)
  if printf '%s' "$content" > "$file" 2>/dev/null; then
    local new_size new_lines
    new_size=$(stat -c%s "$file" 2>/dev/null) || new_size=0
    new_lines=$(printf '%s' "$content" | wc -l)
    [ -z "$content" ] && new_lines=0

    send_json "{
      \"success\": true,
      \"file\": \"$(json_escape "$file")\",
      \"size\": $new_size,
      \"lines\": $new_lines
    }"
  else
    json_error 500 "Failed to write file"
  fi
}

# Main request handling
file_param=$(get_param "file")
if [ -z "$file_param" ]; then
  json_error 400 "File parameter required"
fi

# Resolve and validate file path
if ! resolved_file=$(cd "$(dirname "$file_param")" 2>/dev/null && pwd -P)/$(basename "$file_param"); then
  json_error 404 "Invalid file path"
fi

# Check for backup download request
backup_param=$(get_param "backup")
if [ -n "$backup_param" ]; then
  handle_backup "$resolved_file"
fi

case "$REQUEST_METHOD" in
  "GET")
    handle_read "$resolved_file"
    ;;
  "POST")
    handle_write "$resolved_file"
    ;;
  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
esac
