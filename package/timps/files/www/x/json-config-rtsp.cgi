#!/bin/sh
# json-config-rtsp.cgi - timps flavour of the stock thingino-webui CGI.
#
# The stock version reads/writes /etc/prudynt.json, a file no timps image ever
# ships, so on a timps camera it reports empty ports/endpoints and its POST
# writes prudynt keys nothing reads before restarting a "prudynt" service that
# does not exist. This copy sources everything from the files a timps image
# really has:
#
#   /etc/timps.conf   rtsp.user / rtsp.pass / rtsp.port / rtsp.tls / rtsp.tls_port
#                     video0.rtsp_path / video1.rtsp_path
#   /etc/onvif.json   server.port  (written by S96onvif_discovery)
#
# WHY A CGI AT ALL, when every other timps page talks to /control directly:
# rtsp.* credentials are deliberately NOT exposed there. GET /control never
# emits an "rtsp" section, and rtsp.user/rtsp.pass carry no F_CTRL flag, which
# is timps' mandatory per-field allowlist for POST /control - see the comment
# above apply_ctrl_fields() in timps src/control.c, which names "every rtsp.* /
# http.* credential/token" as intentionally unreachable from the network API.
# Reading or changing them therefore has to happen on the camera, in a
# session-authenticated CGI, exactly like the board-script config that
# config-photosensing.js still loads from /x/json-config-daynight.cgi.
# a/config-rtsp.js pairs this with a live GET /control for the mount paths.
#
# ONVIF credentials are NOT written here: S96onvif_discovery regenerates
# /etc/onvif.json from timps.conf's rtsp.user/rtsp.pass on every start, so
# writing timps.conf and restarting that service is what keeps the two in sync
# (writing onvif.json directly would be overwritten on the next boot).

# Check authentication
. /var/www/x/auth.sh
require_auth

CONF="/etc/timps.conf"
ONVIF_CONFIG="/etc/onvif.json"

emit_json() {
  status="$1"
  [ -n "$status" ] && printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache
Connection: close

$2
EOF
  exit 0
}

json_escape() {
  printf '%s' "$1" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g'
}

json_error() {
  emit_json "${1:-400 Bad Request}" \
    "$(printf '{"error":{"code":"%s","message":"%s"}}' \
       "$(json_escape "${3:-error}")" "$(json_escape "$2")")"
}

# ---------------------------------------------------------------- reading ---
# Flat "key = value" reader, identical to the one S96onvif_discovery uses (and
# matching timps' own parser in config.c): capture the whole value, strip an
# inline comment only when the '#' is preceded by whitespace, trim, unquote.
timps_conf_get() {
  esc=$(echo "$1" | sed 's/[.[\*^$]/\\&/g')
  sed -n "s/^[[:space:]]*${esc}[[:space:]]*=[[:space:]]*\(.*\)$/\1/p" \
    "$CONF" 2>/dev/null | head -n1 \
    | sed 's/[[:space:]]\{1,\}#.*$//; s/[[:space:]]*$//; s/^"\(.*\)"$/\1/; s/^'\''\(.*\)'\''$/\1/'
}

timps_bool() {
  case "$(timps_conf_get "$1" | tr 'A-Z' 'a-z')" in
    true | yes | 1 | on) echo 1 ;;
    *) echo 0 ;;
  esac
}

read_config() {
  username=$(timps_conf_get rtsp.user)
  password=$(timps_conf_get rtsp.pass)

  if [ "$(timps_bool rtsp.tls)" = "1" ]; then
    rtsp_scheme="rtsps"
    rtsp_port=$(timps_conf_get rtsp.tls_port); [ -n "$rtsp_port" ] || rtsp_port="322"
  else
    rtsp_scheme="rtsp"
    rtsp_port=$(timps_conf_get rtsp.port); [ -n "$rtsp_port" ] || rtsp_port="554"
  fi

  # Mount points. a/config-rtsp.js overrides these with the LIVE values from
  # GET /control (videoN.rtsp_path is runtime-mutable); these are the fallback
  # for when the daemon is unreachable, and carry timps' compiled-in defaults
  # (config.c) for when the keys are absent from the file.
  rtsp_ch0=$(timps_conf_get video0.rtsp_path); [ -n "$rtsp_ch0" ] || rtsp_ch0="/ch0"
  rtsp_ch1=$(timps_conf_get video1.rtsp_path); [ -n "$rtsp_ch1" ] || rtsp_ch1="/ch1"
  rtsp_ch0="${rtsp_ch0#/}"
  rtsp_ch1="${rtsp_ch1#/}"

  onvif_port=$(jct "$ONVIF_CONFIG" get server.port 2>/dev/null)
  [ -n "$onvif_port" ] && [ "$onvif_port" != "null" ] || onvif_port="80"
}

send_config() {
  # "rtsp_mic" is deliberately absent: timps serves no audio-only mount point.
  # rtsp.c's find_video_by_path() matches videoN.rtsp_path and otherwise falls
  # back to the first enabled VIDEO stream, so a /mic URL would silently hand
  # out ch0 rather than microphone audio. The page states that instead of
  # printing a URL that does not do what it says.
  printf '{"username":"%s","password":"%s","onvif_port":"%s","rtsp_scheme":"%s","rtsp_port":"%s","rtsp_ch0":"%s","rtsp_ch1":"%s","rtsp_enabled":%s,"rtsp_mic_supported":false}\n' \
    "$(json_escape "$username")" \
    "$(json_escape "$password")" \
    "$(json_escape "$onvif_port")" \
    "$(json_escape "$rtsp_scheme")" \
    "$(json_escape "$rtsp_port")" \
    "$(json_escape "$rtsp_ch0")" \
    "$(json_escape "$rtsp_ch1")" \
    "$(timps_bool rtsp.enabled)"
}

