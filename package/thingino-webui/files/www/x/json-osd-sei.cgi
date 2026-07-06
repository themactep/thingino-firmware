#!/bin/sh
# CGI proxy: forwards /api/v1/osd-sei from prudynt's HTTP server (port 8080)
# to uhttpd (port 80) so the web UI can fetch SEI data from the same origin.
echo "Content-Type: application/json"
echo ""
curl -s http://localhost:8080/api/v1/osd-sei
