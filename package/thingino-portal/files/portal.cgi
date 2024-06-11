#!/bin/sh
# Correct HTTP header format
echo "Status: 303 See Other"
echo "Location: /index.html"
echo "Content-type: text/html; charset=UTF-8"
echo ""  # This empty line is crucial

