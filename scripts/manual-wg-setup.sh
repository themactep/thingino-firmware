#!/bin/sh
# manual-wg-setup.sh — Fully interactive WireGuard setup for Thingino hardware

set -e

if [ "$1" = "--down" ]; then
  echo "[+] Tearing down wg0..."
  ip link delete wg0
  exit 0
fi

# Prompt for keys + endpoint
read -p "Private key: " PRIV
read -p "Peer public key: " PEER_PUB
read -p "Preshared key: " PSK
read -p "Server endpoint (host:port): " ENDPOINT

# Prompt for network config
read -p "Interface IP address (e.g. 10.13.13.2/32): " WG_ADDR
read -p "Allowed IPs (e.g. 0.0.0.0/0): " ALLOWED_IPS
read -p "MTU (default 1420): " MTU
MTU=${MTU:-1420}
read -p "Keepalive (default 25): " KEEPALIVE
KEEPALIVE=${KEEPALIVE:-25}
read -p "Route to add (e.g. 10.13.13.0/24): " ROUTE

# Setup
echo "[+] Setting up wg0..."

ip link add dev wg0 type wireguard

wg set wg0 private-key <(echo "$PRIV")
wg set wg0 peer "$PEER_PUB" \
  preshared-key <(echo "$PSK") \
  endpoint "$ENDPOINT" \
  allowed-ips "$ALLOWED_IPS" \
  persistent-keepalive "$KEEPALIVE"

ip link set mtu "$MTU" dev wg0
ip address add "$WG_ADDR" dev wg0
ip link set up dev wg0
ip route add "$ROUTE" dev wg0

echo "[+] WireGuard is up. Use './manual-wg-setup.sh --down' to remove it."
