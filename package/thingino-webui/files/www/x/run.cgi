#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

printf "Content-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\nPragma: no-cache\r\n\r\n"

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

# exit if no command sent
[ -z "$cmd" ] && exit 1

# restore command from Base64 data
c=$(echo $cmd | base64 -d)

# exit if command is empty
[ -z "$c" ] && echo "No command!" && exit

prompt() {
  echo -e "<b># $1</b>"
}

export PATH=/bin:/sbin
cd /tmp || return
prompt "$c\n"
eval $c 2>&1

case "$?" in
  126)
    echo "-sh: $c: Permission denied"
    prompt
    ;;
  127)
    echo "-sh: $c: not found"
    prompt
    ;;
  0)
    prompt
    ;;
  *)
    echo -e "\nEXIT CODE: $?"
esac

exit 0
