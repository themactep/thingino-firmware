#!/bin/sh
. ./_json.sh

if ntpd -n -q -N; then
	payload='{"result":"success","message":"Camera time synchronized with NTP server."}'
else
	payload='{"result":"danger","message":"Synchronization failed!"}'
fi

json_ok "$payload"
