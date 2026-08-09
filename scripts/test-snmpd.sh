#!/bin/bash
#
# test-snmpd.sh — exercise mini-snmpd on a Thingino camera
#
# Usage:  ./test-snmpd.sh [host] [community]
# Default: 192.168.88.127 public
#
# Requires: snmpget, snmpwalk (apt install snmp)

set -o pipefail

HOST="${1:-192.168.88.127}"
COMMUNITY="${2:-public}"
SNMP=(snmpget -v2c -c "$COMMUNITY" -Oqv -On "$HOST")
WALK=(snmpwalk -v2c -c "$COMMUNITY" -Oqn -On "$HOST")
PASS=0
FAIL=0
TOTAL=0

red()   { printf '\033[1;31m%s\033[0m\n' "$*"; }
green() { printf '\033[1;32m%s\033[0m\n' "$*"; }
bold()  { printf '\033[1m%s\033[0m\n' "$*"; }

check() {
    local label="$1" oid="$2" pattern="$3"
    TOTAL=$((TOTAL + 1))
    local val
    val=$("${SNMP[@]}" "$oid" 2>/dev/null) || true
    printf '  %-48s  ' "$label"
    if echo "$val" | grep -qi "$pattern"; then
        green "PASS"
        PASS=$((PASS + 1))
    else
        red "FAIL  (got: $val, expected: $pattern)"
        FAIL=$((FAIL + 1))
    fi
}

check_val() {
    local label="$1" oid="$2"
    TOTAL=$((TOTAL + 1))
    local val
    val=$("${SNMP[@]}" "$oid" 2>/dev/null) || true
    printf '  %-48s  ' "$label"
    if [ -n "$val" ] && ! echo "$val" | grep -qi "No Such\|Timeout\|Error\|Cannot"; then
        green "PASS  ($val)"
        PASS=$((PASS + 1))
    else
        red "FAIL  (no value)"
        FAIL=$((FAIL + 1))
    fi
}

# ── header ──────────────────────────────────────────────────────────
echo
bold "=== mini-snmpd Test — $HOST ==="
printf '  %-48s  ' "Agent reachable"
sysDescr=$("${SNMP[@]}" .1.3.6.1.2.1.1.1.0 2>/dev/null) || true
if [ -n "$sysDescr" ] && ! echo "$sysDescr" | grep -qi "Timeout\|Error"; then
    green "YES  ($sysDescr)"
else
    red "NO"
    exit 1
fi
echo

# ── SNMPv2-MIB system group ─────────────────────────────────────────
bold "── System (SNMPv2-MIB) ──"
check_val "sysDescr"         .1.3.6.1.2.1.1.1.0
check_val "sysUpTime"        .1.3.6.1.2.1.1.3.0
check_val "sysName"          .1.3.6.1.2.1.1.5.0