# ---------------------------------------------------------------- writing ---
cleanup() { [ -n "$req_file" ] && rm -f "$req_file"; }
trap cleanup EXIT

read_body() {
  req_file=$(mktemp /tmp/config-rtsp-body.XXXXXX) || json_error "500 Internal Server Error" "Cannot create temp file" "temp_failed"
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$req_file"
  else
    cat >"$req_file"
  fi
}

# Reject anything that would not survive a timps.conf write/read round trip.
# config.c's loader trims, then cuts the value at a whitespace-preceded '#',
# THEN unquotes - so a '#' breaks the value even inside quotes, and a value
# both starting and ending with a quote character loses those characters. The
# daemon's own writer (write_kv_line) additionally maps control characters to
# spaces and '"' to '\''. Refusing those inputs up front is honest: the
# operator is told the password is unusable instead of silently getting a
# different one stored than the one typed.
validate_password() {
  case "$1" in
    *'#'* ) json_error "400 Bad Request" "Password may not contain '#' (timps.conf comment marker)." "invalid_password" ;;
    *'"'* ) json_error "400 Bad Request" "Password may not contain a double quote." "invalid_password" ;;
    ' '* | *' ' | "	"* | *"	" ) json_error "400 Bad Request" "Password may not start or end with whitespace." "invalid_password" ;;
    "'"*"'" ) json_error "400 Bad Request" "Password may not both start and end with a single quote." "invalid_password" ;;
  esac
  # control characters (a newline would inject a whole new config line)
  if printf '%s' "$1" | tr -d '\40-\176' | grep -q .; then
    json_error "400 Bad Request" "Password may only contain printable ASCII." "invalid_password"
  fi
  [ "${#1}" -ge 4 ] || json_error "400 Bad Request" "Password must be at least 4 characters." "invalid_password"
  [ "${#1}" -le 120 ] || json_error "400 Bad Request" "Password must be at most 120 characters." "invalid_password"
}

# Replace (or append) the single "rtsp.pass = value" line, preserving every
# other line, comment and the file order - the shell equivalent of the daemon's
# config_write_keys(). Written to a temp file in /etc and renamed, so a failure
# mid-write can never leave a truncated /etc/timps.conf behind (an unreadable
# config would take the streamer down on the next boot). The value travels
# through the environment, never through awk -v or a sed replacement, so no
# character in it can be re-interpreted as syntax.
update_password() {
  new_password=$(jct "$req_file" get password 2>/dev/null)
  [ -n "$new_password" ] || json_error "400 Bad Request" "Password is required" "missing_password"
  validate_password "$new_password"

  [ -f "$CONF" ] || json_error "500 Internal Server Error" "$CONF is missing" "no_config"

  tmp=$(mktemp /etc/.timps.conf.XXXXXX) || json_error "500 Internal Server Error" "Cannot write to /etc" "temp_failed"
  chmod 600 "$tmp"

  CONF_VAL="$new_password" awk '
    BEGIN {
      v = ENVIRON["CONF_VAL"]
      # quote exactly when the daemon own writer (write_kv_line) would
      if (v == "" || v ~ /^[ \t]/ || v ~ /[ \t]$/ || substr(v,1,1) == "#" || index(v, " ") > 0)
        val = "\"" v "\""
      else
        val = v
      done = 0
    }
    /^[ \t]*rtsp\.pass[ \t]*=/ {
      if (!done) { print "rtsp.pass    = " val; done = 1 }
      next                       # drop later duplicates, like config_write_keys()
    }
    { print }
    END { if (!done) print "rtsp.pass    = " val }
  ' "$CONF" >"$tmp" || { rm -f "$tmp"; json_error "500 Internal Server Error" "Failed to rewrite $CONF" "write_failed"; }

  # Never install an obviously broken config: the rewrite must still contain
  # every other key it started with (awk only ever drops rtsp.pass duplicates).
  before=$(grep -c '=' "$CONF" 2>/dev/null)
  after=$(grep -c '=' "$tmp" 2>/dev/null)
  if [ -z "$after" ] || [ "$after" -lt 1 ] || [ "$after" -lt "$((before - 4))" ]; then
    rm -f "$tmp"
    json_error "500 Internal Server Error" "Refusing to install a truncated config" "write_failed"
  fi

  chmod 644 "$tmp"
  mv -f "$tmp" "$CONF" || { rm -f "$tmp"; json_error "500 Internal Server Error" "Failed to replace $CONF" "write_failed"; }

  # rtsp.user/rtsp.pass are read straight off the live ms_config on every RTSP
  # request but are not runtime-writable, so the daemon has to be restarted to
  # pick the new file value up. onvif_discovery regenerates /etc/onvif.json
  # (server.username/server.password) from the same two keys on start, and
  # onvif_notify re-reads that file, so both follow.
  restarted=""
  if command -v service >/dev/null 2>&1; then
    for svc in timps onvif_discovery onvif_notify; do
      if service restart "$svc" >/dev/null 2>&1; then
        restarted="$restarted $svc"
      fi
    done
  fi

  emit_json "" "$(printf '{"status":"ok","restarted":"%s"}' \
    "$(json_escape "${restarted# }")")"
}

case "$REQUEST_METHOD" in
  POST)
    read_body
    update_password
    ;;
  GET | "")
    read_config
    emit_json "" "$(send_config)"
    ;;
  *)
    json_error "405 Method Not Allowed" "Unsupported method" "unsupported_method"
    ;;
esac
