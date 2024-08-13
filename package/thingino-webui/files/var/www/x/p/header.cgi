#!/usr/bin/haserl
Content-type: text/html; charset=UTF-8
Date: <%= $(time_http) %>
Server: <%= $SERVER_SOFTWARE %>
Cache-Control: no-store
Pragma: no-cache

<!DOCTYPE html>
<html lang="en" data-bs-theme="<%= ${webui_theme:=dark} %>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title><% html_title %></title>
<link rel="stylesheet" href="/a/bootstrap.min.css">
<link rel="stylesheet" href="/a/bootstrap.override.css">
<script src="/a/bootstrap.bundle.min.js"></script>
<script src="/a/main.js"></script>
</head>

<body id="page-<%= $pagename %>" class="<%= ${webui_level:-user} %><% [ "$debug" -gt 0 ] && echo -n " debug" %>">
<nav class="navbar navbar-expand-lg bg-body-tertiary">
<div class="container">
<a class="navbar-brand" href="status.cgi"><img alt="Image: thingino logo" width="150" src="/a/logo.svg"></a>
<button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#navbarNav" aria-controls="navbarNav" aria-expanded="false" aria-label="Toggle navigation">
<span class="navbar-toggler-icon"></span>
</button>
<div class="collapse navbar-collapse justify-content-end" id="navbarNav">
<ul class="navbar-nav">
<li class="nav-item dropdown">
<a aria-expanded="false" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="dropdownInformation" role="button">Information</a>
<ul aria-labelledby="dropdownInformation" class="dropdown-menu">
<li><a class="dropdown-item" href="status.cgi">Overview</a></li>
<li><a class="dropdown-item" href="info-cron.cgi">Cron Configuration</a></li>
<li><a class="dropdown-item" href="info-httpd.cgi">HTTPd Environment</a></li>
<li><a class="dropdown-item" href="info-top.cgi">Top Processes</a></li>
<li><a class="dropdown-item" href="info-overlay.cgi">Overlay Partition</a></li>
<% if [ -e /proc/umap ]; then %>
<li><a class="dropdown-item" href="info-proc-umap.cgi">Information from /proc/umap</a></li>
<% fi %>
<li><a class="dropdown-item" href="info-netstat.cgi">netstat</a></li>
<li><a class="dropdown-item" href="info-snmp.cgi">snmp</a></li>
<li><a class="dropdown-item" href="info-modules.cgi">lsmod</a></li>
<li><a class="dropdown-item" href="info-dmesg.cgi">dmesg</a></li>
<li><a class="dropdown-item" href="info-log.cgi">logread</a></li>
<li><a class="dropdown-item" href="info-weblog.cgi">WebUI Log</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a aria-expanded="false" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="dropdownSettings" role="button">Settings</a>
<ul aria-labelledby="dropdownSettings" class="dropdown-menu">
<li><a class="dropdown-item" href="config-audio.cgi">Audio</a></li>
<li><a class="dropdown-item" href="config-wlan.cgi">Wi-Fi</a></li>
<li><a class="dropdown-item" href="config-network.cgi">Network</a></li>
<li><a class="dropdown-item" href="config-hostname.cgi">Hostname</a></li>
<li><a class="dropdown-item" href="config-time.cgi">Time</a></li>
<li><a class="dropdown-item" href="config-indication.cgi">LED Indicators</a></li>
<li><a class="dropdown-item" href="config-light.cgi">Illumination</a></li>
<li><a class="dropdown-item" href="config-record.cgi">Local Recording</a></li>
<li><a class="dropdown-item" href="config-rtsp.cgi">RTSP/ONVIF Access</a></li>
<% if [ -f /bin/motors ]; then %>
<li><a class="dropdown-item" href="config-motors.cgi">Motors</a></li>
<% fi %>
<li><a class="dropdown-item" href="config-osd.cgi">OSD</a></li>
<li><a class="dropdown-item" href="config-imp.cgi">IMP Control</a></li>
<li><a class="dropdown-item" href="config-socks5.cgi">SOCKS5 Proxy</a></li>
<li><a class="dropdown-item" href="config-webui.cgi">Web Interface</a></li>
<li><a class="dropdown-item" href="config-admin.cgi">Admin Profile</a></li>
<!--<li><a class="dropdown-item" href="config-users.cgi">Users</a></li>-->
<li><a class="dropdown-item" href="config-developer.cgi">Developer</a></li>
<li><hr class="dropdown-divider"></li>
<li><a class="dropdown-item" href="reset.cgi">Reset...</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a aria-expanded="false" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="dropdownTools" role="button">Tools</a>
<ul aria-labelledby="dropdownTools" class="dropdown-menu">
<li><a class="dropdown-item" href="tools.cgi">Ping & Traceroute</a></li>
<li><a class="dropdown-item" href="file-manager.cgi">File Manager</a></li>
<li><a class="dropdown-item" href="sdcard.cgi">SD Card</a></li>
<li><a class="dropdown-item" href="ssh-keys.cgi">SSH Key</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a aria-expanded="false" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="dropdownServices" role="button">Services</a>
<ul aria-labelledby="dropdownServices" class="dropdown-menu">
<% load_plugins %>
</ul>
</li>
<li class="nav-item"><a class="nav-link" href="preview.cgi">Preview</a></li>
<li class="nav-item dropdown">
<a aria-expanded="false" class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="dropdownHelp" role="button">Help</a>
<ul aria-labelledby="dropdownHelp" class="dropdown-menu dropdown-menu-lg-end">
<li><a class="dropdown-item" href="https://thingino.com/">About thingino</a></li>
</ul>
</li>
</ul>
</div>
</div>
</nav>

