#!/bin/sh

# Prudynt Debug Helper Script
# This script provides debugging utilities for the Prudynt debug build
# This script is compatible with the BusyBox environment used in thingino firmware.

set -e

PRUDYNT_BIN="/usr/bin/prudynt"
PRUDYNT_DEBUG_BIN="/usr/bin/prudynt-debug"
DEBUG_INFO="/usr/share/prudynt-debug-info.txt"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_header() {
    printf "${BLUE}=== Prudynt Debug Helper ===${NC}\n"
    echo
}

print_status() {
    status=$1
    message=$2
    case $status in
        "INFO")
            printf "${BLUE}[INFO]${NC} %s\n" "$message"
            ;;
        "WARN")
            printf "${YELLOW}[WARN]${NC} %s\n" "$message"
            ;;
        "ERROR")
            printf "${RED}[ERROR]${NC} %s\n" "$message"
            ;;
        "SUCCESS")
            printf "${GREEN}[SUCCESS]${NC} %s\n" "$message"
            ;;
    esac
}

show_debug_info() {
    print_header
    if [ -f "$DEBUG_INFO" ]; then
        cat "$DEBUG_INFO"
    else
        print_status "WARN" "Debug info file not found. This may not be a debug build."
    fi
    echo
}

check_debug_build() {
    if [ ! -f "$PRUDYNT_DEBUG_BIN" ]; then
        print_status "ERROR" "Debug binary not found. This is not a debug build."
        return 1
    fi

    # Check for AddressSanitizer
    if ldd "$PRUDYNT_BIN" 2>/dev/null | grep -q "asan"; then
        print_status "SUCCESS" "AddressSanitizer detected in binary"
        ASAN_AVAILABLE=true
    else
        print_status "INFO" "AddressSanitizer not available (normal for embedded builds)"
        ASAN_AVAILABLE=false
    fi

    # Check for UBSan
    if ldd "$PRUDYNT_BIN" 2>/dev/null | grep -q "ubsan"; then
        print_status "SUCCESS" "UndefinedBehaviorSanitizer detected in binary"
        UBSAN_AVAILABLE=true
    else
        print_status "INFO" "UndefinedBehaviorSanitizer not available (normal for musl builds)"
        UBSAN_AVAILABLE=false
    fi

    # Check for debug symbols
    if objdump -h "$PRUDYNT_BIN" 2>/dev/null | grep -q "debug"; then
        print_status "SUCCESS" "Debug symbols found in binary"
    else
        print_status "WARN" "Debug symbols not found in main binary"
    fi

    # Check for debug build flags
    if strings "$PRUDYNT_BIN" 2>/dev/null | grep -q "DEBUG_BUILD"; then
        print_status "SUCCESS" "Debug build detected (DEBUG_BUILD flag found)"
    else
        print_status "INFO" "Debug build flags not detected in binary"
    fi
}

run_with_asan() {
    print_status "INFO" "Running Prudynt with debug options..."

    # Set sanitizer options only if available
    if [ "${ASAN_AVAILABLE:-false}" = "true" ]; then
        ASAN_OPTIONS="abort_on_error=1:halt_on_error=1:print_stats=1:check_initialization_order=1"
        export ASAN_OPTIONS
        print_status "INFO" "ASAN_OPTIONS: $ASAN_OPTIONS"
    fi

    if [ "${UBSAN_AVAILABLE:-false}" = "true" ]; then
        UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"
        export UBSAN_OPTIONS
        print_status "INFO" "UBSAN_OPTIONS: $UBSAN_OPTIONS"
    fi

    if [ "${ASAN_AVAILABLE:-false}" = "false" ] && [ "${UBSAN_AVAILABLE:-false}" = "false" ]; then
        print_status "INFO" "No sanitizers available - running with debug symbols and stack protection"
    fi

    echo
    exec "$PRUDYNT_BIN" "$@"
}

