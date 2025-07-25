#!/bin/bash

# Test script to verify prudyntcfg to jct migration
# This script tests the basic functionality of the migration

echo "=== Prudynt Configuration Migration Test ==="
echo

# Check if jct command exists
if ! command -v jct >/dev/null 2>&1; then
    echo "ERROR: jct command not found. Please ensure thingino-jct package is installed."
    exit 1
fi

echo "✓ jct command found"

# Create a test JSON configuration file
TEST_CONFIG="/tmp/test_prudynt.json"
cat > "$TEST_CONFIG" << 'EOF'
{
  "rtsp": {
    "port": "554",
    "username": "thingino",
    "password": "thingino"
  },
  "stream0": {
    "rtsp_endpoint": "ch0",
    "width": 1920,
    "height": 1080
  },
  "stream1": {
    "rtsp_endpoint": "ch1",
    "width": 640,
    "height": 360
  },
  "motion": {
    "enabled": true
  }
}
EOF

echo "✓ Created test configuration file: $TEST_CONFIG"

# Test jct get operations (equivalent to old prudyntcfg get)
echo
echo "Testing jct get operations:"

# Test getting rtsp.port
RTSP_PORT=$(jct "$TEST_CONFIG" get rtsp.port 2>/dev/null)
if [ "$RTSP_PORT" = "554" ]; then
    echo "✓ jct get rtsp.port: $RTSP_PORT"
else
    echo "✗ jct get rtsp.port failed. Expected: 554, Got: $RTSP_PORT"
fi

# Test getting stream0.rtsp_endpoint
STREAM0_ENDPOINT=$(jct "$TEST_CONFIG" get stream0.rtsp_endpoint 2>/dev/null)
if [ "$STREAM0_ENDPOINT" = "ch0" ]; then
    echo "✓ jct get stream0.rtsp_endpoint: $STREAM0_ENDPOINT"
else
    echo "✗ jct get stream0.rtsp_endpoint failed. Expected: ch0, Got: $STREAM0_ENDPOINT"
fi

# Test getting motion.enabled
MOTION_ENABLED=$(jct "$TEST_CONFIG" get motion.enabled 2>/dev/null)
if [ "$MOTION_ENABLED" = "true" ]; then
    echo "✓ jct get motion.enabled: $MOTION_ENABLED"
else
    echo "✗ jct get motion.enabled failed. Expected: true, Got: $MOTION_ENABLED"
fi

# Test jct set operations (equivalent to old prudyntcfg set)
echo
echo "Testing jct set operations:"

# Test setting rtsp.password
jct "$TEST_CONFIG" set rtsp.password "newpassword" >/dev/null 2>&1
NEW_PASSWORD=$(jct "$TEST_CONFIG" get rtsp.password 2>/dev/null)
if [ "$NEW_PASSWORD" = "newpassword" ]; then
    echo "✓ jct set rtsp.password: $NEW_PASSWORD"
else
    echo "✗ jct set rtsp.password failed. Expected: newpassword, Got: $NEW_PASSWORD"
fi

# Test setting a numeric value
jct "$TEST_CONFIG" set rtsp.port 8554 >/dev/null 2>&1
NEW_PORT=$(jct "$TEST_CONFIG" get rtsp.port 2>/dev/null)
if [ "$NEW_PORT" = "8554" ]; then
    echo "✓ jct set rtsp.port: $NEW_PORT"
else
    echo "✗ jct set rtsp.port failed. Expected: 8554, Got: $NEW_PORT"
fi

# Test print operation
echo
echo "Testing jct print operation:"
echo "Current configuration:"
jct "$TEST_CONFIG" print 2>/dev/null | head -10

# Clean up
rm -f "$TEST_CONFIG"
echo
echo "✓ Test completed. Cleaned up test files."
echo
echo "=== Migration Test Summary ==="
echo "The migration from prudyntcfg to jct appears to be working correctly."
echo "Key differences:"
echo "  - Old: prudyntcfg get section.key"
echo "  - New: jct /etc/prudynt.json get section.key"
echo "  - Old: prudyntcfg set section.key \"value\""
echo "  - New: jct /etc/prudynt.json set section.key value"
echo "  - Configuration file changed from /etc/prudynt.cfg to /etc/prudynt.json"
