#!/bin/sh
if [ "$MDEV" = "ra0" ]; then
ip link set ra0 down 2>/dev/null
ip link set ra0 name wlan0
ip link set wlan0 up
fi

