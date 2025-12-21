# Thingino Web UI Development Tools

This directory contains development tools and scripts for working with the Thingino Lua web interface.

## Development Servers

### lua-web-server.lua (Recommended)
Enhanced Lua web server that serves real Lua scripts with full functionality.

```bash
cd package/thingino-webui-lua/development
lua lua-web-server.lua [port]
```

**Features:**
- Serves real Lua scripts with uhttpd compatibility
- Session management and authentication
- POST data handling
- Development-friendly error messages
- Default port: 8085

### dev-server.py
Python-based development server with Lua script execution.

```bash
cd package/thingino-webui-lua/development
python3 dev-server.py [port]
```

**Features:**
- Cross-platform compatibility
- Lua script execution via subprocess
- HTTP request handling
- Default port: 8080

### simple-lua-server.py
Lightweight Python server for basic testing.

```bash
cd package/thingino-webui-lua/development
python3 simple-lua-server.py [port]
```

**Features:**
- Minimal setup
- Basic Lua script serving
- Good for quick testing
- Default port: 8090

### dev-server.sh
Shell script wrapper for easy server management.

```bash
cd package/thingino-webui-lua/development
./dev-server.sh
```

## Testing Tools

### generate-test-pages.lua
Generates static HTML pages for testing without running a server.

```bash
cd package/thingino-webui-lua/development
lua generate-test-pages.lua
```

**Features:**
- Creates static HTML files in `test-output/` directory
- Bypasses server complexity for UI testing
- Generates authenticated and non-authenticated pages
- Useful for debugging template issues

## Usage

1. **Choose a development server** based on your needs:
   - Use `lua-web-server.lua` for full Lua functionality
   - Use `dev-server.py` for cross-platform compatibility
   - Use `simple-lua-server.py` for quick testing

2. **Start the server** from the development directory:
   ```bash
   cd package/thingino-webui-lua/development
   lua lua-web-server.lua
   ```

3. **Access the web interface**:
   - Open your browser to `http://localhost:8085/lua/login`
   - Use default credentials: `root` / `admin`

4. **Edit files** in `../files/www/` and refresh your browser to see changes

## Development Workflow

1. **Edit Lua scripts** in `../files/www/lua/`
2. **Edit templates** in `../files/www/lua/templates/`
3. **Edit CSS/JS** in `../files/www/static/`
4. **Refresh browser** to see changes immediately
5. **Check console** for any Lua errors
6. **Test on camera** when ready by rebuilding firmware

## File Structure

```
development/
├── README.md                 # This file
├── lua-web-server.lua       # Enhanced Lua server (recommended)
├── dev-server.py            # Python development server
├── dev-server.sh            # Shell wrapper script
├── simple-lua-server.py     # Lightweight Python server
└── generate-test-pages.lua  # Static page generator
```

## Notes

- All scripts use relative paths (`../files/www/`) to access the web interface files
- The development servers mock camera-specific functions for PC testing
- Session data is stored in memory during development
- Snapshot images use placeholder data when `/tmp/snapshot.jpg` is not available

## Troubleshooting

### Server Won't Start
- Check that Lua is installed: `lua -v`
- Verify Python 3 is available: `python3 --version`
- Ensure you're in the correct directory

### Lua Errors
- Check the console output for detailed error messages
- Verify file paths are correct
- Test individual Lua modules: `lua -l utils`

### Template Issues
- Use `generate-test-pages.lua` to create static files for debugging
- Check template syntax and variable substitution
- Verify template file paths
