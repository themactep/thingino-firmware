#!/bin/sh

. /usr/share/common

TAB_LIST="crontab dmesg httpd logcat logread lsmod netstat onvif prudynt status system top weblog"

button_restore_from_rom() {
  [ -f "/rom/$1" ] || return 1

  if [ -z "$(diff "/rom/$1" "$1")" ]; then
    printf '<p class="small fst-italic">File matches the version in ROM.</p>'
    return 1
  fi

  printf '<p><a class="btn btn-danger" href="restore.cgi?f=%s">Replace %s with its version from ROM</a></p>' "$1" "$1"
}

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
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

button_restore_from_rom() {
  local target="$1"
  [ -f "/rom/$target" ] || return 0

  if diff -q "/rom/$target" "$target" >/dev/null 2>&1; then
    printf '<p class="small fst-italic">File matches the version in ROM.</p>'
    return 0
  fi

  printf '<p><a class="btn btn-danger" href="/x/restore.cgi?f=%s">Replace %s with its version from ROM</a></p>' "$target" "$target"
}

collect_outputs() {
  local commands="$1" entries="" first=1
  local oldifs="$IFS" output output_b64
  IFS=';'
  for c in $commands; do
    c=$(printf '%s' "$c" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
    [ -z "$c" ] && continue
    output=$(eval "$c" 2>&1)
    output_b64=$(printf '%s' "$output" | base64 | tr -d '\n')
    if [ $first -eq 0 ]; then
      entries="$entries,"
    fi
    entries="$entries{\"command\":\"$(json_escape "$c")\",\"output_base64\":\"$(json_escape "$output_b64")\"}"
    first=0
  done
  IFS="$oldifs"
  printf '[%s]' "$entries"
}

tabs_json() {
  local first=1 json="["
  for tab in $TAB_LIST; do
    if [ $first -eq 0 ]; then
      json="$json,"
    fi
    json="$json{\"id\":\"$(json_escape "$tab")\",\"label\":\"$(json_escape "$tab")\"}"
    first=0
  done
  printf '%s]' "$json"
}

parse_section() {
  local qs="$QUERY_STRING" key value
  if [ -z "$qs" ]; then
    name="system"
    return
  fi

  case "$qs" in
    *=*)
      for part in $(printf '%s' "$qs" | tr '&' '\n'); do
        case "$part" in
          name=*|section=*|tab=*)
            value="${part#*=}"
            break
            ;;
        esac
      done
      [ -z "$value" ] && value="${qs%%&*}"
      ;;
    *)
      value="$qs"
      ;;
  esac

  value=$(urldecode "$value")
  [ -n "$value" ] && name="$value" || name="system"
}

is_valid_section() {
  for tab in $TAB_LIST; do
    [ "$tab" = "$1" ] && return 0
  done
  return 1
}

resolve_commands() {
  case "$1" in
    dmesg|logcat|logread|lsmod)
      cmd="$1"
      ;;
    crontab)
      cmd="crontab -l"
      extras=$(cat <<'EOF'
<p><a href="https://devhints.io/cron">Cron syntax cheatsheet</a></p>
<p><a class="btn btn-warning" href="/x/texteditor.cgi?f=/etc/cron/crontabs/root">Edit file</a></p>
EOF
)
      ;;
    httpd)
      cmd="cat /etc/httpd.conf; printenv"
      extras=$(button_restore_from_rom "/etc/httpd.conf")
      ;;
    netstat)
      cmd="netstat -a"
      ;;
    onvif)
      cmd="cat /etc/onvif.json"
      extras=$(button_restore_from_rom "/etc/onvif.json")
      ;;
    prudynt)
      cmd="cat /etc/prudynt.json"
      extras=$(button_restore_from_rom "/etc/prudynt.json")
      ;;
    status)
      cmd="uptime; df -T; cat /proc/meminfo | grep Mem"
      ;;
    system)
      cmd="cat /etc/os-release"
      ;;
    top)
      cmd="top -n 1 -b"
      ;;
    weblog)
      cmd="cat /tmp/webui.log"
      ;;
    *)
      cmd="true"
      ;;
  esac
}

handle_get() {
  parse_section
  if ! is_valid_section "$name"; then
    name="system"
  fi

  extras=""
  resolve_commands "$name"

  output_json=$(collect_outputs "$cmd")
  tabs=$(tabs_json)
  extras_b64=$(printf '%s' "$extras" | base64 | tr -d '\n')

  payload=$(cat <<EOF
{
  "selected": "$(json_escape "$name")",
  "commands": $output_json,
  "tabs": $tabs,
  "extras_html_base64": "$(json_escape "$extras_b64")"
}
EOF
)

  send_json "$payload"
}

case "$REQUEST_METHOD" in
  GET|"")
    handle_get
    ;;
  *)
    json_error 405 "Method not allowed" "405 Method Not Allowed"
    ;;
esac

