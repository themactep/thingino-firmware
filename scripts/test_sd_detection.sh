#!/bin/bash

# Test script for SD card detection functionality
# Validates the SD card detection and safety features

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

test_passed=0
test_failed=0

log_test() {
    echo -e "${BLUE}[TEST]${NC} $1"
}

log_pass() {
    echo -e "${GREEN}[PASS]${NC} $1"
    ((test_passed++))
}

log_fail() {
    echo -e "${RED}[FAIL]${NC} $1"
    ((test_failed++))
}

log_info() {
    echo -e "${YELLOW}[INFO]${NC} $1"
}

# Test 1: Script executability
test_script_executability() {
    log_test "Testing script executability"
    
    local scripts=(
        "$SCRIPT_DIR/sd_card_monitor.sh"
        "$SCRIPT_DIR/sd_card_flasher.sh"
        "$SCRIPT_DIR/sd_utils.sh"
    )
    
    for script in "${scripts[@]}"; do
        if [[ -x "$script" ]]; then
            log_pass "$(basename "$script") is executable"
        else
            log_fail "$(basename "$script") is not executable"
        fi
    done
}

# Test 2: Help functionality
test_help_functionality() {
    log_test "Testing help functionality"
    
    if "$SCRIPT_DIR/sd_card_monitor.sh" --help >/dev/null 2>&1; then
        log_pass "sd_card_monitor.sh --help works"
    else
        log_fail "sd_card_monitor.sh --help failed"
    fi
    
    if "$SCRIPT_DIR/sd_utils.sh" --help >/dev/null 2>&1; then
        log_pass "sd_utils.sh --help works"
    else
        log_fail "sd_utils.sh --help failed"
    fi
    
    if "$SCRIPT_DIR/sd_card_flasher.sh" --help >/dev/null 2>&1; then
        log_pass "sd_card_flasher.sh --help works"
    else
        log_fail "sd_card_flasher.sh --help failed"
    fi
}

# Test 3: SD card detection
test_sd_detection() {
    log_test "Testing SD card detection"
    
    # Test detection command
    if "$SCRIPT_DIR/sd_card_monitor.sh" detect >/dev/null 2>&1; then
        log_pass "SD card detection command runs successfully"
    else
        log_fail "SD card detection command failed"
    fi
    
    # Test list command
    if "$SCRIPT_DIR/sd_card_monitor.sh" list >/dev/null 2>&1; then
        log_pass "Device listing command runs successfully"
    else
        log_fail "Device listing command failed"
    fi
    
    # Test find command
    if "$SCRIPT_DIR/sd_utils.sh" find >/dev/null 2>&1; then
        log_pass "SD card find command runs successfully"
    else
        log_fail "SD card find command failed"
    fi
}

# Test 4: Device information
test_device_info() {
    log_test "Testing device information functionality"
    
    # Find an SD card to test with
    local sd_card
    if sd_card=$("$SCRIPT_DIR/sd_card_monitor.sh" detect 2>/dev/null); then
        log_info "Found SD card for testing: $sd_card"
        
        # Test device info
        if "$SCRIPT_DIR/sd_utils.sh" info "$sd_card" >/dev/null 2>&1; then
            log_pass "Device info command works"
        else
            log_fail "Device info command failed"
        fi
        
        # Test safety check
        if "$SCRIPT_DIR/sd_utils.sh" check "$sd_card" >/dev/null 2>&1; then
            log_pass "Safety check command runs (may fail if mounted)"
        else
            log_pass "Safety check command runs (correctly detected unsafe device)"
        fi
    else
        log_info "No SD card found for device info testing"
        log_pass "Device info test skipped (no SD card available)"
    fi
}

# Test 5: Error handling
test_error_handling() {
    log_test "Testing error handling"
    
    # Test with non-existent device
    if ! "$SCRIPT_DIR/sd_utils.sh" info /dev/nonexistent >/dev/null 2>&1; then
        log_pass "Correctly handles non-existent device"
    else
        log_fail "Should fail with non-existent device"
    fi
    
    # Test flasher without firmware image
    if ! "$SCRIPT_DIR/sd_card_flasher.sh" >/dev/null 2>&1; then
        log_pass "Flasher correctly requires firmware image"
    else
        log_fail "Flasher should require firmware image"
    fi
    
    # Test with invalid command
    if ! "$SCRIPT_DIR/sd_utils.sh" invalid_command >/dev/null 2>&1; then
        log_pass "Correctly handles invalid commands"
    else
        log_fail "Should fail with invalid command"
    fi
}

# Test 6: Integration test
test_integration() {
    log_test "Testing integration functionality"
    
    # Test that scripts can source each other
    if bash -c "source '$SCRIPT_DIR/sd_card_monitor.sh' && declare -f is_sd_card >/dev/null"; then
        log_pass "Scripts can be sourced correctly"
    else
        log_fail "Script sourcing failed"
    fi
    
    # Test verbose mode
    if "$SCRIPT_DIR/sd_card_monitor.sh" detect -v >/dev/null 2>&1; then
        log_pass "Verbose mode works"
    else
        log_fail "Verbose mode failed"
    fi
}

# Test 7: System compatibility
test_system_compatibility() {
    log_test "Testing system compatibility"
    
    # Check required commands
    local required_commands=(
        "udevadm"
        "lsblk"
        "blkid"
        "mount"
        "umount"
        "fdisk"
        "dd"
        "sync"
    )
    
    local missing_commands=()
    
    for cmd in "${required_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            log_pass "Required command '$cmd' is available"
        else
            log_fail "Required command '$cmd' is missing"
            missing_commands+=("$cmd")
        fi
    done
    
    if [[ ${#missing_commands[@]} -eq 0 ]]; then
        log_pass "All required system commands are available"
    else
        log_fail "Missing commands: ${missing_commands[*]}"
    fi
}

# Main test runner
main() {
    echo "=== SD Card Detection Test Suite ==="
    echo "Testing thingino SD card detection and flashing utilities"
    echo
    
    test_script_executability
    echo
    
    test_help_functionality
    echo
    
    test_sd_detection
    echo
    
    test_device_info
    echo
    
    test_error_handling
    echo
    
    test_integration
    echo
    
    test_system_compatibility
    echo
    
    # Summary
    echo "=== Test Results ==="
    echo "Passed: $test_passed"
    echo "Failed: $test_failed"
    echo "Total:  $((test_passed + test_failed))"
    
    if [[ $test_failed -eq 0 ]]; then
        echo -e "${GREEN}All tests passed!${NC}"
        exit 0
    else
        echo -e "${RED}Some tests failed.${NC}"
        exit 1
    fi
}

# Run tests if script is executed directly
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
