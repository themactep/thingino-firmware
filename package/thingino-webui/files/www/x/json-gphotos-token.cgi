#!/bin/sh
# Exchange a Google OAuth authorization code for refresh/access tokens

set -e

send_json() {
  printf '%s\n' "$1"
}

echo "Content-Type: application/json"
echo

if ! command -v curl >/dev/null 2>&1; then
  send_json '{"error":"curl_missing","message":"curl is required to contact Google APIs"}'
  exit 0
fi

req_file=$(mktemp /tmp/gphotos-auth.XXXXXX)
resp_file=$(mktemp /tmp/gphotos-auth-resp.XXXXXX)
cleanup() {
  rm -f "$req_file" "$resp_file"
}
trap cleanup EXIT

if [ -n "$CONTENT_LENGTH" ]; then
  dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$req_file"
else
  cat >"$req_file"
fi

read_field() {
  jct "$req_file" get "$1" 2>/dev/null
}

client_id=$(read_field client_id)
client_secret=$(read_field client_secret)
code=$(read_field code)
redirect_uri=$(read_field redirect_uri)
[ -n "$redirect_uri" ] || redirect_uri="http://localhost"

error_response() {
  send_json "{\"error\":\"$1\",\"message\":\"$2\"}"
  exit 0
}

[ -n "$client_id" ] || error_response "missing_client_id" "Provide your Google OAuth client ID."
[ -n "$client_secret" ] || error_response "missing_client_secret" "Provide your Google OAuth client secret."
[ -n "$code" ] || error_response "missing_code" "Paste the authorization code returned by Google."

curl_status=0
http_code=$(curl -sS \
  -o "$resp_file" \
  -w '%{http_code}' \
  --data-urlencode "client_id=$client_id" \
  --data-urlencode "client_secret=$client_secret" \
  --data-urlencode "code=$code" \
  --data-urlencode "redirect_uri=$redirect_uri" \
  --data-urlencode "grant_type=authorization_code" \
  https://oauth2.googleapis.com/token) || curl_status=$?

if [ $curl_status -ne 0 ]; then
  error_response "http_request_failed" "curl exited with status $curl_status"
fi

case "$http_code" in
  200|201|202)
    cat "$resp_file"
    ;;
  *)
    body=$(cat "$resp_file")
    esc=$(printf '%s' "$body" | sed -e 's/\\/\\\\/g' -e 's/"/\\"/g' -e ':a;N;$!ba;s/\n/\\n/g')
    send_json "{\"error\":\"token_exchange_failed\",\"status\":$http_code,\"body\":\"$esc\"}"
    ;;
 esac
