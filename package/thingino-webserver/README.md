# Thingino Web Server Abstraction

This package provides a virtual package abstraction for selecting a web server for thingino-webui.

## Supported Web Servers

The following web servers are supported:

### BusyBox httpd (default)
- Minimal footprint
- Suitable for embedded systems
- No SSL support natively (use thingino-httpd-ssl for HTTPS)
- Simple configuration via /etc/httpd.conf

### uhttpd
- Modern HTTP server from OpenWrt
- Optional TLS/HTTPS support with mbedTLS or wolfSSL
- Optional Lua scripting support
- Session-based authentication
- Auto HTTP to HTTPS redirection

### nginx
- Full-featured HTTP server and reverse proxy
- Requires more resources
- Extensive module support
- Requires fcgiwrap for CGI script execution

## Usage

When building thingino firmware, select one of the web server options from the configuration menu:

```
Thingino Firmware → System Packages → Web Server
```

The thingino-webui package will automatically depend on whichever web server you choose and install the appropriate configuration files.

## Configuration

The webui package detects which web server is selected and installs the appropriate configuration:

- **BusyBox httpd**: Installs `/etc/httpd.conf` and `/etc/init.d/S90httpd`
- **uhttpd**: Uses uhttpd's own configuration in `/etc/uhttpd/`
- **nginx**: Installs `/etc/nginx/nginx.conf` (requires fcgiwrap for CGI)

## Adding HTTPS Support

### With BusyBox httpd
Enable the `thingino-httpd-ssl` package which provides an mbedTLS wrapper for BusyBox httpd.

### With uhttpd
Enable TLS support in the uhttpd configuration menu and select your preferred TLS library (mbedTLS or wolfSSL).

### With nginx
Configure nginx with SSL modules and provide appropriate SSL certificates.
