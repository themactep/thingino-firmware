#!/bin/sh
. ./_json.sh

# parse parameters from query string
[ -n "$QUERY_STRING" ] && eval $(echo "$QUERY_STRING" | sed "s/&/;/g")

[ -z "$state" ] && json_error "Missing mandatory parameter: state"
[ -z "$iface" ] && iface="wg0"

WG_CTL="/etc/init.d/S42wireguard"

is_wg_up() {
	ip link show $iface | grep -q UP
}

wg_status() {
	is_wg_up && echo -n "up" || echo -n "down"
}

if [ "true" = "$wg_enabled" ] ; then
	is_wg_up || $WG_CTL force
else
	is_wg_up && $WG_CTL stop
fi

json_ok "WireGuarde service is $(wg_status)."
