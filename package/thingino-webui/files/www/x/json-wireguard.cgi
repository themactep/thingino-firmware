#!/bin/sh
. ./_json.sh

# parse parameters from query string
if [ -n "$QUERY_STRING" ]; then
	eval $(echo "$QUERY_STRING" | sed "s/&/;/g")
fi

if [ -z "$state" ]; then
	json_error "Missing mandatory parameter: state"
fi

if [ -z "$iface" ]; then
	iface="wg0"
fi

is_wg_up() {
	ip link show $iface | grep -q UP
}

wg_status() {
	is_wg_up && echo -n "up" || echo -n "down"
}

if [ "true" = "$wg_enabled" ] ; then
	is_wg_up || service force wireguard
else
	is_wg_up && service stop wireguard
fi

json_ok "WireGuard service is $(wg_status)"
