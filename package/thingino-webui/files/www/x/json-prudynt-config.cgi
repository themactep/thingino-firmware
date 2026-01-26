#!/bin/sh
# Export full prudynt configuration from memory

printf "Content-Type: application/json\r\n"
printf "Content-Disposition: attachment; filename=\"prudynt-config-$(date +%Y%m%d-%H%M%S).json\"\r\n"
printf "\r\n"

# Use dump_config action to get full config from memory
echo '{"action":{"dump_config":null}}' | prudyntctl json -
