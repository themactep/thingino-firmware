# Thingino uHTTPd Web Server Package

This package provides a uHTTPd web server with optional HTTPS support for thingino cameras.

## Features

- **Native HTTPS Support**: Secure HTTP connections using mbedTLS or wolfSSL
- **Session-Based Authentication**: Secure login system with session management
- **RESTful API**: JSON endpoints for automation and AJAX requests
- **Modern Security**: Rate limiting, secure cookies, HTTPS enforcement
- **Lightweight**: Optimized for embedded camera systems

## Configuration Options

### BR2_PACKAGE_THINGINO_UHTTPD_TLS
Enables TLS/HTTPS support. Enabled by default. Provides:
- HTTPS on port 443 with modern TLS protocols
- SSL/TLS encryption for secure web access
- Automatic HTTP to HTTPS redirection

### BR2_PACKAGE_THINGINO_UHTTPD_HTTP_REDIRECT
Enables automatic redirection from HTTP (port 80) to HTTPS (port 443).

### BR2_PACKAGE_THINGINO_UHTTPD_LUA
Enables Lua scripting support in the uhttpd binary.
Requires `BR2_PACKAGE_LUA`.

### BR2_PACKAGE_THINGINO_UHTTPD_UBUS
Enables ubus support for communication with other system services.
Requires `BR2_PACKAGE_UBUS`.

## Files Installed

- `/usr/bin/uhttpd` — uHTTPd web server binary
- `/etc/init.d/S60uhttpd` — startup script
- `/etc/default/uhttpd` — default configuration
- `/var/www/` — document root

## Service Configuration

- **Port 443**: HTTPS with SSL/TLS encryption (if TLS enabled)
- **Port 80**: HTTP redirect to HTTPS (if redirect enabled)
- **Document root**: `/var/www`

## TLS Certificate Setup

### Auto-generated Certificates (Default)
Self-signed certificates are generated on first boot:
- Certificate: `/etc/ssl/certs/uhttpd.crt`
- Private key: `/etc/ssl/private/uhttpd.key`

### Custom Certificates
```bash
cp your-certificate.crt /etc/ssl/certs/uhttpd.crt
cp your-private-key.key /etc/ssl/private/uhttpd.key
chmod 644 /etc/ssl/certs/uhttpd.crt
chmod 600 /etc/ssl/private/uhttpd.key
/etc/init.d/S60uhttpd restart
```

### Generate New Self-Signed Certificate
```bash
openssl req -x509 -newkey rsa:2048 \
  -keyout /etc/ssl/private/uhttpd.key \
  -out /etc/ssl/certs/uhttpd.crt \
  -days 365 -nodes \
  -subj '/C=US/ST=State/L=City/O=Thingino/CN=camera.local'
```

## Dependencies

- **Core**: libubox, thingino-jct
- **TLS Support**: mbedTLS or wolfSSL with ustream-ssl
- **Optional**: lua (for Lua scripting), ubus (for system integration)

## References

- https://wiki.openwrt.org/doc/howto/http.uhttpd
