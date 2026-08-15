#!/bin/bash
#
# thingino-snmp-monitor.sh - Monitor multiple Thingino cameras via SNMP
#
# See: docs/thingino/services/snmpd.md (camera-side SNMP agent)
#       docs/thingino/tools/snmp/README.md (this tool)
#
# Usage:
#   thingino-snmp-monitor.sh status              # One-shot status table
#   thingino-snmp-monitor.sh watch [interval]     # Watch mode (default 10s)
#   thingino-snmp-monitor.sh discover [subnet]    # Auto-discover cameras
#   thingino-snmp-monitor.sh html [file]          # Generate static HTML dashboard
#   thingino-snmp-monitor.sh add <name> <ip> <community>  # Add camera to config
#   thingino-snmp-monitor.sh remove <name>        # Remove camera from config
#   thingino-snmp-monitor.sh list                 # List configured cameras
#
# Requires: snmpget, snmpwalk (apt install snmp)
# Optional: arp-scan or nmap (for discovery mode)
#
# Config: ~/.config/thingino/monitor.conf
#   Format: NAME|IP|COMMUNITY  (one per line, # for comments)
#
#   Example:
#     # Thingino camera monitor config
#     front-door|192.168.88.127|mysecret
#     backyard|192.168.88.128|mysecret
#     garage|192.168.88.129|anothersecret

set -o pipefail

# -- defaults -----------------------------------------------------------
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/thingino"
CONFIG_FILE="$CONFIG_DIR/monitor.conf"
DEFAULT_INTERVAL=10
SNMP_TIMEOUT=2
SNMP_TIMEOUT_DISCOVER=1
MAX_PARALLEL_PROBES=30
CACHE_DIR="${XDG_CACHE_HOME:-$HOME/.cache}/thingino/snmp-monitor"

# -- OID reference (from docs/snmpd.md) ---------------------------------
OID_SYS_DESCR=".1.3.6.1.2.1.1.1.0"
OID_SYS_UPTIME=".1.3.6.1.2.1.1.3.0"
OID_SYS_NAME=".1.3.6.1.2.1.1.5.0"
OID_SYS_LOCATION=".1.3.6.1.2.1.1.6.0"
OID_SYS_CONTACT=".1.3.6.1.2.1.1.4.0"

OID_MEM_TOTAL=".1.3.6.1.4.1.2021.4.5.0"      # memTotalReal (KB)
OID_MEM_AVAIL=".1.3.6.1.4.1.2021.4.6.0"      # memAvailReal (KB)
OID_MEM_BUFFER=".1.3.6.1.4.1.2021.4.14.0"    # memBuffer (KB)
OID_MEM_CACHED=".1.3.6.1.4.1.2021.4.15.0"    # memCached (KB)

OID_LA_1=".1.3.6.1.4.1.2021.10.1.3.1"        # load 1 min
OID_LA_5=".1.3.6.1.4.1.2021.10.1.3.2"        # load 5 min
OID_LA_15=".1.3.6.1.4.1.2021.10.1.3.3"       # load 15 min

OID_CPU_USER=".1.3.6.1.4.1.2021.11.50.0"     # ssCpuUser (cumulative ticks)
OID_CPU_SYSTEM=".1.3.6.1.4.1.2021.11.52.0"   # ssCpuSystem
OID_CPU_IDLE=".1.3.6.1.4.1.2021.11.53.0"     # ssCpuIdle

OID_IF_NUMBER=".1.3.6.1.2.1.2.1.0"
OID_IF_DESCR=".1.3.6.1.2.1.2.2.1.2"          # ifDescr (table)
OID_IF_IN_OCTETS=".1.3.6.1.2.1.31.1.1.1.6"   # ifHCInOctets (table)
OID_IF_OUT_OCTETS=".1.3.6.1.2.1.31.1.1.1.10" # ifHCOutOctets (table)

OID_DSK_PATH=".1.3.6.1.4.1.2021.9.1.2"       # dskPath (table)
OID_DSK_TOTAL=".1.3.6.1.4.1.2021.9.1.6"      # dskTotal (table)
OID_DSK_USED=".1.3.6.1.4.1.2021.9.1.8"       # dskUsed (table)
OID_DSK_PERCENT=".1.3.6.1.4.1.2021.9.1.9"    # dskPercent (table)

OID_SNMP_IN=".1.3.6.1.2.1.11.1.0"            # snmpInPkts
OID_SNMP_OUT=".1.3.6.1.2.1.11.2.0"           # snmpOutPkts
OID_HR_PROCESSES=".1.3.6.1.2.1.25.1.6.0"     # hrSystemProcesses
OID_HR_MEMORY_SIZE=".1.3.6.1.2.1.25.2.2.0"   # hrMemorySize (KB)

# -- terminal helpers ----------------------------------------------------
bold()   { printf '\033[1m%s\033[0m' "$*"; }
red()    { printf '\033[1;31m%s\033[0m' "$*"; }
green()  { printf '\033[1;32m%s\033[0m' "$*"; }
yellow() { printf '\033[1;33m%s\033[0m' "$*"; }
cyan()   { printf '\033[1;36m%s\033[0m' "$*"; }
dim()    { printf '\033[2m%s\033[0m' "$*"; }
clear_screen() { printf '\033[2J\033[H'; }

die() {
    echo "ERROR: $*" >&2
    exit 1
}

