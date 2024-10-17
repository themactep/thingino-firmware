#!/bin/sh
. ./_json.sh

if ntpd -n -q -N; then
	payload='"Camera time synchronized with NTP server."'
else
	payload='"Synchronization failed!"'
fi

json_ok "$payload"
