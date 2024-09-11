#!/bin/sh
preview=/tmp/snapshot.jpg
date=$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
echo -ne "HTTP/1.1 200 OK\r\n\
Content-type: image/jpeg\r\n\
Content-Disposition: attachment; filename=preview-$(date +%s).jpg\r\n\
Cache-Control: no-store\r\n\
Pragma: no-cache\r\n\
Date: $date\r\n\
Expires: $date\r\n\
Connection: close\r\n\r\n"
cat $preview
