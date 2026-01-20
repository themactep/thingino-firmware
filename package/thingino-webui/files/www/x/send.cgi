#!/bin/sh

http_200() {
  printf 'Status: 200 OK\r\n'
}

http_400() {
  printf 'Status: 400 Bad Request\r\n'
}

http_412() {
  printf 'Status: 412 Precondition Failed\r\n'
}

json_header() {
  printf 'Content-Type: application/json\r\n'
  printf 'Pragma: no-cache\r\n'
  printf 'Expires: %s\r\n' "$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')"
  printf 'Etag: "%s"\r\n' "$(cat /proc/sys/kernel/random/uuid)"
  printf '\r\n'
}

json_error() {
  http_412
  json_header
  printf '{"error":{"code":412,"message":"%s"}}
' "$1"
  exit 0
}

json_ok() {
  http_200
  json_header
  if [ "{" = "${1:0:1}" ]; then
    printf '{"code":200,"result":"success","message":%s}
' "$1"
  else
    printf '{"code":200,"result":"success","message":"%s"}
' "$1"
  fi
  exit 0
}

# redirect_to "url" "flash class" "flash text"
redirect_to() {
  #[ -n "$3" ] && alert_append "$2" "$3"
  echo "HTTP/1.1 303 See Other
Content-type: text/html; charset=UTF-8
Cache-Control: no-store
Pragma: no-cache
Date: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Server: $SERVER_SOFTWARE
Location: $1

"
  exit 0
}

# redirect_back "flash class" "flash text"
redirect_back() {
  redirect_to "${HTTP_REFERER:-/}" "$1" "$2"
}

urldecode() {
  local data="${1//+/ }"
  printf '%b' "${data//%/\\x}"
}

set_param_value() {
  local scope="$1" key="$2" value="$3"
  case "$key" in
    to)
      if [ "$scope" = "GET" ]; then GET_to="$value"; else POST_to="$value"; fi
      ;;
    type)
      if [ "$scope" = "GET" ]; then GET_type="$value"; else POST_type="$value"; fi
      ;;
    verbose)
      if [ "$scope" = "GET" ]; then GET_verbose="$value"; else POST_verbose="$value"; fi
      ;;
    file)
      if [ "$scope" = "GET" ]; then GET_file="$value"; else POST_file="$value"; fi
      ;;
    payload)
      if [ "$scope" = "GET" ]; then GET_payload="$value"; else POST_payload="$value"; fi
      ;;
  esac
}

WEBUI_LOG_FILE=${WEBUI_LOG_FILE:-/tmp/webui.log}
WEBUI_LOG_MAX_LINES=${WEBUI_LOG_MAX_LINES:-2000}

webui_log() {
  local log_file="$WEBUI_LOG_FILE"
  local timestamp msg line_count tmp_file
  [ -n "$1" ] || return
  timestamp=$(date +'%Y-%m-%dT%H:%M:%S%z')
  msg="$*"
  printf '%s %s\n' "$timestamp" "$msg" >> "$log_file"
  if [ "$WEBUI_LOG_MAX_LINES" -gt 0 ] && [ -f "$log_file" ]; then
    line_count=$(wc -l < "$log_file" 2>/dev/null)
    if [ -n "$line_count" ] && [ "$line_count" -gt "$WEBUI_LOG_MAX_LINES" ]; then
      tmp_file="${log_file}.$$"
      tail -n "$WEBUI_LOG_MAX_LINES" "$log_file" > "$tmp_file" && mv "$tmp_file" "$log_file"
    fi
  fi
}

parse_kv_pairs() {
  local data="$1" scope="$2" pair key value oldifs
  [ -n "$data" ] || return
  oldifs="$IFS"
  IFS='&'
  for pair in $data; do
    IFS="$oldifs"
    [ -n "$pair" ] || { IFS='&'; continue; }
    case "$pair" in
      *=*)
        key=${pair%%=*}
        value=${pair#*=}
        ;;
      *)
        key=$pair
        value=""
        ;;
    esac
    key=$(urldecode "$key")
    value=$(urldecode "$value")
    set_param_value "$scope" "$key" "$value"
    IFS='&'
  done
  IFS="$oldifs"
}