# -- SNMP helpers --------------------------------------------------------
snmp_get() {
    # Usage: snmp_get <ip> <community> <oid>
    # Returns: value or empty string on failure
    snmpget -v2c -c "$2" -Oqv -On -t "$SNMP_TIMEOUT" -r 1 "$1" "$3" 2>/dev/null || true
}

snmp_get_stripped() {
    # Same as snmp_get but strips surrounding quotes
    local val
    val=$(snmp_get "$1" "$2" "$3")
    val="${val#\"}"
    val="${val%\"}"
    echo "$val"
}

snmp_walk_count() {
    # Count rows in a table column
    snmpwalk -v2c -c "$2" -Oqn -On -t "$SNMP_TIMEOUT" -r 1 "$1" "$3" 2>/dev/null | wc -l
}

snmp_walk_column() {
    # Walk a table column, return values one per line
    snmpwalk -v2c -c "$2" -Oqv -On -t "$SNMP_TIMEOUT" -r 1 "$1" "$3" 2>/dev/null || true
}

# -- config management ---------------------------------------------------
load_config() {
    if [ ! -f "$CONFIG_FILE" ]; then
        return 1
    fi
    # Strip comments and blank lines
    grep -v '^\s*#' "$CONFIG_FILE" | grep -v '^\s*$' || true
}

get_camera_config() {
    # Usage: get_camera_config <name>
    # Returns: NAME|IP|COMMUNITY line
    load_config | grep "^$1|" || true
}

list_camera_names() {
    load_config | cut -d'|' -f1
}

ensure_config_dir() {
    mkdir -p "$CONFIG_DIR"
    mkdir -p "$CACHE_DIR"
}

# -- subcommands ---------------------------------------------------------

cmd_list() {
    if [ ! -f "$CONFIG_FILE" ]; then
        echo "No config file found at $CONFIG_FILE"
        echo "Use 'add' to add cameras or 'discover' to find them."
        exit 0
    fi
    local count
    count=$(load_config | wc -l)
    echo "Configured cameras ($count):"
    echo
    while IFS='|' read -r name ip community; do
        printf '  %-20s %-18s %s\n' "$name" "$ip" "$community"
    done < <(load_config)
}

cmd_add() {
    local name="$1" ip="$2" community="$3"
    if [ -z "$name" ] || [ -z "$ip" ] || [ -z "$community" ]; then
        die "Usage: $0 add <name> <ip> <community>"
    fi
    ensure_config_dir

    # Check for duplicate name
    if get_camera_config "$name" | grep -q .; then
        die "Camera '$name' already exists. Use 'remove' first to change it."
    fi

    # Validate IP format loosely
    if ! echo "$ip" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$'; then
        die "Invalid IP address: $ip"
    fi

    # Test SNMP connectivity before adding
    local sysname
    sysname=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_NAME" 2>/dev/null || true)
    if [ -z "$sysname" ]; then
        echo "$(yellow 'WARNING:') Could not reach SNMP agent at $ip with community '$community'"
        echo "Adding anyway, but you may need to check the configuration."
        echo
    else
        echo "Camera responds: $sysname"
    fi

    echo "$name|$ip|$community" >> "$CONFIG_FILE"
    echo "Added camera '$name' at $ip"
}

cmd_remove() {
    local name="$1"
    if [ -z "$name" ]; then
        die "Usage: $0 remove <name>"
    fi
    if [ ! -f "$CONFIG_FILE" ]; then
        die "No config file found."
    fi
    if ! get_camera_config "$name" | grep -q .; then
        die "Camera '$name' not found in config."
    fi

    # Remove the line
    grep -v "^$name|" "$CONFIG_FILE" > "${CONFIG_FILE}.tmp"
    mv "${CONFIG_FILE}.tmp" "$CONFIG_FILE"
    echo "Removed camera '$name'"
}

snmp_probe_quick() {
    # Fast single-community probe, returns "IP|community|sysName|sysDescr" if found
    local ip="$1" comm="$2"
    local sysname
    sysname=$(snmpget -v2c -c "$comm" -Oqv -On -t "$SNMP_TIMEOUT_DISCOVER" -r 0 "$ip" "$OID_SYS_NAME" 2>/dev/null || true)
    if [ -n "$sysname" ]; then
        sysname="${sysname#\"}"; sysname="${sysname%\"}"
        local descr
        descr=$(snmpget -v2c -c "$comm" -Oqv -On -t "$SNMP_TIMEOUT_DISCOVER" -r 0 "$ip" "$OID_SYS_DESCR" 2>/dev/null || true)
        descr="${descr#\"}"; descr="${descr%\"}"
        echo "$ip|$comm|$sysname|$descr"
    fi
}

# ── mDNS discovery helpers ─────────────────────────────────────────────
discover_mdns() {
    # Discover SNMP agents via mDNS (_snmp._udp).
    # Writes result files to $1 with prefix $2 (one per camera).
    local tmpdir="$1" prefix="$2"
    if ! command -v avahi-browse >/dev/null 2>&1; then
        return 1
    fi

    local mdns_file count=0 seen_ips=""
    mdns_file=$(mktemp)
    avahi-browse -t _snmp._udp -r -p -f 2>/dev/null > "$mdns_file" || true

    while IFS=';' read -r event iface proto name stype domain host addr port rest; do
        [ "$event" = "=" ] || continue
        [ -n "$addr" ] || continue

        # Skip duplicates (dual-stack hosts appear twice)
        case " $seen_ips " in
            *" $addr "*) continue ;;
        esac
        seen_ips="$seen_ips $addr"

        # Probe with common community strings
        local result
        for comm in "public" "private"; do
            result=$(snmp_probe_quick "$addr" "$comm" 2>/dev/null || true)
            if [ -n "$result" ]; then
                echo "$result" > "$tmpdir/${prefix}${count}"
                count=$((count + 1))
                break
            fi
        done
    done < "$mdns_file"
    rm -f "$mdns_file"
    [ "$count" -gt 0 ]
}

