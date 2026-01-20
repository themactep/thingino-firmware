#!/bin/sh

. /usr/share/common

CONFIG_JSON="/etc/thingino.json"
NETWORK_DIR="/etc/network/interfaces.d"
REQ_FILE=""

dns_primary=""
dns_secondary=""

[ -d "$NETWORK_DIR" ] || mkdir -p "$NETWORK_DIR"

emit_json() {
  local status="$1"
  shift
  [ -n "$status" ] && printf 'Status: %s\n' "$status"
  cat <<EOF
Content-Type: application/json
Cache-Control: no-store
Pragma: no-cache

$1
EOF
  exit 0
}

json_escape() {
  printf '%s' "$1" | sed \
    -e 's/\\/\\\\/g' \
    -e 's/"/\\"/g' \
    -e 's/\r/\\r/g' \
    -e 's/\n/\\n/g'
}

json_error() {
  local status=${1:-"400 Bad Request"} text="$2" code=${3:-error}
  emit_json "$status" "$(printf '{"error":{"code":"%s","message":"%s"}}' "$(json_escape "$code")" "$(json_escape "$text")")"
}

cleanup() {
  [ -n "$REQ_FILE" ] && [ -f "$REQ_FILE" ] && rm -f "$REQ_FILE"
}

trap cleanup EXIT

read_body() {
  REQ_FILE=$(mktemp /tmp/json-config-network.XXXXXX)
  if [ -n "$CONTENT_LENGTH" ]; then
    dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null >"$REQ_FILE"
  else
    cat >"$REQ_FILE"
  fi
}

read_json_string() {
  local key="$1" value
  value=$(jct "$REQ_FILE" get "$key" 2>/dev/null)
  [ "$value" = "null" ] && value=""
  printf '%s' "$value"
}

read_json_bool() {
  local key="$1" default_value="$2" value
  value=$(jct "$REQ_FILE" get "$key" 2>/dev/null)
  case "$value" in
    true|false) printf '%s' "$value" ;;
    *) printf '%s' "${default_value:-false}" ;;
  esac
}

trim_value() {
  printf '%s' "$1" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//'
}

ensure_config_file() {
  [ -f "$CONFIG_JSON" ] && return
  local old_umask
  old_umask=$(umask)
  umask 077
  echo '{}' >"$CONFIG_JSON"
  umask "$old_umask"
}

read_fw_env() {
  command -v fw_printenv >/dev/null 2>&1 || return
  fw_printenv -n "$1" 2>/dev/null
}

iface_path() {
  printf '%s/%s' "$NETWORK_DIR" "$1"
}

disable_iface() {
  local iface="$1" path
  path=$(iface_path "$iface")
  [ -f "$path" ] || return
  sed -i -E "s/^[[:space:]]*auto[[:space:]]+$iface/#auto $iface/" "$path"
}

iface_has_auto() {
  local iface="$1" path
  path=$(iface_path "$iface")
  [ -f "$path" ] || return 1
  grep -qE "^[[:space:]]*(auto|allow-hotplug)[[:space:]]+$iface" "$path"
}

hostname_in_etc() {
  [ -f /etc/hostname ] || return
  cat /etc/hostname
}

iface_broadcast() {
  [ -d "/sys/class/net/$1" ] || return
  ifconfig "$1" 2>/dev/null | sed -En 's/.*Bcast:([0-9\.]+).*/\1/p'
}

iface_gateway() {
  ip route show | awk -v dev="$1" '$0 ~ dev && /via/ {print $3; exit}'
}

iface_ip_actual() {
  ip route show | sed -nE "/$1/s/.+src ([0-9\.]+).+/\1/p" | head -n1
}

iface_ip_in_etc() {
  local path
  path=$(iface_path "$1")
  [ -f "$path" ] || return
  sed -nE 's/^[[:space:]]*address[[:space:]]+([^[:space:]]+).*/\1/p' "$path"
}

iface_ipv6() {
  local path
  path=$(iface_path "$1")
  [ -f "$path" ] || return
  grep -q 'dhcp-v6-enabled true' "$path" && echo "true" || echo "false"
}