parse_post_body() {
  local len raw
  len=${CONTENT_LENGTH:-0}
  case "$len" in
    ''|*[!0-9]*) len=0 ;;
  esac
  [ "$len" -gt 0 ] || return
  raw=$(dd bs=1 count="$len" 2>/dev/null)
  parse_kv_pairs "$raw" "POST"
}

[ -n "$QUERY_STRING" ] && parse_kv_pairs "$QUERY_STRING" "GET"
if [ "${REQUEST_METHOD:-GET}" = "POST" ]; then
  parse_post_body
fi

webui_log "send.cgi: POST_to='$POST_to', POST_type='$POST_type', GET_to='$GET_to', GET_type='$GET_type'"

target=${POST_to:-$GET_to}
type=${POST_type:-$GET_type}
verbose=${POST_verbose:-$GET_verbose}

webui_log "send.cgi: resolved target='$target', type='$type', verbose='$verbose'"

verbose_flag=""
case "$verbose" in
  1|true|yes|on) verbose_flag="-v" ;;
esac

opts=""
case "$type" in
  photo) opts="-S" ;;
  video) opts="-V" ;;
  *) ;;
esac

json_escape() {
  LC_ALL=C printf '%s' "$1" \
    | tr '\r' '\n' \
    | awk ' { line=$0; gsub(/\\/,"\\\\",line); gsub(/"/,"\\\"",line); gsub(/\t/,"\\t",line); gsub(/[^ -~\t]/,"?",line); printf "%s\\n", line } '
}

run_verbose() {
  local out status out_b64
  webui_log "Running command: $*"
  if out=$("$@" 2>&1); then
    status=0
    state="success"
  else
    status=$?
    state="error"
  fi
  out_b64=$(printf '%s' "$out" | base64 | tr -d '\n')
  json_ok "{\"target\":\"$target\",\"status\":\"$state\",\"exit_code\":$status,\"output_b64\":\"$out_b64\"}"
}

case "$target" in
  telegram)
    webui_log "send.cgi: target=$target, type=$type, opts='$opts', verbose_flag='$verbose_flag'"
    if [ -n "$verbose_flag" ]; then
      if [ -n "$opts" ]; then
        webui_log "Running: send2telegram $verbose_flag $opts"
        run_verbose send2telegram $verbose_flag $opts
      else
        webui_log "Running: send2telegram $verbose_flag"
        run_verbose send2telegram $verbose_flag
      fi
    else
      if [ -n "$opts" ]; then
        webui_log "Running: send2telegram $opts"
        send2telegram $opts >/dev/null &
      else
        webui_log "Running: send2telegram"
        send2telegram >/dev/null &
      fi
      json_ok "Sent to $target"
    fi
    ;;
  email | ftp | gphotos | mqtt | nfty | storage | webhook)
    webui_log "send.cgi: target=$target, type=$type, opts='$opts', verbose_flag='$verbose_flag'"
    if [ -n "$verbose_flag" ]; then
      if [ -n "$opts" ]; then
        webui_log "Running: send2$target $verbose_flag $opts"
        run_verbose send2$target $verbose_flag $opts
      else
        webui_log "Running: send2$target $verbose_flag"
        run_verbose send2$target $verbose_flag
      fi
    else
      if [ -n "$opts" ]; then
        webui_log "Running: send2$target $opts"
        send2$target $opts >/dev/null &
      else
        webui_log "Running: send2$target"
        send2$target >/dev/null &
      fi
      json_ok "Sent to $target"
    fi
    ;;
  termbin)
    case ${POST_file:-$GET_file} in
      weblog)
        url=$(cat /tmp/webui.log | send2termbin)
        ;;
      *)
        cmd=$(echo "${POST_payload:-$GET_payload}" | base64 -d) || cmd="${POST_payload:-$GET_payload}"
        url=$($cmd | send2termbin)
        ;;
    esac
    redirect_to $url
    ;;
  *)
    redirect_back "danger" "Unknown target $target"
esac
