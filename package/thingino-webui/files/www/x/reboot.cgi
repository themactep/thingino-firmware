#!/bin/sh

# Check authentication
. /var/www/x/auth.sh
require_auth

umount -a -t nfs -l
sleep 3
printf "Status: 302 Found\r\nLocation: /wait.html\r\nContent-Type: text/html; charset=UTF-8\r\nCache-Control: no-store\r\nPragma: no-cache\r\n\r\n"
echo "I'll be back"
sleep 1
reboot -f