iface_mac() {
  [ -f "/sys/class/net/$1/address" ] || return
  cat "/sys/class/net/$1/address"
}

iface_netmask() {
  local from_cfg path
  path=$(iface_path "$1")
  if [ -f "$path" ]; then
    from_cfg=$(sed -nE 's/^[[:space:]]*netmask[[:space:]]+([^[:space:]]+).*/\1/p' "$path")
  fi
  if [ -n "$from_cfg" ]; then
    printf '%s' "$from_cfg"
    return
  fi
  [ -d "/sys/class/net/$1" ] || return
  ifconfig "$1" 2>/dev/null | sed -En 's/.*Mask:([0-9\.]+).*/\1/p'
}

iface_up() {
  local carrier="/sys/class/net/$1/carrier"
  if [ -f "$carrier" ]; then
    [ "$(cat "$carrier" 2>/dev/null)" -eq 1 ] && echo "true" && return
  fi
  local oper="/sys/class/net/$1/operstate"
  if [ -f "$oper" ]; then
    [ "$(cat "$oper" 2>/dev/null)" = "up" ] && echo "true" && return
  fi
  echo "false"
}

is_iface_dhcp() {
  local path mode
  path=$(iface_path "$1")
  [ -f "$path" ] || return 1
  mode=$(sed -nE 's/^[[:space:]]*iface[[:space:]]+[^[:space:]]+[[:space:]]+inet[[:space:]]+([^[:space:]]+).*/\1/p' "$path" | head -n1)
  [ "$mode" = "dhcp" ]
}

setup_dns() {
  local primary="$1" secondary="$2"
  [ -d "/etc/default" ] || mkdir -p /etc/default
  {
    echo "# set from web ui"
    for ip in $primary $secondary; do
      [ -n "$ip" ] && echo "nameserver $ip"
    done
  } > /etc/default/resolv.conf
}

setup_iface() {
  local interface=$1
  local mode=${2:-dhcp}
  local address=$3
  local netmask=$4
  local gateway=$5
  local broadcast=$6
  local ipv6=${7:-false}

  {
    echo "auto $interface"
    echo "iface $interface inet $mode"
    if [ "$mode" = "static" ]; then
      echo "\taddress $address"
      echo "\tnetmask $netmask"
      [ -n "$gateway" ] && echo "\tgateway $gateway"
      [ -n "$broadcast" ] && echo "\tbroadcast $broadcast"
    fi
    echo "\tdhcp-v6-enabled $ipv6"
  } > "$(iface_path "$interface")"

  touch /tmp/network-restart.txt
}

normalize_mac() {
  local value="$1"
  value=$(printf '%s' "$value" | tr -d '[:space:]')
  [ -n "$value" ] || return
  value=$(printf '%s' "$value" | tr '[:lower:]' '[:upper:]')
  value=${value//-/:}
  printf '%s' "$value"
}

valid_mac() {
  printf '%s' "$1" | grep -qE '^([0-9A-F]{2}:){5}[0-9A-F]{2}$'
}

safe_fw_setenv() {
  command -v fw_setenv >/dev/null 2>&1 || return
  fw_setenv "$@" >/dev/null 2>&1 || true
}

mac_json_key() {
  case "$1" in
    eth0) echo "eth.mac" ;;
    wlan0) echo "wlan.mac" ;;
    usb0) echo "usb.mac" ;;
  esac
}

mac_env_key() {
  case "$1" in
    eth0) echo "ethaddr" ;;
    wlan0) echo "wlan_mac" ;;
    usb0) echo "usbmac" ;;
  esac
}

read_known_mac() {
  local iface="$1" value
  value=$(iface_mac "$iface")
  [ -n "$value" ] || value=$(jct "$CONFIG_JSON" get "$(mac_json_key "$iface")" 2>/dev/null)
  [ -n "$value" ] || value=$(read_fw_env "$(mac_env_key "$iface")")
  printf '%s' "$value"
}

