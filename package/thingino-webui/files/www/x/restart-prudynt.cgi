#!/bin/sh
# Restart prudynt service

echo "Content-Type: application/json"
echo

service restart prudynt >/dev/null 2>&1 &
echo '{"status":"ok","message":"Prudynt restart initiated"}'