cmd_discover() {
    local subnet="${1:-}"
    local tmpdir found=0
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    # ── Try mDNS first ────────────────────────────────────────────────
    if command -v avahi-browse >/dev/null 2>&1; then
        echo "Scanning for SNMP agents via mDNS..."
        if discover_mdns "$tmpdir" "mdns-" 2>/dev/null; then
            local mdns_found
            mdns_found=$(ls "$tmpdir"/mdns-* 2>/dev/null | wc -l)
            echo "Found $mdns_found SNMP agent(s) via mDNS."
            echo
            print_and_add_results "$tmpdir" "mdns-"
            return
        fi
        echo "Nothing found via mDNS."
    fi

    # ── Fall back to network scan ─────────────────────────────────────
    echo
    local tool=""
    if command -v arp-scan >/dev/null 2>&1; then
        tool="arp-scan"
    elif command -v nmap >/dev/null 2>&1; then
        tool="nmap"
    fi

    if [ -z "$subnet" ]; then
        if [ -z "$tool" ]; then
            die "No subnet specified and no discovery tool found.\n" \
                "Install avahi-browse, arp-scan, or nmap; or specify a subnet: $0 discover 192.168.1.0/24"
        fi
        local default_if default_net
        default_if=$(ip route show default 2>/dev/null | awk '{print $5}' | head -1)
        if [ -z "$default_if" ]; then
            die "Could not detect default interface. Specify subnet manually."
        fi
        default_net=$(ip -4 addr show "$default_if" 2>/dev/null | grep -oP 'inet \K[\d.]+/[\d]+' | head -1)
        if [ -z "$default_net" ]; then
            die "Could not detect subnet on $default_if. Specify subnet manually."
        fi
        subnet="$default_net"
    fi

    echo "Scanning $subnet for live hosts (using $tool)..."
    echo

    local live_hosts=""
    case "$tool" in
        arp-scan)
            if [ "$(id -u)" -ne 0 ]; then
                echo "$(yellow 'WARNING:') arp-scan may need root. Trying anyway..."
            fi
            live_hosts=$(arp-scan --quiet "$subnet" 2>/dev/null | awk '{print $1}' | grep -E '^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$')
            ;;
        nmap)
            live_hosts=$(nmap -sn "$subnet" 2>/dev/null | grep 'Nmap scan report' | awk '{print $NF}' | tr -d '()')
            ;;
    esac

    if [ -z "$live_hosts" ]; then
        echo "No hosts found on $subnet."
        exit 0
    fi

    local host_count
    host_count=$(echo "$live_hosts" | wc -l)
    echo "Found $host_count live hosts. Probing for SNMP agents in parallel..."
    echo

    # Probe all hosts with both communities in parallel
    local running=0
    local communities=("public" "private")
    while IFS= read -r ip; do
        [ -z "$ip" ] && continue
        for comm in "${communities[@]}"; do
            while [ "$running" -ge "$MAX_PARALLEL_PROBES" ]; do
                wait -n 2>/dev/null || true
                running=$((running - 1))
            done
            (
                result=$(snmp_probe_quick "$ip" "$comm" 2>/dev/null || true)
                [ -n "$result" ] && echo "$result" > "$tmpdir/scan-${ip}__${comm}"
            ) &
            running=$((running + 1))
        done
    done <<< "$live_hosts"

    # Wait for remaining jobs, showing a spinner
    local spinner=('|' '/' '-' '\\') spin_idx=0
    while [ "$running" -gt 0 ]; do
        wait -n 2>/dev/null && running=$((running - 1)) || running=$((running - 1))
        printf '\r  %s Probing... %d remaining  ' "${spinner[$spin_idx]}" "$running"
        spin_idx=$(( (spin_idx + 1) % ${#spinner[@]} ))
    done
    printf '\r%50s\r' ''

    print_and_add_results "$tmpdir" "scan-"
}

# Shared result display + interactive add (used by both mDNS and scan paths)
print_and_add_results() {
    local tmpdir="$1" prefix="$2"
    local found=0 already=0

    # Helper: check if an IP is already in the config
    ip_in_config() {
        [ -f "$CONFIG_FILE" ] && grep -q "|$1|" "$CONFIG_FILE" 2>/dev/null
    }

    # Collect and print results
    for f in "$tmpdir"/"$prefix"*; do
        [ -f "$f" ] || continue
        local result
        result=$(cat "$f")
        if [ -n "$result" ]; then
            local ip comm sysname descr
            ip=$(echo "$result" | cut -d'|' -f1)
            comm=$(echo "$result" | cut -d'|' -f2)
            sysname=$(echo "$result" | cut -d'|' -f3)
            descr=$(echo "$result" | cut -d'|' -f4)
            if ip_in_config "$ip"; then
                rm -f "$f"
                already=$((already + 1))
            else
                printf '  %-18s %-30s %-20s %s\n' "$ip" "$sysname" "$(dim "community: $comm")" "$descr"
                found=$((found + 1))
            fi
        fi
    done

    if [ "$found" -eq 0 ]; then
        if [ "$already" -gt 0 ]; then
            echo "All $already discovered camera(s) are already in the config."
        else
            echo "No SNMP agents found."
        fi
        return
    fi

    echo
    if [ "$already" -gt 0 ]; then
        echo "Found $found new SNMP agent(s) ($already already monitored, not shown)."
    else
        echo "Found $found SNMP agent(s)."
    fi

    # Ask whether to add them
    echo
    read -r -p "Add these to the monitor config? [y/N] " reply
    if [ "$reply" != "y" ] && [ "$reply" != "Y" ]; then
        echo "Skipped. Use 'add <name> <ip> <community>' to add manually."
        return
    fi

    ensure_config_dir
    local added=0 skipped=0
    for f in "$tmpdir"/"$prefix"*; do
        [ -f "$f" ] || continue
        local result
        result=$(cat "$f")
        [ -n "$result" ] || continue

        local ip comm sysname
        ip=$(echo "$result" | cut -d'|' -f1)
        comm=$(echo "$result" | cut -d'|' -f2)
        sysname=$(echo "$result" | cut -d'|' -f3)

        # Derive a short name from sysName: strip 'ing-' prefix, truncate
        local suggested_name
        suggested_name=$(echo "$sysname" | sed 's/^ing-//' | tr -cd 'a-zA-Z0-9-_' | cut -c1-30)
        [ -z "$suggested_name" ] && suggested_name="camera-$ip"

        if get_camera_config "$suggested_name" | grep -q .; then
            suggested_name="${suggested_name}-2"
        fi

        echo
        printf '  %-18s %s\n' "IP:" "$ip"
        printf '  %-18s %s\n' "Hostname:" "$sysname"
        printf '  %-18s %s\n' "Community:" "$comm"
        read -r -p "  Name [$suggested_name]: " name
        name="${name:-$suggested_name}"

        name=$(echo "$name" | tr -d '|' | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        if [ -z "$name" ]; then
            echo "  $(yellow 'SKIPPED:') empty name"
            skipped=$((skipped + 1))
            continue
        fi

        if get_camera_config "$name" | grep -q .; then
            echo "  $(yellow 'SKIPPED:') '$name' already exists"
            skipped=$((skipped + 1))
            continue
        fi

        echo "$name|$ip|$comm" >> "$CONFIG_FILE"
        echo "  $(green 'ADDED') as '$name'"
        added=$((added + 1))
    done

    echo
    echo "Added $added, skipped $skipped. Run '$0 status' to see the dashboard."
}

cmd_status() {
    # One-shot status table for all configured cameras
    if ! load_config >/dev/null 2>&1; then
        echo "No cameras configured."
        echo
        echo "Quick start:"
        echo "  $0 add front-door 192.168.1.100 mycommunity"
        echo "  $0 discover                    # auto-detect cameras"
        exit 0
    fi

    # Collect data from all cameras in parallel
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    local pids=()
    while IFS='|' read -r name ip community; do
        (
            poll_camera "$name" "$ip" "$community" > "$tmpdir/$name"
        ) &
        pids+=($!)
    done < <(load_config)

    # Wait for all polls to complete
    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Print header
    echo
    bold "Thingino SNMP Monitor - $(date '+%Y-%m-%d %H:%M:%S')"
    echo

    # Table header (fixed-width columns) - pad before bolding to avoid
    # ANSI escape codes fooling printf width calculation
    local fmt_cols="%-20s %-16s %-14s %-5s %-6s %-7s %s\n"
    local h_cam h_ip h_upt h_mem h_ld1 h_dsk h_dsc
    h_cam=$(printf '%-20s' 'CAMERA')
    h_ip=$(printf '%-16s' 'IP')
    h_upt=$(printf '%-14s' 'UPTIME')
    h_mem=$(printf '%-5s' 'MEM')
    h_ld1=$(printf '%-6s' 'LOAD1')
    h_dsk=$(printf '%-7s' 'DISK')
    h_dsc='DESCRIPTION'
    printf "$fmt_cols" \
        "$(bold "$h_cam")" \
        "$(bold "$h_ip")" \
        "$(bold "$h_upt")" \
        "$(bold "$h_mem")" \
        "$(bold "$h_ld1")" \
        "$(bold "$h_dsk")" \
        "$(bold "$h_dsc")"
    printf '%s\n' "$(printf '%80s' | tr ' ' '-')"

    # Print each camera row (in config order)
    while IFS='|' read -r name ip community; do
        if [ -f "$tmpdir/$name" ]; then
            local row
            row=$(cat "$tmpdir/$name")
            local status="${row%%|*}"
            local rest="${row#*|}"

            # Pad name first, then colorize - escape codes fool printf's width calc
            local pad_name
            pad_name=$(printf '%-20s' "$name")

            if [ "$status" = "ONLINE" ]; then
                printf "$fmt_cols" \
                    "$(green "$pad_name")" \
                    "$ip" \
                    "$(echo "$rest" | cut -d'|' -f1)" \
                    "$(echo "$rest" | cut -d'|' -f2)" \
                    "$(echo "$rest" | cut -d'|' -f3)" \
                    "$(echo "$rest" | cut -d'|' -f4)" \
                    "$(echo "$rest" | cut -d'|' -f5)"
            else
                printf "$fmt_cols" \
                    "$(red "$pad_name")" \
                    "$ip" \
                    "$(red 'OFFLINE')" \
                    "-" "-" "-" \
                    "$(dim "$rest")"
            fi
        else
            local pad_name
            pad_name=$(printf '%-20s' "$name")
            printf "$fmt_cols" \
                "$(red "$pad_name")" \
                "$ip" \
                "$(red 'TIMEOUT')" \
                "-" "-" "-" "-"
        fi
    done < <(load_config)

    echo
}

# Poll a single camera, return a pipe-delimited row
# Format: STATUS|uptime|mem_used%|cpu_used%|load1|disk_used%|description
poll_camera() {
    local name="$1" ip="$2" community="$3"

    # Quick ping-style check: get sysDescr
    local descr uptime_ticks mem_total mem_avail cpu_idle load1 dsk_path

    descr=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_DESCR" 2>/dev/null || true)
    if [ -z "$descr" ]; then
        echo "OFFLINE|no response"
        return
    fi

    # Uptime
    uptime_ticks=$(snmp_get "$ip" "$community" "$OID_SYS_UPTIME" 2>/dev/null || echo "0")
    uptime_ticks="${uptime_ticks#Timestamp: }"
    uptime_ticks="${uptime_ticks#Timeticks: }"
    # mini-snmpd returns formatted time like "0:0:09:09.38" - use directly
    # Other agents return "(3327048) 9:14:30.48" - extract raw ticks
    local uptime_str
    if echo "$uptime_ticks" | grep -q ':'; then
        # Already formatted as d:h:m:s or h:m:s - strip any leading raw ticks
        uptime_str="${uptime_ticks##* }"   # "9:14:30.48" or "0:0:09:09.38"
    else
        uptime_ticks="${uptime_ticks%% *}"
        uptime_str=$(format_uptime "$uptime_ticks")
    fi

    # Memory
    mem_total=$(snmp_get "$ip" "$community" "$OID_MEM_TOTAL" 2>/dev/null || echo "0")
    mem_avail=$(snmp_get "$ip" "$community" "$OID_MEM_AVAIL" 2>/dev/null || echo "0")
    local mem_pct="?"
    mem_total=$(echo "$mem_total" | tr -cd '0-9')
    mem_avail=$(echo "$mem_avail" | tr -cd '0-9')
    if [ -n "$mem_total" ] && [ "$mem_total" -gt 0 ] 2>/dev/null; then
        mem_pct=$(( ( (mem_total - mem_avail) * 100 ) / mem_total ))
    fi

    # Load 1min
    load1=$(snmp_get_stripped "$ip" "$community" "$OID_LA_1" 2>/dev/null || echo "?")
    # Truncate to 4 chars
    load1="${load1:0:4}"

    # Disk - first entry (typically /)
    dsk_path=$(snmp_get_stripped "$ip" "$community" "${OID_DSK_PERCENT}.1" 2>/dev/null || echo "?")
    local dsk_str="${dsk_path}%"

    # Processes
    local processes
    processes=$(snmp_get "$ip" "$community" "$OID_HR_PROCESSES" 2>/dev/null | tr -cd '0-9' || echo "?")
    [ -z "$processes" ] && processes="?"

    # Network: find first non-loopback interface, get RX/TX octets
    local net_rx="?" net_tx="?" net_if="?"
    local if_count if_idx
    if_count=$(snmp_get "$ip" "$community" "$OID_IF_NUMBER" 2>/dev/null | tr -cd '0-9' || echo "0")
    for if_idx in $(seq 1 "$if_count"); do
        local if_name
        if_name=$(snmp_get_stripped "$ip" "$community" "${OID_IF_DESCR}.$if_idx" 2>/dev/null || true)
        if [ "$if_name" != "lo" ]; then
            net_rx=$(snmp_get "$ip" "$community" "${OID_IF_IN_OCTETS}.$if_idx" 2>/dev/null | tr -cd '0-9' || echo "?")
            net_tx=$(snmp_get "$ip" "$community" "${OID_IF_OUT_OCTETS}.$if_idx" 2>/dev/null | tr -cd '0-9' || echo "?")
            net_if="$if_name"
            break
        fi
    done
    [ -z "$net_rx" ] && net_rx="?"
    [ -z "$net_tx" ] && net_tx="?"

    # Truncate description
    descr="${descr:0:40}"

    echo "ONLINE|${uptime_str}|${mem_pct}%|${load1}|${dsk_str}|${descr}|${processes}|${net_rx}|${net_tx}|${net_if}"
}

format_bytes() {
    # Convert raw byte count to human-readable (pure bash)
    local bytes="$1" gb mb
    [ -z "$bytes" ] || [ "$bytes" = "?" ] && { echo "?"; return; }
    if [ "$bytes" -ge 1073741824 ] 2>/dev/null; then
        gb=$(( bytes / 107374182 ))
        printf '%d.%d GB' $(( gb / 10 )) $(( gb % 10 ))
    elif [ "$bytes" -ge 1048576 ] 2>/dev/null; then
        mb=$(( bytes / 104857 ))
        printf '%d.%d MB' $(( mb / 10 )) $(( mb % 10 ))
    elif [ "$bytes" -ge 1024 ] 2>/dev/null; then
        echo "$(( bytes / 1024 )) KB"
    else
        echo "${bytes} B"
    fi
}

format_uptime() {
    # Convert centiseconds to human-readable
    local ticks="$1"
    [ -z "$ticks" ] || [ "$ticks" = "0" ] && { echo "0s"; return; }
    # ticks are in hundredths of a second
    local total_sec=$(( ticks / 100 ))
    local d h m s
    d=$(( total_sec / 86400 ))
    h=$(( (total_sec % 86400) / 3600 ))
    m=$(( (total_sec % 3600) / 60 ))
    if [ "$d" -gt 0 ]; then
        printf '%dd%dh' "$d" "$h"
    elif [ "$h" -gt 0 ]; then
        printf '%dh%dm' "$h" "$m"
    elif [ "$m" -gt 0 ]; then
        printf '%dm' "$m"
    else
        printf '%ds' "$total_sec"
    fi
}

cmd_watch() {
    local interval="${1:-$DEFAULT_INTERVAL}"
    if ! [[ "$interval" =~ ^[0-9]+$ ]] || [ "$interval" -lt 2 ]; then
        die "Interval must be at least 2 seconds"
    fi

    if ! load_config >/dev/null 2>&1; then
        die "No cameras configured. Use 'add' or 'discover' first."
    fi

    while true; do
        clear_screen
        cmd_status
        echo "$(dim "Refreshing every ${interval}s - Ctrl+C to exit")"
        sleep "$interval"
    done
}

# -- HTML generation -----------------------------------------------------
cmd_html() {
    local output="${1:-}"
    if [ -n "$output" ]; then
        exec > "$output"
    fi

    if ! load_config >/dev/null 2>&1; then
        die "No cameras configured. Use 'add' or 'discover' first."
    fi

    # Collect all camera data
    local tmpdir
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    local pids=()
    while IFS='|' read -r name ip community; do
        (
            poll_camera "$name" "$ip" "$community" > "$tmpdir/$name"
        ) &
        pids+=($!)
    done < <(load_config)

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    # Generate HTML
    local now
    now=$(date '+%Y-%m-%d %H:%M:%S')

    cat <<HTML
<!DOCTYPE html>
<html lang="en">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width, initial-scale=1">
<title>Thingino SNMP Monitor</title>
<style>
  * { box-sizing: border-box; margin: 0; padding: 0; }
  body { font-family: -apple-system, BlinkMacSystemFont, 'Segoe UI', Roboto, sans-serif;
         background: #0f172a; color: #e2e8f0; padding: 2rem; }
  h1 { font-size: 1.5rem; margin-bottom: 0.25rem; }
  .timestamp { color: #64748b; font-size: 0.85rem; margin-bottom: 1.5rem; }
  .grid { display: grid; grid-template-columns: repeat(auto-fill, minmax(340px, 1fr)); gap: 1rem; }
  .card { background: #1e293b; border-radius: 8px; padding: 1.25rem; border: 1px solid #334155; }
  .card.offline { opacity: 0.5; border-color: #7f1d1d; }
  .card-header { display: flex; justify-content: space-between; align-items: baseline; margin-bottom: 1rem; }
  .card-name { font-size: 1.1rem; font-weight: 600; }
  .card-name.online { color: #4ade80; }
  .card-name.offline { color: #f87171; }
  .card-ip { font-size: 0.8rem; color: #94a3b8; font-family: monospace; }
  .card-desc { font-size: 0.8rem; color: #64748b; margin-bottom: 1rem; }
  .metrics { display: grid; grid-template-columns: 1fr 1fr; gap: 0.5rem; }
  .metric { background: #0f172a; border-radius: 6px; padding: 0.6rem; }
  .metric-label { font-size: 0.7rem; color: #64748b; text-transform: uppercase; letter-spacing: 0.05em; }
  .metric-value { font-size: 1rem; font-weight: 600; font-family: monospace; margin-top: 0.15rem; }
  .metric-value.warn { color: #fbbf24; }
  .metric-value.crit { color: #f87171; }
  .bar-bg { background: #334155; border-radius: 3px; height: 6px; margin-top: 0.25rem; }
  .bar-fill { background: #4ade80; border-radius: 3px; height: 100%; }
  .bar-fill.warn { background: #fbbf24; }
  .bar-fill.crit { background: #f87171; }
</style>
</head>
<body>
<h1>Thingino SNMP Monitor</h1>
<p class="timestamp">Last update: $now</p>
<div class="grid">
HTML

    while IFS='|' read -r name ip community; do
        if [ -f "$tmpdir/$name" ]; then
            local row
            row=$(cat "$tmpdir/$name")
            local status="${row%%|*}"
            local rest="${row#*|}"

            if [ "$status" = "ONLINE" ]; then
                local uptime_str mem_str load1 dsk_str descr processes net_rx net_tx net_if
                uptime_str=$(echo "$rest" | cut -d'|' -f1)
                mem_str=$(echo "$rest" | cut -d'|' -f2)
                mem_str="${mem_str%\%}"
                load1=$(echo "$rest" | cut -d'|' -f3)
                dsk_str=$(echo "$rest" | cut -d'|' -f4)
                descr=$(echo "$rest" | cut -d'|' -f5)
                processes=$(echo "$rest" | cut -d'|' -f6)
                net_rx=$(echo "$rest" | cut -d'|' -f7)
                net_tx=$(echo "$rest" | cut -d'|' -f8)
                net_if=$(echo "$rest" | cut -d'|' -f9)

                local net_rx_fmt net_tx_fmt
                net_rx_fmt=$(format_bytes "$net_rx")
                net_tx_fmt=$(format_bytes "$net_tx")

                # Color classes
                local mem_class="" mem_bar_class=""
                if [ "$mem_str" -gt 85 ] 2>/dev/null; then mem_class="crit"; mem_bar_class="crit"
                elif [ "$mem_str" -gt 70 ] 2>/dev/null; then mem_class="warn"; mem_bar_class="warn"; fi

                cat <<CARD
<div class="card">
  <div class="card-header">
    <span class="card-name online">$name</span>
    <span class="card-ip">$ip</span>
  </div>
  <div class="card-desc">$descr -- uptime: $uptime_str -- $processes processes</div>
  <div class="metrics">
    <div class="metric">
      <div class="metric-label">Memory Used</div>
      <div class="metric-value $mem_class">${mem_str}%</div>
      <div class="bar-bg"><div class="bar-fill $mem_bar_class" style="width:${mem_str}%"></div></div>
    </div>
    <div class="metric">
      <div class="metric-label">Load 1min</div>
      <div class="metric-value">$load1</div>
    </div>
    <div class="metric">
      <div class="metric-label">Disk Used</div>
      <div class="metric-value">$dsk_str</div>
    </div>
    <div class="metric">
      <div class="metric-label">$net_if RX</div>
      <div class="metric-value">$net_rx_fmt</div>
    </div>
    <div class="metric">
      <div class="metric-label">$net_if TX</div>
      <div class="metric-value">$net_tx_fmt</div>
    </div>
  </div>
</div>
CARD
            else
                cat <<CARD
<div class="card offline">
  <div class="card-header">
    <span class="card-name offline">$name</span>
    <span class="card-ip">$ip</span>
  </div>
  <div class="card-desc">[OFFLINE] no SNMP response</div>
</div>
CARD
            fi
        else
            cat <<CARD
<div class="card offline">
  <div class="card-header">
    <span class="card-name offline">$name</span>
    <span class="card-ip">$ip</span>
  </div>
  <div class="card-desc">[OFFLINE] Timeout</div>
</div>
CARD
        fi
    done < <(load_config)

    cat <<'HTML'
</div>
</body>
</html>
HTML

    if [ -n "$output" ]; then
        echo "HTML dashboard written to $output" >&2
    fi
}

cmd_alerts() {
    # Check all cameras and print alerts for any issues
    if ! load_config >/dev/null 2>&1; then
        die "No cameras configured."
    fi

    local tmpdir had_alert=0
    tmpdir=$(mktemp -d)
    trap "rm -rf $tmpdir" EXIT

    local pids=()
    while IFS='|' read -r name ip community; do
        (
            poll_camera "$name" "$ip" "$community" > "$tmpdir/$name"
        ) &
        pids+=($!)
    done < <(load_config)

    for pid in "${pids[@]}"; do
        wait "$pid" 2>/dev/null || true
    done

    while IFS='|' read -r name ip community; do
        if [ -f "$tmpdir/$name" ]; then
            local row
            row=$(cat "$tmpdir/$name")
            local status="${row%%|*}"
            local rest="${row#*|}"

            if [ "$status" != "ONLINE" ]; then
                echo "$(red "OFFLINE:") $name ($ip) - no SNMP response"
                had_alert=1
                continue
            fi

            local mem_pct
            mem_pct=$(echo "$rest" | cut -d'|' -f2 | tr -d '%')

            if [ "$mem_pct" -gt 90 ] 2>/dev/null; then
                echo "$(red "HIGH MEMORY:") $name ($ip) - ${mem_pct}% used"
                had_alert=1
            fi
        fi
    done < <(load_config)

    if [ "$had_alert" -eq 0 ]; then
        echo "$(green "ALL OK:") All cameras are online and healthy."
    fi
}

# -- detailed view -------------------------------------------------------
cmd_detail() {
    local name="$1"
    if [ -z "$name" ]; then
        die "Usage: $0 detail <name>"
    fi

    local config
    config=$(get_camera_config "$name")
    if [ -z "$config" ]; then
        die "Camera '$name' not found in config."
    fi

    local ip community
    ip=$(echo "$config" | cut -d'|' -f2)
    community=$(echo "$config" | cut -d'|' -f3)

    echo
    bold "=== $name ($ip) ==="
    echo

    # System
    local sys_descr sys_uptime sys_name sys_loc sys_contact
    sys_descr=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_DESCR")
    sys_uptime_raw=$(snmp_get "$ip" "$community" "$OID_SYS_UPTIME")
    sys_uptime_raw="${sys_uptime_raw#Timestamp: }"
    sys_uptime_raw="${sys_uptime_raw#Timeticks: }"
    local sys_uptime_str
    if echo "$sys_uptime_raw" | grep -q ':'; then
        sys_uptime_str="${sys_uptime_raw##* }"
    else
        sys_uptime_raw="${sys_uptime_raw%% *}"
        sys_uptime_str=$(format_uptime "$sys_uptime_raw")
    fi
    sys_name=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_NAME")
    sys_loc=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_LOCATION")
    sys_contact=$(snmp_get_stripped "$ip" "$community" "$OID_SYS_CONTACT")

    echo "  System:"
    echo "    Description: $sys_descr"
    echo "    Name:        $sys_name"
    echo "    Uptime:      $sys_uptime_str"
    [ -n "$sys_loc" ]     && echo "    Location:    $sys_loc"
    [ -n "$sys_contact" ] && echo "    Contact:     $sys_contact"
    echo

    # Memory
    local mem_total mem_avail mem_buf mem_cache
    mem_total=$(snmp_get "$ip" "$community" "$OID_MEM_TOTAL")
    mem_avail=$(snmp_get "$ip" "$community" "$OID_MEM_AVAIL")
    mem_buf=$(snmp_get "$ip" "$community" "$OID_MEM_BUFFER")
    mem_cache=$(snmp_get "$ip" "$community" "$OID_MEM_CACHED")

    echo "  Memory (KB):"
    printf '    %-12s %s\n' "Total:"    "$mem_total"
    printf '    %-12s %s\n' "Available:" "$mem_avail"
    printf '    %-12s %s\n' "Buffers:"   "$mem_buf"
    printf '    %-12s %s\n' "Cached:"    "$mem_cache"
    if [ "$mem_total" -gt 0 ] 2>/dev/null; then
        local used=$((mem_total - mem_avail))
        local pct=$((used * 100 / mem_total))
        printf '    %-12s %s (%s%%)\n' "Used:" "$used" "$pct"
    fi
    echo

    # CPU
    local cpu_user cpu_sys cpu_idle
    cpu_user=$(snmp_get "$ip" "$community" "$OID_CPU_USER")
    cpu_sys=$(snmp_get "$ip" "$community" "$OID_CPU_SYSTEM")
    cpu_idle=$(snmp_get "$ip" "$community" "$OID_CPU_IDLE")

    echo "  CPU (cumulative ticks since boot):"
    printf '    %-12s %s\n' "User:"   "$cpu_user"
    printf '    %-12s %s\n' "System:" "$cpu_sys"
    printf '    %-12s %s\n' "Idle:"   "$cpu_idle"
    echo

    # Load
    local la1 la5 la15
    la1=$(snmp_get_stripped "$ip" "$community" "$OID_LA_1")
    la5=$(snmp_get_stripped "$ip" "$community" "$OID_LA_5")
    la15=$(snmp_get_stripped "$ip" "$community" "$OID_LA_15")
    echo "  Load Average: $la1 / $la5 / $la15"
    echo

    # Disks
    echo "  Disks:"
    local dsk_count
    dsk_count=$(snmp_walk_count "$ip" "$community" "$OID_DSK_PATH")
    for idx in $(seq 1 "$dsk_count"); do
        local path total used pct
        path=$(snmp_get_stripped "$ip" "$community" "${OID_DSK_PATH}.$idx")
        total=$(snmp_get "$ip" "$community" "${OID_DSK_TOTAL}.$idx")
        used=$(snmp_get "$ip" "$community" "${OID_DSK_USED}.$idx")
        pct=$(snmp_get "$ip" "$community" "${OID_DSK_PERCENT}.$idx")
        printf '    %-16s total=%6sK  used=%6sK  (%s%%)\n' "$path" "$total" "$used" "$pct"
    done
    echo

    # Network interfaces
    echo "  Interfaces:"
    local if_count
    if_count=$(snmp_get "$ip" "$community" "$OID_IF_NUMBER")
    for idx in $(seq 1 "$if_count"); do
        local if_descr if_in if_out
        if_descr=$(snmp_get_stripped "$ip" "$community" "${OID_IF_DESCR}.$idx")
        if_in=$(snmp_get "$ip" "$community" "${OID_IF_IN_OCTETS}.$idx")
        if_out=$(snmp_get "$ip" "$community" "${OID_IF_OUT_OCTETS}.$idx")
        [ -z "$if_in" ] && if_in="?"; [ -z "$if_out" ] && if_out="?"
        local if_in_fmt if_out_fmt
        if_in_fmt=$(format_bytes "$if_in")
        if_out_fmt=$(format_bytes "$if_out")
        printf '    %-10s  RX: %s  TX: %s\n' "$if_descr" "$if_in_fmt" "$if_out_fmt"
    done
    echo

    # Processes
    local processes
    processes=$(snmp_get "$ip" "$community" "$OID_HR_PROCESSES" 2>/dev/null | tr -cd '0-9' || echo "?")
    [ -z "$processes" ] && processes="?"
    echo "  Running Processes: $processes"
    echo

    # SNMP stats
    local snmp_in
    snmp_in=$(snmp_get "$ip" "$community" "$OID_SNMP_IN")
    echo "  SNMP Packets Received: $snmp_in"
    echo
}

# -- usage ---------------------------------------------------------------
usage() {
    cat <<EOF
Usage: $0 <command> [args...]

Commands:
  status                  Print one-shot status table for all cameras
  watch [interval]        Continuously refresh status (default: ${DEFAULT_INTERVAL}s)
  detail <name>           Detailed view of a single camera
  discover [subnet]       Scan network for SNMP agents
  add <name> <ip> <comm>  Add a camera to the monitor config
  remove <name>           Remove a camera from the monitor config
  list                    List configured cameras
  html [file]             Generate static HTML dashboard
  alerts                  Check all cameras and report problems

Config: $CONFIG_FILE

Dependencies: snmpget, snmpwalk (package: snmp)
Optional: arp-scan or nmap (for discovery)
EOF
    exit 0
}

# -- main ----------------------------------------------------------------
main() {
    local cmd="${1:-}"
    shift || true

    case "$cmd" in
        status)   cmd_status "$@";;
        watch)    cmd_watch "$@";;
        detail)   cmd_detail "$@";;
        discover) cmd_discover "$@";;
        add)      cmd_add "$@";;
        remove)   cmd_remove "$@";;
        list)     cmd_list "$@";;
        html)     cmd_html "$@";;
        alerts)   cmd_alerts "$@";;
        -h|--help|help) usage;;
        "")       usage;;
        *)        echo "Unknown command: $cmd" >&2; usage;;
    esac
}

main "$@"
