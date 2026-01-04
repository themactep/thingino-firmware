#!/bin/haserl
<%in _common.cgi %>
<%
. ./_json.sh

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
  email | ftp | mqtt | webhook | ntfy)
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
%>