<main class="pb-4">
<div class="container" style="min-height: 85vh">
<div class="row mt-1 x-small">
<div class="col-lg-2">
<div class="progress-stacked memory my-1">
<div class="progress" role="progressbar" aria-label="Active" id="pb-memory-active">
<div class="progress-bar"></div>
</div>
<div class="progress" role="progressbar" aria-label="Buffers" id="pb-memory-buffers">
<div class="progress-bar"></div>
</div>
<div class="progress" role="progressbar" aria-label="Cached" id="pb-memory-cached">
<div class="progress-bar"></div>
</div>
</div>
<div class="progress-stacked overlay my-1">
<div class="progress" role="progressbar" id="pb-overlay-used">
<div class="progress-bar"></div>
</div>
</div>
</div>
<div class="col-md-6 mb-2">
<%= $(signature) %>
</div>
<div class="col-1" id="daynight_value"></div>
<div class="col-md-4 col-lg-3 mb-2 text-end">
<div><a href="/x/config-time.cgi" id="time-now" class="link-underline link-underline-opacity-0 link-underline-opacity-75-hover"></a></div>
</div>
</div>
<% if [ -z "$network_gateway" ]; then %>
<div class="alert alert-warning">
<p class="mb-0">No Internet connection. Please <a href="config-network.cgi">check your network settings</a>.</p>
</div>
<% fi %>

<% if [ "true" = "$telegram_socks5_enabled" ] || [ "true" = "$yadisk_socks5_enabled" ]; then
if [ -z "$socks5_host" ] || [ -z "$socks5_port" ]; then %>
<div class="alert alert-danger">
<p class="mb-0">You want to use SOCKS5 proxy but it is not configured! Please <a href="config-socks5.cgi">configure the proxy</a>.</p>
</div>
<% fi; fi %>

<% if [ "$(cat /etc/TZ)" != "$TZ" ]; then %>
<div class="alert alert-danger">
<p>$TZ variable in system environment needs updating!</p>
<span class="d-flex gap-3">
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<a class="btn btn-primary" href="config-time.cgi">See timezone settings</a>
</span>
</div>
<% fi %>

<% if [ -f /tmp/network-restart.txt ]; then %>
<div class="alert alert-danger">
<p>Network settings have been updated. Restart to apply changes.</p>
<span class="d-flex gap-3">
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<a class="btn btn-primary" href="config-network.cgi">See network settings</a>
</span>
</div>
<% fi %>

<% if [ -f /tmp/motionguard-restart.txt ]; then %>
<div class="alert alert-danger">
<p>Changes to motion guard configuration detected. Please restart camera to apply the changes.</p>
<span class="d-flex gap-3">
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<a class="btn btn-primary" href="plugin-motion.cgi">See motion guard settings</a>
</span>
</div>
<% fi %>

<h2><%= $page_title %></h2>
<% alert_read %>
