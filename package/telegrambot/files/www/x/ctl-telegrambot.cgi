#!/bin/sh
CTL="/etc/init.d/telegrambot"
echo "Content-Type: application/json"; echo
case "$QUERY_STRING" in
   enabled=1)
      $CTL enable >/dev/null 2>&1
      $CTL restart >/dev/null 2>&1 || /etc/init.d/telegrambot start >/dev/null 2>&1
      echo '{"ok":true}'
      ;;
  enabled=0)
      $CTL stop >/dev/null 2>&1
      $CTL disable >/dev/null 2>&1
      echo '{"ok":true}'
      ;;
  status=1)
      $CTL enabled >/dev/null 2>&1 && eb=true || eb=false
      pidof telegrambot >/dev/null 2>&1 && er=true || er=false
      echo "{\"enabled_boot\":$eb,\"enabled_runtime\":$er}"
      ;;
   *)
      echo '{"ok":false}'
      ;;
esac