read_dns_servers() {
  dns_primary=""
  dns_secondary=""
  for file in /etc/resolv.conf /etc/default/resolv.conf; do
    [ -f "$file" ] || continue
    while IFS= read -r ns; do
      [ -n "$ns" ] || continue
      if [ -z "$dns_primary" ]; then
        dns_primary="$ns"
        continue
      fi
      if [ -z "$dns_secondary" ] && [ "$ns" != "$dns_primary" ]; then
        dns_secondary="$ns"
        break
      fi
    done <<EOF
$(sed -nE 's/^[[:space:]]*nameserver[[:space:]]+([^[:space:]]+).*/\1/p' "$file")
EOF
    [ -n "$dns_primary" ] && [ -n "$dns_secondary" ] && break
  done
}

interface_state_json() {
  local iface="$1" enabled="false" link="false" dhcp="true" ipv6="false"
  local address netmask gateway broadcast mac

  iface_has_auto "$iface" && enabled="true"
  link=$(iface_up "$iface")
  if is_iface_dhcp "$iface"; then
    dhcp="true"
  else
    dhcp="false"
  fi
  ipv6=$(iface_ipv6 "$iface")
  [ -n "$ipv6" ] || ipv6="false"

  address=$(iface_ip_actual "$iface")
  [ -n "$address" ] || address=$(iface_ip_in_etc "$iface")
  netmask=$(iface_netmask "$iface")
  gateway=$(iface_gateway "$iface")
  broadcast=$(iface_broadcast "$iface")
  mac=$(normalize_mac "$(read_known_mac "$iface")")

  printf '"%s":{"enabled":%s,"link_up":%s,"dhcp":%s,"ipv6":%s,"address":"%s","netmask":"%s","gateway":"%s","broadcast":"%s","mac":"%s"}' \
    "$iface" "$enabled" "$link" "$dhcp" "$ipv6" \
    "$(json_escape "$address")" \
    "$(json_escape "$netmask")" \
    "$(json_escape "$gateway")" \
    "$(json_escape "$broadcast")" \
    "$(json_escape "$mac")"
}

send_state() {
  ensure_config_file

  local hostname_value
  hostname_value=$(hostname -s)

  read_dns_servers

  local wifi_ssid wifi_bssid wifi_pass wifi_ap_enabled wifi_ap_ssid wifi_ap_pass

        wifi_ssid=$(jct "$CONFIG_JSON" get wlan.ssid       2>/dev/null || read_fw_env wlan_ssid)
       wifi_bssid=$(jct "$CONFIG_JSON" get wlan.bssid      2>/dev/null || read_fw_env wlan_bssid)
        wifi_pass=$(jct "$CONFIG_JSON" get wlan.pass       2>/dev/null || read_fw_env wlan_pass)

  wifi_ap_enabled=$(jct "$CONFIG_JSON" get wlan_ap.enabled 2>/dev/null || read_fw_env wlanap_enabled)
     wifi_ap_ssid=$(jct "$CONFIG_JSON" get wlan_ap.ssid    2>/dev/null || read_fw_env wlanap_ssid)
     wifi_ap_pass=$(jct "$CONFIG_JSON" get wlan_ap.pass    2>/dev/null || read_fw_env wlanap_pass)

  [ "$wifi_ap_enabled" = "true" ] || [ "$wifi_ap_enabled" = "false" ] || wifi_ap_enabled="false"

  printf '{"hostname":"%s","dns":{"primary":"%s","secondary":"%s"},' \
    "$(json_escape "$hostname_value")" \
    "$(json_escape "$dns_primary")" \
    "$(json_escape "$dns_secondary")"

  printf '"wifi":{"ssid":"%s","bssid":"%s","password":"%s"},' \
    "$(json_escape "$wifi_ssid")" \
    "$(json_escape "$wifi_bssid")" \
    "$(json_escape "$wifi_pass")"

  printf '"wifi_ap":{"enabled":%s,"ssid":"%s","password":"%s"},' \
    "$wifi_ap_enabled" \
    "$(json_escape "$wifi_ap_ssid")" \
    "$(json_escape "$wifi_ap_pass")"

  printf '"interfaces":{'
  local first=1 iface output
  for iface in eth0 wlan0 usb0; do
    output=$(interface_state_json "$iface")
    [ $first -eq 0 ] && printf ','
    first=0
    printf '%s' "$output"
  done
  printf '}}'
}

