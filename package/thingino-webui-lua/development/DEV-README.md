# Thingino Lua Web Interface Development

This directory contains a development server for testing the Thingino Lua web interface locally without needing to rebuild and flash firmware.

## Quick Start

```bash
# Start the development server (default port 8080)
./dev-server.sh

# Or specify a custom port
./dev-server.sh 3000
```

Then open your browser to: **http://localhost:8080/lua/login**

**Default credentials:** `root` / (empty password)

## What's Included

### 🎯 **Configuration Pages Created**
- **Camera Configuration** (`/lua/config-camera`)
  - Video stream settings (resolution, FPS, bitrate, codec)
  - Image settings (flip horizontal/vertical)
  - Night vision controls (auto/on/off, IR GPIO settings)
  - Live preview with refresh
  - Quick actions (snapshot, restart streaming, toggle night vision)

- **System Configuration** (`/lua/config-system`)
  - Date & time settings (timezone, NTP server)
  - Remote access (SSH/Telnet enable/disable)
  - Logging configuration
  - Web interface settings (theme, password change)
  - Danger zone (factory reset, reboot)

### 🎨 **Enhanced Styling**
- Updated `thingino.css` with modern responsive design
- Dark theme with proper color variables
- Mobile-friendly responsive layout
- Form styling and validation
- Status indicators and alerts

### 🔧 **Fixed Issues**
- **Snapshot API** now works correctly (serves `/tmp/snapshot.jpg`)
- **Authentication** system working with session management
- **Template rendering** with proper variable substitution
- **Configuration management** with backup/restore functionality

## Development Features

### 🚀 **Development Server**
- **Live reload** - edit files and refresh browser to see changes
- **Mock data** - provides realistic system/camera status for testing
- **Error display** - shows Lua errors with stack traces in browser
- **Static files** - serves CSS, JS, and other assets correctly

### 🛠 **Mock Functions**
The development server provides mock implementations for:
- `utils.get_hostname()` → "thingino-dev"
- `utils.get_system_info()` → Mock system stats
- `utils.get_camera_status()` → Mock camera status
- `utils.file_exists("/tmp/snapshot.jpg")` → Always true
- `utils.send_file()` → Placeholder for snapshot images

## File Structure

```
package/thingino-webui-lua/files/www/
├── lua/
│   ├── main.lua              # Main request handler
│   ├── lib/
│   │   ├── auth.lua          # Authentication functions
│   │   ├── session.lua       # Session management
│   │   ├── utils.lua         # Utility functions
│   │   └── config.lua        # Configuration management
│   └── templates/
│       ├── login.html        # Login page
│       ├── dashboard.html    # Main dashboard
│       ├── info.html         # System information
│       ├── preview.html      # Camera preview
│       └── config/
│           ├── network.html  # Network configuration
│           ├── camera.html   # Camera configuration ✨ NEW
│           └── system.html   # System configuration ✨ NEW
└── static/
    └── css/
        └── thingino.css      # Enhanced styling ✨ UPDATED
```

## Available URLs

| URL | Description |
|-----|-------------|
| `/lua/login` | Login page |
| `/lua/dashboard` | Main dashboard |
| `/lua/info` | System information |
| `/lua/preview` | Camera preview |
| `/lua/config-network` | Network settings |
| `/lua/config-camera` | Camera settings ✨ NEW |
| `/lua/config-system` | System settings ✨ NEW |
| `/lua/api/camera/snapshot` | Camera snapshot (fixed) |
| `/lua/api/status` | System status JSON |
| `/lua/logout` | Logout |

## Development Workflow

1. **Edit files** in `package/thingino-webui-lua/files/www/`
2. **Refresh browser** to see changes immediately
3. **Check console** for any Lua errors
4. **Test on camera** when ready by rebuilding firmware

## Dependencies

- **Python 3** (for development server)
- **Lua 5.4** (for executing Lua scripts)

## Next Steps

- [ ] Add more API endpoints (camera controls, system management)
- [ ] Implement WebSocket support for real-time updates
- [ ] Add file upload/download functionality
- [ ] Create more configuration pages (WiFi, services, etc.)
- [ ] Add JavaScript for dynamic UI interactions
- [ ] Implement proper form validation
- [ ] Add backup/restore configuration features

## Testing on Camera

When ready to test on the actual camera:

1. **Build firmware** with `BR2_PACKAGE_THINGINO_WEBUI_LUA=y`
2. **Flash to camera**
3. **Access** via `https://camera-ip/lua/login`

The development server helps you iterate quickly without the build/flash cycle!
