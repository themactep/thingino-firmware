#!/bin/sh
# shellcheck disable=SC1091

# Check authentication
. /var/www/x/auth.sh
require_auth

# uhttpd SIGKILLs this CGI when the browser follows the redirect, so the
# reboot has to run in a detached session with stdio dropped.
setsid sh -c 'umount -a -t nfs -l; sleep 3; sync; reboot -f' \
	</dev/null >/dev/null 2>&1 &

printf "Status: 302 Found\r\nLocation: /wait.html\r\nContent-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\nPragma: no-cache\r\n\r\n"
echo "I'll be back"
