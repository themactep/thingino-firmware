#!/bin/sh
. ./_json.sh

if cp /rom/etc/ntp.conf /tmp/ntp.conf; then
	json_ok '{"result":"success","message":"Configuration reset to firmware defaults."}'
else
	json_error '{"result":"danger","message":"Configuration reset to firmware defaults failed!"}'
fi

