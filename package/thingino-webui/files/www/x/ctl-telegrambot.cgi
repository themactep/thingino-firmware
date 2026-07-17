#!/bin/sh
SVC="service telegrambot"
echo "Content-Type: application/json"
echo "Connection: close"
echo
case "$QUERY_STRING" in
   enabled=1)
      $SVC enable >/dev/null 2>&1
      $SVC restart >/dev/null 2>&1 || $SVC start >/dev/null 2>&1
      echo '{"ok":true}'
      ;;
   enabled=0)
      $SVC stop >/dev/null 2>&1
      $SVC disable >/dev/null 2>&1
      echo '{"ok":true}'
      ;;
   restart=1)
      $SVC restart >/dev/null 2>&1
      echo '{"ok":true}'
      ;;
   status=1)
      [ "$($SVC status 2>/dev/null)" = "enabled" ] && eb=true || eb=false
      pidof telegrambot >/dev/null 2>&1 && er=true || er=false
      echo "{\"enabled_boot\":$eb,\"enabled_runtime\":$er}"
      ;;
   *)
      echo '{"ok":false}'
      ;;
esac
