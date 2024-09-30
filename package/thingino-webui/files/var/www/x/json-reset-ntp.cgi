#!/bin/sh
. ./_json.sh

if cp /rom/etc/ntp.conf /tmp/ntp.conf; then
	payload='{"result":"success","message":"Configuration reset to firmware defaults."}'
else
	payload='{"result":"danger","message":"Configuration reset to firmware defaults failed!"}'
fi

json_ok "$payload"