run_with_gdb() {
    # Check for gdbserver first (preferred for embedded systems)
    if command -v gdbserver >/dev/null 2>&1; then
        print_status "INFO" "GDBserver found - setting up remote debugging..."

        # Default port for gdbserver
        GDB_PORT="${GDB_PORT:-2345}"

        print_status "INFO" "Starting GDBserver on port $GDB_PORT"
        printf "${BLUE}=== Remote Debugging Setup ===${NC}\n"
        echo
        printf "${YELLOW}On Camera (this device):${NC}\n"
        printf "  gdbserver :$GDB_PORT $PRUDYNT_DEBUG_BIN %s\n" "$*"
        echo
        printf "${YELLOW}On Development Machine:${NC}\n"
        printf "  gdb $PRUDYNT_DEBUG_BIN\n"
        printf "  (gdb) target remote CAMERA_IP:$GDB_PORT\n"
        printf "  (gdb) set environment ASAN_OPTIONS=abort_on_error=1:halt_on_error=1\n"
        printf "  (gdb) set environment UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1\n"
        printf "  (gdb) continue\n"
        echo
        printf "${BLUE}Starting gdbserver now...${NC}\n"
        echo

        # Set sanitizer options for the debug session
        if [ "${ASAN_AVAILABLE:-false}" = "true" ]; then
            ASAN_OPTIONS="abort_on_error=1:halt_on_error=1:print_stats=1:check_initialization_order=1"
            export ASAN_OPTIONS
        fi

        if [ "${UBSAN_AVAILABLE:-false}" = "true" ]; then
            UBSAN_OPTIONS="print_stacktrace=1:halt_on_error=1"
            export UBSAN_OPTIONS
        fi

        # Start gdbserver
        exec gdbserver ":$GDB_PORT" "$PRUDYNT_DEBUG_BIN" "$@"

    elif command -v gdb >/dev/null 2>&1; then
        print_status "INFO" "Local GDB found - starting interactive debugging..."
        print_status "INFO" "Use 'run' to start, 'bt' for backtrace, 'info registers' for register state"
        echo

        gdb -ex "set environment ASAN_OPTIONS=abort_on_error=1:halt_on_error=1" \
            -ex "set environment UBSAN_OPTIONS=print_stacktrace=1:halt_on_error=1" \
            "$PRUDYNT_DEBUG_BIN"
    else
        print_status "ERROR" "Neither gdbserver nor gdb found."
        print_status "INFO" "For remote debugging, gdbserver should be available in thingino firmware."
        print_status "INFO" "For local debugging, install gdb package."
        return 1
    fi
}

show_memory_info() {
    print_status "INFO" "Current memory usage:"
    free -h
    echo

    print_status "INFO" "Process memory if Prudynt is running:"
    if pgrep prudynt >/dev/null; then
        # BusyBox ps doesn't support aux, use basic ps and filter
        ps | grep prudynt | grep -v grep
        echo

        pid=$(pgrep prudynt)
        if [ -f "/proc/$pid/status" ]; then
            print_status "INFO" "Detailed memory info for PID $pid:"
            grep -E "VmSize|VmRSS|VmPeak|VmHWM" "/proc/$pid/status"
        fi
    else
        print_status "INFO" "Prudynt is not currently running"
    fi
}

show_usage() {
    echo "Usage: $0 [COMMAND] [OPTIONS]"
    echo
    echo "Commands:"
    echo "  info          Show debug build information"
    echo "  check         Check if this is a debug build"
    echo "  run [args]    Run Prudynt with AddressSanitizer options"
    echo "  gdb [args]    Start GDBserver for remote debugging (or local GDB if available)"
    echo "  memory        Show current memory usage information"
    echo "  manual        Show comprehensive remote debugging manual"
    echo "  help          Show this help message"
    echo
    echo "Examples:"
    echo "  $0 info                    # Show debug build info"
    echo "  $0 run                     # Run with memory safety checking"
    echo "  $0 gdb                     # Start remote debugging with gdbserver"
    echo "  $0 memory                  # Check memory usage"
    echo
    echo "Environment Variables:"
    echo "  GDB_PORT      Port for gdbserver (default: 2345)"
}

case "${1:-help}" in
    "info")
        show_debug_info
        ;;
    "check")
        check_debug_build
        ;;
    "run")
        shift
        run_with_asan "$@"
        ;;
    "gdb")
        shift
        run_with_gdb "$@"
        ;;
    "memory")
        show_memory_info
        ;;
    "help"|*)
        show_usage
        ;;
esac
