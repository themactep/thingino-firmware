#!/bin/haserl
Content-type: text/plain; charset=UTF-8
Date: <%= TZ=GMT0 date "%a, %d %b %Y %T %Z" %>
Server: Thingino Captive Portal
Cache-Control: no-store
Pragma: no-cache

<%
fw_setenv wlanssid $POST_ssid
fw_setenv wlanpass $POST_password
echo "Credentials set. Rebooting..."
reboot
%>
