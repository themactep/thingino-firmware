#!/bin/sh
# Correct HTTP header format
echo "Status: 302 Moved Temporarily"
echo "Location: http://thingino.local/index.html"
echo "Content-type: text/html; charset=UTF-8"
echo ""  # This empty line is crucial