ensure_hostname() {
  local host="$1" bad
  [ -n "$host" ] || json_error "400 Bad Request" "Hostname cannot be empty" "missing_hostname"
  printf '%s' "$host" | grep -q '[[:space:]]' && json_error "400 Bad Request" "Hostname cannot contain spaces" "invalid_hostname"
  bad=$(printf '%s' "$host" | sed 's/[0-9A-Za-z\.-]//g')
  [ -z "$bad" ] || json_error "400 Bad Request" "Hostname contains invalid characters: $bad" "invalid_hostname"
}

ensure_dns() {
  dns_primary=$(trim_value "$1")
  dns_secondary=$(trim_value "$2")
  [ -n "$dns_primary" ] || dns_primary="$dns_secondary"
  [ -n "$dns_primary" ] || json_error "400 Bad Request" "At least one DNS server is required" "missing_dns"
}

assign_iface_state() {
  local iface="$1" enabled="$2" dhcp="$3" ipv6="$4" address="$5" netmask="$6" gateway="$7" broadcast="$8" mac="$9" mode="${10}"
  case "$iface" in
    eth0)
      eth0_enabled="$enabled"
      eth0_dhcp="$dhcp"
      eth0_ipv6="$ipv6"
      eth0_address="$address"
      eth0_netmask="$netmask"
      eth0_gateway="$gateway"
      eth0_broadcast="$broadcast"
      eth0_mac="$mac"
      eth0_mode="$mode"
      ;;
    wlan0)
      wlan0_enabled="$enabled"
      wlan0_dhcp="$dhcp"
      wlan0_ipv6="$ipv6"
      wlan0_address="$address"
      wlan0_netmask="$netmask"
      wlan0_gateway="$gateway"
      wlan0_broadcast="$broadcast"
      wlan0_mac="$mac"
      wlan0_mode="$mode"
      ;;
    usb0)
      usb0_enabled="$enabled"
      usb0_dhcp="$dhcp"
      usb0_ipv6="$ipv6"
      usb0_address="$address"
      usb0_netmask="$netmask"
      usb0_gateway="$gateway"
      usb0_broadcast="$broadcast"
      usb0_mac="$mac"
      usb0_mode="$mode"
      ;;
  esac
}

process_interface_input() {
  local iface="$1" prefix="interfaces.$1" enabled dhcp ipv6 address netmask gateway broadcast mac mode=""
  enabled=$(read_json_bool "$prefix.enabled" "true")
  dhcp=$(read_json_bool "$prefix.dhcp" "true")
  ipv6=$(read_json_bool "$prefix.ipv6" "false")
  address=$(trim_value "$(read_json_string "$prefix.address")")
  netmask=$(trim_value "$(read_json_string "$prefix.netmask")")
  gateway=$(trim_value "$(read_json_string "$prefix.gateway")")
  broadcast=$(trim_value "$(read_json_string "$prefix.broadcast")")
  mac=$(trim_value "$(read_json_string "$prefix.mac")")
  [ -n "$mac" ] && mac=$(normalize_mac "$mac")

  if [ "$enabled" = "true" ]; then
    if [ "$dhcp" = "false" ]; then
      mode="static"
      [ -n "$mac" ]     || json_error "400 Bad Request" "$iface MAC address cannot be empty in static mode" "missing_mac"
      valid_mac "$mac"  || json_error "400 Bad Request" "$iface MAC address format is invalid" "invalid_mac"
      [ -n "$address" ] || json_error "400 Bad Request" "$iface IP address cannot be empty" "missing_address"
      [ -n "$netmask" ] || json_error "400 Bad Request" "$iface netmask cannot be empty" "missing_netmask"
    else
      mode="dhcp"
    fi
  fi

  assign_iface_state "$iface" "$enabled" "$dhcp" "$ipv6" "$address" "$netmask" "$gateway" "$broadcast" "$mac" "$mode"
}

