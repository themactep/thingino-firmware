#!/bin/sh
. ./_json.sh

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$state" ] && json_error "Missing mandatory parameter: state"
[ -z "$iface" ] && iface="wg0"

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
