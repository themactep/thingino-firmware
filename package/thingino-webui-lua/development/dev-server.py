#!/usr/bin/env python3

"""
Simple development server for thingino Lua web interface
Usage: python3 dev-server.py [port]
"""

import http.server
import socketserver
import os
import subprocess
import urllib.parse
import sys
import json
from pathlib import Path

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 8080
WEBROOT = "../files/www"

# Check if we're in the right directory
if not Path(WEBROOT + "/lua/main.lua").exists():
    print(f"Error: Cannot find {WEBROOT}/lua/main.lua")
    print("Make sure you're running this from the thingino root directory")
    sys.exit(1)

class ThinginoHandler(http.server.SimpleHTTPRequestHandler):
    def __init__(self, *args, **kwargs):
        super().__init__(*args, directory=WEBROOT, **kwargs)
    
    def do_GET(self):
        if self.path.startswith('/lua/'):
            self.handle_lua_request()
        elif self.path == '/':
            self.send_response(302)
            self.send_header('Location', '/lua/login')
            self.end_headers()
        else:
            super().do_GET()
    
    def do_POST(self):
        if self.path.startswith('/lua/'):
            self.handle_lua_request()
        else:
            self.send_error(404)
    
    def handle_lua_request(self):
        try:
            # Parse URL
            parsed_url = urllib.parse.urlparse(self.path)
            path = parsed_url.path
            query = parsed_url.query
            
            # Read POST data if present
            post_data = ""
            if self.command == 'POST':
                content_length = int(self.headers.get('Content-Length', 0))
                if content_length > 0:
                    post_data = self.rfile.read(content_length).decode('utf-8')
            
            # Create Lua script to handle the request
            lua_script = f'''
-- Set up package path
package.path = "{WEBROOT}/lua/lib/?.lua;" .. package.path

-- Mock uhttpd global
uhttpd = {{
    send = function(data)
        io.write(data)
    end
}}

-- Mock development functions
local function mock_file_exists(path)
    if path == "/tmp/snapshot.jpg" then
        return true
    end
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

-- Override utils functions for development
local original_utils = require("utils")
local dev_utils = {{}}
for k, v in pairs(original_utils) do
    dev_utils[k] = v
end

dev_utils.file_exists = mock_file_exists
dev_utils.get_hostname = function() return "thingino-dev" end
dev_utils.get_system_info = function()
    return {{
        uptime = "2 days, 3 hours",
        memory_usage = {{percentage = 45, used = "23MB", total = "64MB"}},
        load_average = {{one_min = "0.15", five_min = "0.12", fifteen_min = "0.08"}}
    }}
end
dev_utils.get_camera_status = function()
    return {{
        streaming = true,
        resolution = "1920x1080",
        fps = 25,
        night_mode = false
    }}
end
dev_utils.send_file = function(file_path, content_type)
    if file_path == "/tmp/snapshot.jpg" then
        -- Send a placeholder image
        uhttpd.send("Status: 200 OK\\r\\n")
        uhttpd.send("Content-Type: " .. content_type .. "\\r\\n\\r\\n")
        uhttpd.send("FAKE_JPEG_DATA_FOR_DEVELOPMENT")
    else
        uhttpd.send("Status: 404 Not Found\\r\\n\\r\\n")
        uhttpd.send("File not found in development mode")
    end
end

-- Fix template loading for development
dev_utils.load_template = function(template_name, vars)
    local template_path = "lua/templates/" .. template_name .. ".html"
    local file = io.open(template_path, "r")

    if not file then
        return "<h1>Template not found: " .. template_name .. " at " .. template_path .. "</h1>"
    end

    local content = file:read("*all")
    file:close()

    -- Simple template variable replacement
    if vars then
        for key, value in pairs(vars) do
            local pattern = "{{{{%s*" .. key .. "%s*}}}}"
            content = content:gsub(pattern, tostring(value))
        end
    end

    return content
end

-- Replace utils in package.loaded
package.loaded["utils"] = dev_utils

-- Load main handler
dofile("{WEBROOT}/lua/main.lua")

-- Create environment
local env = {{
    REQUEST_URI = "{path}",
    REQUEST_METHOD = "{self.command}",
    QUERY_STRING = "{query}",
    REMOTE_ADDR = "{self.client_address[0]}",
    HTTP_HOST = "{self.headers.get('Host', 'localhost')}",
    CONTENT_TYPE = "{self.headers.get('Content-Type', '')}",
    CONTENT_LENGTH = "{self.headers.get('Content-Length', '0')}"
}}

-- Handle the request
handle_request(env)
'''
            
            # Execute Lua script
            result = subprocess.run([
                'lua', '-e', lua_script
            ], capture_output=True, text=True, cwd=os.getcwd())
            
            if result.returncode == 0:
                output = result.stdout
                if 'Status:' in output:
                    # Parse CGI-style response
                    lines = output.split('\\n')

                    # Find the status line
                    status_code = 200
                    header_start = 0
                    for i, line in enumerate(lines):
                        if line.startswith('Status:'):
                            status_parts = line.split()
                            if len(status_parts) >= 2:
                                try:
                                    status_code = int(status_parts[1])
                                except ValueError:
                                    status_code = 200
                            header_start = i + 1
                            break

                    self.send_response(status_code)

                    # Parse headers
                    i = header_start
                    while i < len(lines) and lines[i].strip():
                        if ':' in lines[i]:
                            key, value = lines[i].split(':', 1)
                            self.send_header(key.strip(), value.strip())
                        i += 1

                    self.end_headers()

                    # Send body (everything after the empty line)
                    body_start = i + 1
                    if body_start < len(lines):
                        body = '\\n'.join(lines[body_start:])
                        self.wfile.write(body.encode('utf-8'))
                else:
                    # Plain response
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.end_headers()
                    self.wfile.write(output.encode('utf-8'))
            else:
                # Lua error
                error_html = f'''
<!DOCTYPE html>
<html>
<head>
    <title>Lua Error - Thingino Development Server</title>
    <style>
        body {{ font-family: monospace; margin: 2rem; background: #1a1a1a; color: #fff; }}
        .error {{ background: #4a1a1a; border: 1px solid #ff6b6b; padding: 1rem; border-radius: 4px; }}
        pre {{ white-space: pre-wrap; }}
    </style>
</head>
<body>
    <h1>Lua Error</h1>
    <div class="error">
        <h3>Error Output:</h3>
        <pre>{result.stderr}</pre>
        <h3>Request Details:</h3>
        <pre>Path: {path}
Method: {self.command}
Query: {query}</pre>
    </div>
</body>
</html>
                '''
                self.send_response(500)
                self.send_header('Content-Type', 'text/html; charset=utf-8')
                self.end_headers()
                self.wfile.write(error_html.encode('utf-8'))
                
        except Exception as e:
            error_html = f'''
<!DOCTYPE html>
<html>
<head>
    <title>Server Error - Thingino Development Server</title>
    <style>
        body {{ font-family: monospace; margin: 2rem; background: #1a1a1a; color: #fff; }}
        .error {{ background: #4a1a1a; border: 1px solid #ff6b6b; padding: 1rem; border-radius: 4px; }}
    </style>
</head>
<body>
    <h1>Server Error</h1>
    <div class="error">
        <pre>{str(e)}</pre>
    </div>
</body>
</html>
            '''
            self.send_response(500)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(error_html.encode('utf-8'))

def main():
    print("🚀 Thingino Development Server")
    print(f"📁 Web root: {WEBROOT}")
    print(f"🌐 URL: http://localhost:{PORT}/lua/login")
    print("📝 Default credentials: root / (empty password)")
    print("⏹️  Press Ctrl+C to stop")
    print()
    
    try:
        with socketserver.TCPServer(("", PORT), ThinginoHandler) as httpd:
            httpd.serve_forever()
    except KeyboardInterrupt:
        print("\\n👋 Development server stopped")

if __name__ == "__main__":
    main()
