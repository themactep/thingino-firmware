#!/bin/sh

printf "Status: 200 OK\r\n"
printf "Content-Type: text/html; charset=utf-8\r\n"
printf "Clear-Site-Data: \"cache\"\r\n"
printf "Cache-Control: no-store, no-cache, must-revalidate, max-age=0\r\n"
printf "Pragma: no-cache\r\n"
printf "Connection: close\r\n"
printf "\r\n"
printf '%s\n' '<!doctype html><html><head><meta charset="utf-8"><meta http-equiv="refresh" content="0; url=/"><title>Redirecting...</title></head><body><script>window.location.replace("/");</script></body></html>'

