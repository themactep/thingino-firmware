#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

. /usr/share/common

# Parse query string
if [ -n "$QUERY_STRING" ]; then
  eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

file=$(mktemp)
trap "rm -f $file" EXIT

case "$log" in
  dmesg)
    dmesg >$file
    ;;
  logread)
    logread >$file
    ;;
  netstat)
    netstat -a >$file
    ;;
  snmp)
    cat /proc/net/snmp >$file
    ;;
  *)
    echo "Status: 400 Bad Request"
    echo "Content-type: text/plain"
    echo ""
    echo "Unknown file type: $log"
    exit 1
    ;;
esac

if [ ! -f "$file" ] || [ ! -s "$file" ]; then
  echo "Status: 500 Internal Server Error"
  echo "Content-type: text/plain"
  echo ""
  echo "Failed to generate log file."
  exit 1
fi

file_size=$(stat -c%s "$file")
timestamp=$(date +%s)

cat <<EOF
HTTP/1.0 200 OK
Date: $(TZ=GMT0 date +'%a, %d %b %Y %H:%M:%S %Z')
Server: ${SERVER_SOFTWARE:-thingino}
Content-type: text/plain
Content-Disposition: attachment; filename=${log}-${timestamp}.txt
Content-Length: $file_size
Cache-Control: no-store
Pragma: no-cache

EOF

cat "$file"
