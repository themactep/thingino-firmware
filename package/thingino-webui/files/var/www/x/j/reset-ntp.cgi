#!/bin/sh

if cp /rom/etc/ntp.conf /etc/ntp.conf; then
	payload='{"result":"success","message":"Configuration reset to firmware defaults."}'
else
	payload='{"result":"danger","message":"Configuration reset to firmware defaults failed!"}'
fi

echo "HTTP/1.1 200 OK
Content-type: application/json
Pragma: no-cache
Expires: $(TZ=GMT0 date +'%a, %d %b %Y %T %Z')
Etag: \"$(cat /proc/sys/kernel/random/uuid)\"

$payload
"
