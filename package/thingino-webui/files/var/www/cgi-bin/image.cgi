#!/bin/sh
preview=/tmp/snapshot.jpg
date=$(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
echo "HTTP/1.1 200 OK
Content-type: image/jpeg
Content-Disposition: attachment; filename=preview-$(date +%s).jpg
Cache-Control: no-store
Pragma: no-cache
Date: $date
Expires: $date
Connection: close
"
cat $preview