setup_wireless_network() {
  local ssid="$1" bssid="$2" pass="$3" temp_file psk pass_plain=""
  if printf '%s' "$pass" | grep -qE '^[0-9A-Fa-f]{64}$'; then
    pass_plain=""
  else
    pass_plain="$pass"
  fi
  psk=$(convert_psk "$ssid" "$pass")
  temp_file=$(mktemp /tmp/wlan-config.XXXXXX)
  echo '{}' > "$temp_file"
  jct "$temp_file" set wlan.ssid "$ssid"
  jct "$temp_file" set wlan.bssid "$bssid"
  jct "$temp_file" set wlan.pass "$psk"
  [ -n "$pass_plain" ] && jct "$temp_file" set wlan.pass_plain "$pass_plain"
  jct "$CONFIG_JSON" import "$temp_file"
  rm -f "$temp_file"

  temp_file=$(mktemp /tmp/wlan-env.XXXXXX)
  {
    [ -n "$ssid" ] && echo "wlan_ssid $ssid"
    [ -n "$bssid" ] && echo "wlan_bssid $bssid"
    [ -n "$psk" ] && echo "wlan_pass $psk"
  } > "$temp_file"
  safe_fw_setenv -s "$temp_file"
  rm -f "$temp_file"
}

update_wifi_ap_settings() {
  local ssid="$1" pass="$2" enabled="$3" temp_file psk pass_plain=""
  if [ -n "$ssid$pass" ]; then
    if [ -n "$pass" ] && printf '%s' "$pass" | grep -qE '^[0-9A-Fa-f]{64}$'; then
      psk=$(printf '%s' "$pass" | tr '[:lower:]' '[:upper:]')
    else
      psk=$(convert_psk "$ssid" "$pass")
      pass_plain="$pass"
    fi
  fi

  temp_file=$(mktemp /tmp/wlan-ap.XXXXXX)
  echo '{}' > "$temp_file"
  jct "$temp_file" set wlan_ap.enabled "$enabled"
  jct "$temp_file" set wlan_ap.ssid "$ssid"
  if [ -n "$psk" ]; then
    jct "$temp_file" set wlan_ap.pass "$psk"
    [ -n "$pass_plain" ] && jct "$temp_file" set wlan_ap.pass_plain "$pass_plain"
  fi
  jct "$CONFIG_JSON" import "$temp_file"
  rm -f "$temp_file"

  safe_fw_setenv wlanap_enabled "$enabled"
  [ -n "$ssid" ] && safe_fw_setenv wlanap_ssid "$ssid"
  [ -n "$psk" ] && safe_fw_setenv wlanap_pass "$psk"
}

update_hostname_files() {
  local host="$1"
  [ "$host" = "$(hostname_in_etc)" ] || echo "$host" >/etc/hostname
  if grep -q '^127.0.1.1' /etc/hosts; then
    sed -i "s/^127.0.1.1.*/127.0.1.1\t$host/" /etc/hosts
  else
    echo "127.0.1.1\t$host" >> /etc/hosts
  fi
  hostname "$host" >/dev/null 2>&1 || true
}

apply_interface_settings() {
  local iface="$1" enabled="$2" mode="$3" address="$4" netmask="$5" gateway="$6" broadcast="$7" ipv6="$8" mac="$9"
  [ -n "$mode" ] || mode="dhcp"
  [ -n "$ipv6" ] || ipv6="false"
  setup_iface "$iface" "$mode" "$address" "$netmask" "$gateway" "$broadcast" "$ipv6"
  local json_key env_key
  json_key=$(mac_json_key "$iface")
  env_key=$(mac_env_key "$iface")
  [ -n "$json_key" ] && jct "$CONFIG_JSON" set "$json_key" "$mac"
  if [ -n "$env_key" ] && [ -n "$mac" ]; then
    safe_fw_setenv "$env_key" "$mac"
  fi
  [ "$enabled" = "true" ] || disable_iface "$iface"
}

