# Thingino uHTTPd Web Server Package

This package provides a modern uHTTPd web server with native HTTPS support, Lua scripting capabilities, and session-based authentication for thingino cameras. It serves as the foundation for the modern thingino web interface.

## Features

- **Native HTTPS Support**: Secure HTTP connections using mbedtls library
- **Lua Scripting Engine**: Dynamic server-side content generation and web applications
- **Session-Based Authentication**: Secure login system with session management
- **RESTful API**: JSON endpoints for automation and AJAX requests
- **Modern Security**: Rate limiting, secure cookies, HTTPS enforcement
- **Lightweight**: Optimized for embedded camera systems

## Configuration Options

### BR2_PACKAGE_THINGINO_UHTTPD_TLS
Enables TLS/HTTPS support using mbedtls. This is enabled by default and provides:
- HTTPS on port 443 with modern TLS protocols
- SSL/TLS encryption for secure web access
- Automatic HTTP to HTTPS redirection

### BR2_PACKAGE_THINGINO_UHTTPD_LUA
Enables Lua scripting support for dynamic web applications.
Requires BR2_PACKAGE_LUA to be enabled (Lua 5.4 support).
Essential for thingino-webui-lua package.

### BR2_PACKAGE_THINGINO_UHTTPD_HTTP_REDIRECT
Enables automatic redirection from HTTP (port 80) to HTTPS (port 443).
Recommended for security to ensure all connections are encrypted.

### BR2_PACKAGE_THINGINO_UHTTPD_UBUS
Enables ubus support for communication with other system services.
Requires BR2_PACKAGE_UBUS to be enabled.

## Files Installed

- `/usr/bin/uhttpd` - uHTTPd web server binary with Lua and TLS support
- `/etc/ssl/certs/uhttpd.crt` - SSL certificate (auto-generated)
- `/etc/ssl/private/uhttpd.key` - SSL private key (auto-generated)

**Note**: This package provides only the web server binary. For a complete web interface, install the `thingino-webui-lua` package which includes:
- Startup scripts (`S60uhttpd-lua`)
- Lua web application files
- HTML templates and static assets
- Session management system

## Service Configuration

### uHTTPd Web Server
- **Port 443**: HTTPS with SSL/TLS encryption
- **Port 80**: HTTP redirect to HTTPS (if enabled)
- **Document root**: `/var/www`
- **Lua handler**: `/var/www/lua/main.lua` (if thingino-webui-lua installed)
- **Session storage**: `/tmp/sessions/` (secure permissions)
- **API endpoints**: `/lua/api/*` for JSON responses

### Architecture
```
Client → HTTPS (443) → uhttpd → Lua Handler → Dynamic Response
         HTTP (80)  → redirect to HTTPS
```

## Usage

### With thingino-webui-lua Package
If you have the complete web interface installed:

```bash
# Start the Lua web interface
/etc/init.d/S60uhttpd-lua start

# Stop the service
/etc/init.d/S60uhttpd-lua stop

# Restart the service
/etc/init.d/S60uhttpd-lua restart

# Check status
/etc/init.d/S60uhttpd-lua status
```

### Standalone Usage
For custom Lua applications or static file serving:

```bash
# Start uhttpd with custom configuration
uhttpd -h /var/www -s 443 -p 80 -q \
       -C /etc/ssl/certs/uhttpd.crt \
       -K /etc/ssl/private/uhttpd.key \
       -L /path/to/your/script.lua -l /lua
```

## TLS Certificate Setup

For HTTPS support, you need to provide SSL certificates:

### Auto-generated Certificates (Default)
The package automatically generates self-signed certificates during build:
- Certificate: `/etc/ssl/certs/uhttpd.crt`
- Private key: `/etc/ssl/private/uhttpd.key`

### Custom Certificates
To use your own certificates, replace the auto-generated files:

```bash
# Copy your certificate and key
cp your-certificate.crt /etc/ssl/certs/uhttpd.crt
cp your-private-key.key /etc/ssl/private/uhttpd.key

# Set proper permissions
chmod 644 /etc/ssl/certs/uhttpd.crt
chmod 600 /etc/ssl/private/uhttpd.key

# Restart the service
/etc/init.d/S60uhttpd-lua restart
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

- **Core**: libubox, json-c, mbedtls, ustream-ssl
- **TLS Support**: mbedtls, ustream-ssl-mbedtls
- **Lua Support**: lua (Lua 5.4 for scripting capabilities)
- **Optional**: ubus (for system integration)
- **Recommended**: thingino-webui-lua (complete web interface)

## Integration with thingino-webui-lua

This package provides the web server foundation. For a complete camera web interface, install the `thingino-webui-lua` package which includes:

- **Modern Web Interface**: Responsive dark theme with mobile support
- **Session Authentication**: Secure login system with session management
- **System Monitoring**: Hardware info, network status, system logs
- **Camera Controls**: Live preview, snapshots, camera settings
- **Configuration Pages**: Network, camera, and system configuration
- **RESTful API**: JSON endpoints for automation and AJAX

### Package Relationship
```
thingino-uhttpd (this package)
├── Provides: uhttpd binary with Lua and TLS support
└── Used by: thingino-webui-lua
    ├── Provides: Complete web interface
    ├── Includes: Startup scripts, Lua applications, templates
    └── Requires: thingino-uhttpd for the web server
```

## Migration from Legacy Interface

This package replaces the old busybox httpd + haserl approach with:
- **Better Security**: Session-based auth vs basic auth
- **Modern UI**: Responsive design vs static HTML
- **Better Performance**: Lua vs CGI process spawning
- **Easier Maintenance**: Modular code vs monolithic scripts
- **API Support**: JSON endpoints for automation
