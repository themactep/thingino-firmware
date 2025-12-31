#!/bin/sh
# Export full prudynt configuration from memory

echo "Content-Type: application/json"
echo "Content-Disposition: attachment; filename=\"prudynt-config-$(date +%Y%m%d-%H%M%S).json\""
echo

# Use dump_config action to get full config from memory
echo '{"action":{"dump_config":null}}' | prudyntctl json -
