#!/bin/haserl
Content-type: text/html; charset=UTF-8
Date: <%= $(time_http) %>
Server: <%= $SERVER_SOFTWARE %>
Cache-Control: no-store
Pragma: no-cache

<!DOCTYPE html>
<html lang="en" data-bs-theme="<% html_theme %>">
<head>
<meta charset="utf-8">
<meta name="viewport" content="width=device-width,initial-scale=1">
<title><% html_title %></title>
<link rel="icon" type="image/svg+xml" href="/a/favicon.svg">
<% if is_isolated; then %>
<link rel="stylesheet" href="/a/bootstrap.min.css">
<script src="/a/bootstrap.bundle.min.js"></script>
<% else %>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="preconnect" href="https://fonts.gstatic.com" crossorigin>
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Montserrat:ital,wght@0,100..900;1,100..900&display=swap">
<link rel="stylesheet" href="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/css/bootstrap.min.css"
 integrity="sha384-QWTKZyjpPEjISv5WaRU9OFeRpok6YctnYmDr5pNlyT2bRjXh0JMhjY6hW+ALEwIH" crossorigin="anonymous">
<script src="https://cdn.jsdelivr.net/npm/bootstrap@5.3.3/dist/js/bootstrap.bundle.min.js"
 integrity="sha384-YvpcrYf0tY3lHB60NNkmXc5s9fDVZLESaAA55NDzOxhy9GkcIdslK1eN7N6jIeHz" crossorigin="anonymous"></script>
<% fi %>
<link rel="stylesheet" href="/a/main.css?ts=<%= $assets_ts %>">
<script src="/a/main.js?ts=<%= $assets_ts %>"></script>
</head>

<body id="page-<%= $pagename %>"<% is_isolated && echo -n ' class="paranoid"' %>>
<nav class="navbar navbar-expand-lg bg-body-tertiary">
<div class="container">
<a class="navbar-brand" href="/"><img alt="Image: thingino logo" width="150" src="/a/logo.svg"></a>
<button class="navbar-toggler" type="button" data-bs-toggle="collapse" data-bs-target="#nbMain"
aria-controls="nbMain" aria-label="Toggle navigation"><span class="navbar-toggler-icon"></span></button>

<div class="collapse navbar-collapse justify-content-end" id="nbMain">
<ul class="navbar-nav">
<li class="nav-item dropdown">
<a class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="ddInfo" role="button">Information</a>
<ul aria-labelledby="ddInfo" class="dropdown-menu">
<li><a class="dropdown-item" href="info.cgi">Commands and logs</a></li>
<li><a class="dropdown-item" href="info-diagnostic.cgi">Share diagnostic info</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="ddSettings" role="button">Settings</a>
<ul aria-labelledby="ddSettings" class="dropdown-menu">
<% menu "config" %>
<li><hr class="dropdown-divider"></li>
<li><a class="dropdown-item" href="reset.cgi">Reset...</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="ddTools" role="button">Tools</a>
<ul aria-labelledby="ddTools" class="dropdown-menu">
<% menu "tool" %>
<li><a href="reboot.cgi" class="dropdown-item bg-danger confirm">⏼ Reboot</a></li>
</ul>
</li>
<li class="nav-item dropdown">
<a class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="ddServices" role="button">Services</a>
<ul aria-labelledby="ddServices" class="dropdown-menu">
<% menu "service" %>
</ul>
</li>
<li class="nav-item">
<a class="nav-link" href="preview.cgi">Preview</a>
</li>
<li class="nav-item dropdown">
<a class="nav-link dropdown-toggle" data-bs-toggle="dropdown" href="#" id="ddHelp" role="button">Help</a>
<ul aria-labelledby="ddHelp" class="dropdown-menu dropdown-menu-lg-end">
<li><a class="dropdown-item" href="https://thingino.com/">About thingino</a></li>
</ul>
</li>
</ul>
</div>

</div>
</nav>

<main class="pb-4">
<div class="container" style="min-height: 80vh">

<div class="row my-2 x-small">
<div class="col col-10 col-md-3 col-lg-2">
<div class="progress-stacked memory my-1">
<div class="progress" role="progressbar" aria-label="Active" id="pb-memory-active"><div class="progress-bar"></div></div>
<div class="progress" role="progressbar" aria-label="Buffers" id="pb-memory-buffers"><div class="progress-bar"></div></div>
<div class="progress" role="progressbar" aria-label="Cached" id="pb-memory-cached"><div class="progress-bar"></div></div>
</div>
<div class="progress-stacked overlay">
<div class="progress" role="progressbar" id="pb-overlay-used"><div class="progress-bar"></div></div>
</div>
</div>
<div class="col col-2 col-md-2 col-lg-1">
<% if pidof record > /dev/null; then %>
<a href="service-videorec.cgi" id="recording" class="link-underline link-underline-opacity-0 icon blink me-2"
data-bs-toggle="tooltip" data-bs-title="Recording in progress">⏺</a>
<% else %>
<a href="service-videorec.cgi" id="recording" class="link-underline link-underline-opacity-0 icon me-2"
data-bs-toggle="tooltip" data-bs-title="Recording stopped">⏹</a>
<% fi %>
<a href="config-daynight.cgi" class="gain link-underline link-underline-opacity-0 link-underline-opacity-75-hover"
 data-bs-toggle="tooltip" data-bs-title="Sensor gain value. If the Day/Night script is enabled, the camera will switch
 to Day mode when the gain falls below <%= $day_night_min %>, and to Night mode if the gain rises above <%= $day_night_max %>.
 Click on the link to set the thresholds."></a>
</div>
<div class="col col-12 col-md-7 col-lg-6 col-xl-5"><%= $(signature) %></div>
<div class="col col-12 col-md-12 col-lg-3 col-xl-4 text-end"><a href="/x/config-time.cgi" id="time-now"
class="link-underline link-underline-opacity-0 link-underline-opacity-75-hover"></a></div>
</div>

<% if ! is_ap && [ -z "$network_gateway" ]; then %>
<div class="alert alert-warning">
<p class="mb-0">No Internet connection. Please <a href="config-network.cgi">check your network settings</a>.</p>
</div>
<% fi %>

<% if [ "$(cat /etc/TZ)" != "$TZ" ]; then %>
<div class="alert alert-danger">
<p>$TZ variable in system environment needs updating!</p>
<span class="d-flex flex-wrap gap-3">
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<a class="btn btn-primary" href="config-time.cgi">See timezone settings</a>
</span>
</div>
<% fi %>

<% if [ -f /tmp/network-restart.txt ]; then %>
<div class="alert alert-danger">
<p>Network settings have been updated. Restart to apply changes.</p>
<span class="d-flex flex-wrap gap-3">
<a class="btn btn-danger" href="reboot.cgi">Reboot camera</a>
<a class="btn btn-primary" href="config-network.cgi">See network settings</a>
</span>
</div>
<% fi %>

<h2><%= $page_title %></h2>

<% alert_read %>
