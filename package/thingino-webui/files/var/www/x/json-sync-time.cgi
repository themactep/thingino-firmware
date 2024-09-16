#!/bin/sh

if ntpd -n -q -N; then
	payload='{"result":"success","message":"Camera time synchronized with NTP server."}'
else
	payload='{"result":"danger","message":"Synchronization failed!"}'
fi

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

$payload
"
