# Thingino Web UI - Lua Edition

Modern Lua-based web interface for thingino cameras with session-based authentication, HTTPS support, and responsive design.

## Features

- **Session-based Authentication**: Secure login with session management (no more basic auth)
- **HTTPS First**: TLS encryption with automatic HTTP to HTTPS redirection
- **Modern UI**: Responsive dark theme with mobile support
- **Modular Architecture**: Clean Lua modules for easy maintenance and extension
- **JSON API**: RESTful API endpoints for AJAX requests and automation
- **Security**: Rate limiting, session timeouts, secure cookies
- **Performance**: Efficient Lua execution with uhttpd integration

## Requirements

- **uhttpd** with Lua support enabled
- **Lua 5.4** (modern buildroot default)
- **SSL certificates** (auto-generated during build)

## Installation

1. Enable Lua in buildroot:
   ```
   Target packages → Interpreter languages and scripting → lua
   ```

2. Enable thingino-webui-lua:
   ```
   Thingino Firmware → System Packages → thingino-webui-lua
   ```

3. Build firmware:
   ```bash
   make
   ```

## Usage

### Starting the Web Interface

```bash
# Start the service
/etc/init.d/S60uhttpd-lua start

# Check status
/etc/init.d/S60uhttpd-lua status

# Stop the service
/etc/init.d/S60uhttpd-lua stop
```

### Accessing the Interface

- **HTTPS**: `https://camera-ip:443/` (recommended)
- **HTTP**: `http://camera-ip:80/` (redirects to HTTPS)

### Default Login

- **Username**: `root`
- **Password**: `admin` (temporary test credentials)

**Note**: The package currently includes temporary test credentials (`root`/`admin`) for initial testing. In production, you should remove these and implement proper system password verification.

## Architecture

```
Browser → HTTPS (uhttpd) → Lua Handler → System APIs
```

### Components

- **main.lua**: Main request router and handler
- **lib/session.lua**: Session management and storage
- **lib/auth.lua**: Authentication against system users
- **lib/utils.lua**: Utility functions and HTTP helpers
- **lib/config.lua**: Configuration management
- **templates/**: HTML templates with variable substitution
- **static/**: CSS, JavaScript, and image assets

### URL Structure

- `/lua/login` - Login page
- `/lua/dashboard` - Main dashboard
- `/lua/info` - System information
- `/lua/preview` - Camera preview
- `/lua/config-*` - Configuration pages
- `/lua/api/*` - JSON API endpoints

## Security Features

### Session Management

- **Secure sessions**: Stored in `/run/sessions/` (tmpfs) with 600 permissions
- **Session timeout**: 30 minutes of inactivity
- **Session cleanup**: Automatic removal of expired sessions
- **Secure cookies**: HttpOnly, SameSite=Strict

### Authentication

- **System integration**: Uses `/etc/passwd` and `/etc/shadow`
- **Password verification**: Supports all common hash formats (SHA-512, SHA-256, MD5, DES)
- **Rate limiting**: Max 5 login attempts per 15 minutes per IP
- **Admin detection**: Automatic detection of admin users (UID 0, wheel/sudo groups)

### HTTPS

- **TLS encryption**: All traffic encrypted with mbedtls
- **HTTP redirect**: Automatic redirection from HTTP to HTTPS
- **Secure headers**: Proper security headers in responses

## API Endpoints

### System Status
```
GET /lua/api/status
```
Returns system and camera status information.

### Camera Snapshot
```
GET /lua/api/camera/snapshot
```
Returns a JPEG snapshot from the camera.

### System Reboot
```
POST /lua/api/system/reboot
```
Initiates a system reboot (admin only).

## Configuration

### Session Settings

Edit `/var/www/lua/main.lua`:
```lua
local CONFIG = {
    session_timeout = 1800, -- 30 minutes
    debug = false
}
```

### SSL Certificates

Certificates are auto-generated during build. To replace:
```bash
openssl req -x509 -newkey rsa:2048 \
  -keyout /etc/ssl/private/uhttpd.key \
  -out /etc/ssl/certs/uhttpd.crt \
  -days 365 -nodes \
  -subj '/C=US/ST=State/L=City/O=Thingino/CN=camera.local'
```

## Development

### Development Tools

The `development/` directory contains tools for local development and testing:

- **lua-web-server.lua**: Enhanced Lua server with full functionality (recommended)
- **dev-server.py**: Python-based development server
- **simple-lua-server.py**: Lightweight server for quick testing
- **generate-test-pages.lua**: Static page generator for debugging
- **dev-server.sh**: Shell wrapper script

See `development/README.md` for detailed usage instructions.

### Quick Start

```bash
cd package/thingino-webui-lua/development
lua lua-web-server.lua
# Open http://localhost:8085/lua/login
```

### Adding New Pages

1. Create template in `/var/www/lua/templates/`
2. Add route handler in `main.lua`
3. Implement page logic

### Adding API Endpoints

1. Add route in `handle_api_request()` function
2. Implement endpoint function
3. Return JSON response using `utils.send_json()`

### Template System

Simple variable substitution:
```html
<h1>Welcome, {{user}}!</h1>
<p>Current time: {{current_time}}</p>
```

Variables are replaced in `utils.load_template()`.

## Troubleshooting

### Service Won't Start

Check requirements:
```bash
# Verify uhttpd has Lua support
ldd /usr/bin/uhttpd | grep lua

# Check Lua installation
lua -v

# Verify SSL certificates
ls -la /etc/ssl/certs/uhttpd.crt /etc/ssl/private/uhttpd.key
```

### POST Data Issues

This version of uhttpd has a quirk where `uhttpd.recv()` returns the byte count instead of the actual POST data. The package includes a workaround that reads POST data from stdin using `io.read()`. If you encounter login issues, this is likely the cause.

### Login Issues

Check authentication:
```bash
# Verify user exists
grep "^root:" /etc/passwd

# Check shadow file
grep "^root:" /etc/shadow
```

### Debug Mode

Enable debug logging in `main.lua`:
```lua
local CONFIG = {
    debug = true
}
```

View logs:
```bash
tail -f /tmp/webui-lua.log
```

## Migration from Haserl

The Lua web interface replaces the legacy haserl-based interface with:

- **Better security**: Session-based auth vs basic auth
- **Modern UI**: Responsive design vs static HTML
- **Better performance**: Lua vs CGI process spawning
- **Easier maintenance**: Modular code vs monolithic scripts
- **API support**: JSON endpoints for automation

## License

MIT License - See LICENSE file for details.