# sysORTable — count implemented MIBs
or_count=$("${WALK[@]}" .1.3.6.1.2.1.1.9.1.3 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "sysORTable MIB count"
if [ "$or_count" -ge 4 ]; then
    green "PASS  ($or_count MIBs advertised)"
    PASS=$((PASS + 1))
else
    red "FAIL  (only $or_count)"
    FAIL=$((FAIL + 1))
fi
echo

# ── IF-MIB ──────────────────────────────────────────────────────────
bold "── Interfaces (IF-MIB) ──"
check_val "ifNumber"         .1.3.6.1.2.1.2.1.0

if_count=$("${SNMP[@]}" .1.3.6.1.2.1.2.1.0 2>/dev/null || echo 0)
echo "  Interfaces: $if_count"

# Walk ifDescr, check each has operStatus
for idx in $(seq 1 "$if_count"); do
    descr=$("${SNMP[@]}" ".1.3.6.1.2.1.2.2.1.2.$idx" 2>/dev/null | tr -d '"' || echo "?")
    check_val "  $descr operStatus"  ".1.3.6.1.2.1.2.2.1.8.$idx"
done
echo

# ── IP-MIB ─────────────────────────────────────────────────────────
bold "── IP-MIB ──"
ip_count=$("${WALK[@]}" .1.3.6.1.2.1.4.34.1.3 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "ipAddressTable entries"
if [ "$ip_count" -ge 1 ]; then
    green "PASS  ($ip_count addresses)"
    PASS=$((PASS + 1))
else
    red "FAIL  (none)"
    FAIL=$((FAIL + 1))
fi
echo

# ── HOST-RESOURCES-MIB ─────────────────────────────────────────────
bold "── Host Resources (HOST-RESOURCES-MIB) ──"
check_val "hrMemorySize (KB)"        .1.3.6.1.2.1.25.2.2.0
check_val "hrSystemNumUsers"         .1.3.6.1.2.1.25.1.5.0
check_val "hrSystemProcesses"        .1.3.6.1.2.1.25.1.6.0

# hrStorageTable
stor_count=$("${WALK[@]}" .1.3.6.1.2.1.25.2.3.1.3 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "hrStorageTable entries"
if [ "$stor_count" -ge 2 ]; then
    green "PASS  ($stor_count volumes)"
    PASS=$((PASS + 1))
else
    red "FAIL  ($stor_count)"
    FAIL=$((FAIL + 1))
fi

# hrProcessorTable
cpu_count=$("${WALK[@]}" .1.3.6.1.2.1.25.3.3.1.2 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "hrProcessorTable entries"
if [ "$cpu_count" -ge 1 ]; then
    green "PASS  ($cpu_count CPUs)"
    PASS=$((PASS + 1))
else
    red "FAIL"
    FAIL=$((FAIL + 1))
fi
echo

# ── UCD-SNMP-MIB: memory ───────────────────────────────────────────
bold "── Memory (UCD-SNMP-MIB) ──"
check_val "memTotalReal"     .1.3.6.1.4.1.2021.4.5.0
check_val "memAvailReal"     .1.3.6.1.4.1.2021.4.6.0
check_val "memBuffer"        .1.3.6.1.4.1.2021.4.14.0
check_val "memCached"        .1.3.6.1.4.1.2021.4.15.0
echo

# ── UCD-SNMP-MIB: disks ────────────────────────────────────────────
bold "── Disks (UCD-SNMP-MIB dskTable) ──"
dsk_count=$("${WALK[@]}" .1.3.6.1.4.1.2021.9.1.2 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "dskTable entries"
if [ "$dsk_count" -ge 1 ]; then
    green "PASS  ($dsk_count mounts)"
    PASS=$((PASS + 1))
else
    red "FAIL"
    FAIL=$((FAIL + 1))
fi
for idx in $(seq 1 "$dsk_count"); do
    path=$("${SNMP[@]}" ".1.3.6.1.4.1.2021.9.1.2.$idx" 2>/dev/null | tr -d '"' || echo "?")
    total=$("${SNMP[@]}" ".1.3.6.1.4.1.2021.9.1.6.$idx" 2>/dev/null || echo "?")
    used=$("${SNMP[@]}"  ".1.3.6.1.4.1.2021.9.1.8.$idx" 2>/dev/null || echo "?")
    echo "    $path  total=${total}K  used=${used}K"
done
echo

# ── UCD-SNMP-MIB: load ─────────────────────────────────────────────
bold "── CPU Load (UCD-SNMP-MIB laTable) ──"
la_count=$("${WALK[@]}" .1.3.6.1.4.1.2021.10.1.3 2>/dev/null | wc -l)
TOTAL=$((TOTAL + 1))
printf '  %-48s  ' "laTable entries (1/5/15min)"
if [ "$la_count" -eq 3 ]; then
    green "PASS"
    PASS=$((PASS + 1))
    # Print values
    for idx in $(seq 1 3); do
        name=$("${SNMP[@]}" ".1.3.6.1.4.1.2021.10.1.2.$idx" 2>/dev/null | tr -d '"' || echo "?")
        load=$("${SNMP[@]}" ".1.3.6.1.4.1.2021.10.1.3.$idx" 2>/dev/null | tr -d '"' || echo "?")
        echo "    $name: $load"
    done
else
    red "FAIL  ($la_count)"
    FAIL=$((FAIL + 1))
fi
echo

# ── UCD-SNMP-MIB: system stats ─────────────────────────────────────
bold "── CPU Stats (UCD-SNMP-MIB systemStats) ──"
check_val "ssCpuUser (%)"   .1.3.6.1.4.1.2021.11.50.0
check_val "ssCpuSystem (%)" .1.3.6.1.4.1.2021.11.52.0
check_val "ssCpuIdle (%)"   .1.3.6.1.4.1.2021.11.53.0
echo

# ── Agent's own SNMP counters ──────────────────────────────────────
bold "── SNMP Agent Counters ──"
check_val "snmpInPkts"           .1.3.6.1.2.1.11.1.0
check_val "snmpSilentDrops"      .1.3.6.1.2.1.11.30.0
echo

# ── Full walk stats ────────────────────────────────────────────────
oid_total=$("${WALK[@]}" .1 2>/dev/null | wc -l)
echo "  Total OIDs served: $oid_total"

# ── Summary ─────────────────────────────────────────────────────────
echo
bold "=== RESULTS ==="
printf '  %d/%d passed  ' "$PASS" "$TOTAL"
if [ "$FAIL" -eq 0 ]; then
    green "ALL GOOD"
else
    red "$FAIL FAILED"
fi
echo

exit $FAIL