handle_post() {
  ensure_config_file
  read_body

  hostname_value=$(trim_value "$(read_json_string hostname)")
  ensure_hostname "$hostname_value"

  dns_primary_input=$(read_json_string dns.primary)
  dns_secondary_input=$(read_json_string dns.secondary)
  ensure_dns "$dns_primary_input" "$dns_secondary_input"

  process_interface_input eth0
  process_interface_input wlan0
  process_interface_input usb0

  wifi_ssid=$(trim_value "$(read_json_string wifi.ssid)")
  wifi_pass=$(trim_value "$(read_json_string wifi.password)")
  wifi_bssid=$(trim_value "$(read_json_string wifi.bssid)")
  if [ -n "$wifi_bssid" ]; then
    wifi_bssid=$(normalize_mac "$wifi_bssid")
    valid_mac "$wifi_bssid" || json_error "400 Bad Request" "wlan0 BSSID format is invalid" "invalid_bssid"
  fi

  wifi_ap_enabled=$(read_json_bool wifi_ap.enabled "false")
  wifi_ap_ssid=$(trim_value "$(read_json_string wifi_ap.ssid)")
  wifi_ap_pass=$(trim_value "$(read_json_string wifi_ap.password)")
  if [ "$wifi_ap_enabled" = "true" ]; then
    [ -n "$wifi_ap_ssid" ] || json_error "400 Bad Request" "Wi-Fi AP SSID cannot be empty" "missing_wlanap_ssid"
    [ -n "$wifi_ap_pass" ] || json_error "400 Bad Request" "Wi-Fi AP password cannot be empty" "missing_wlanap_pass"
    [ ${#wifi_ap_pass} -ge 8 ] || json_error "400 Bad Request" "Wi-Fi AP password must be at least 8 characters" "invalid_wlanap_pass"
  fi

  if [ "$wlan0_enabled" = "true" ] && [ -n "$wifi_ssid$wifi_pass" ]; then
    [ -n "$wifi_ssid" ] || json_error "400 Bad Request" "Wi-Fi SSID cannot be empty" "missing_wifi_ssid"
    [ -n "$wifi_pass" ] || json_error "400 Bad Request" "Wi-Fi password cannot be empty" "missing_wifi_pass"
    [ ${#wifi_pass} -ge 8 ] || json_error "400 Bad Request" "Wi-Fi password must be at least 8 characters" "invalid_wifi_pass"
  fi

  apply_interface_settings eth0 "$eth0_enabled" "$eth0_mode" "$eth0_address" "$eth0_netmask" "$eth0_gateway" "$eth0_broadcast" "$eth0_ipv6" "$eth0_mac"
  apply_interface_settings wlan0 "$wlan0_enabled" "$wlan0_mode" "$wlan0_address" "$wlan0_netmask" "$wlan0_gateway" "$wlan0_broadcast" "$wlan0_ipv6" "$wlan0_mac"
  apply_interface_settings usb0 "$usb0_enabled" "$usb0_mode" "$usb0_address" "$usb0_netmask" "$usb0_gateway" "$usb0_broadcast" "$usb0_ipv6" "$usb0_mac"

  update_hostname_files "$hostname_value"
  setup_dns "$dns_primary" "$dns_secondary"

  if [ "$wlan0_enabled" = "true" ] && [ -n "$wifi_ssid$wifi_pass" ]; then
    setup_wireless_network "$wifi_ssid" "$wifi_bssid" "$wifi_pass"
  fi

  update_wifi_ap_settings "$wifi_ap_ssid" "$wifi_ap_pass" "$wifi_ap_enabled"

  refresh_env_dump
  command -v update_caminfo >/dev/null 2>&1 && update_caminfo

  emit_json "" '{"status":"ok"}'
}

case "${REQUEST_METHOD:-GET}" in
  POST)
    handle_post
    ;;
  GET)
    response=$(send_state)
    emit_json "" "$response"
    ;;
  *)
    json_error "405 Method Not Allowed" "Unsupported method" "unsupported_method"
    ;;
esac
