#!/usr/bin/env python3

"""
Simple Lua CGI Server for Thingino Development
Executes real Lua scripts and serves the results
"""

import http.server
import socketserver
import subprocess
import os
import urllib.parse
from pathlib import Path

PORT = 8089
WEBROOT = "../files/www"

class LuaCGIHandler(http.server.SimpleHTTPRequestHandler):
    def do_GET(self):
        self.handle_request("GET")
    
    def do_POST(self):
        self.handle_request("POST")
    
    def handle_request(self, method):
        # Parse URL
        parsed_url = urllib.parse.urlparse(self.path)
        path = parsed_url.path
        query = parsed_url.query
        
        print(f"{method} {self.path}")
        if query:
            print(f"  Query: '{query}'")
        
        if path.startswith('/lua/'):
            self.serve_lua(path, method, query)
        elif path.startswith('/static/'):
            self.serve_static(path)
        elif path == '/':
            self.send_response(302)
            self.send_header('Location', '/lua/dashboard')
            self.end_headers()
        else:
            self.serve_static(path)
    
    def serve_static(self, path):
        """Serve static files"""
        file_path = os.path.join(WEBROOT, path.lstrip('/'))
        
        if os.path.exists(file_path) and os.path.isfile(file_path):
            self.send_response(200)
            
            # Set content type
            if path.endswith('.css'):
                self.send_header('Content-Type', 'text/css')
            elif path.endswith('.js'):
                self.send_header('Content-Type', 'application/javascript')
            elif path.endswith('.html'):
                self.send_header('Content-Type', 'text/html; charset=utf-8')
            elif path.endswith(('.png', '.jpg', '.jpeg')):
                self.send_header('Content-Type', 'image/' + path.split('.')[-1])
            else:
                self.send_header('Content-Type', 'text/plain')
            
            self.end_headers()
            
            with open(file_path, 'rb') as f:
                self.wfile.write(f.read())
        else:
            self.send_response(404)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(b'<h1>404 Not Found</h1>')
    
    def serve_lua(self, path, method, query):
        """Execute Lua script and serve result"""
        try:
            # Read POST data if present
            post_data = ""
            if method == "POST":
                content_length = int(self.headers.get('Content-Length', 0))
                if content_length > 0:
                    post_data = self.rfile.read(content_length).decode('utf-8')
            
            # Create Lua script to execute the request
            lua_script = f'''
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

-- Load and override utils for development
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
        uhttpd.send("Status: 200 OK\\r\\n")
        uhttpd.send("Content-Type: " .. content_type .. "\\r\\n\\r\\n")
        uhttpd.send("FAKE_JPEG_DATA_FOR_DEVELOPMENT")
    else
        uhttpd.send("Status: 404 Not Found\\r\\n\\r\\n")
        uhttpd.send("File not found in development mode")
    end
end

dev_utils.load_template = function(template_name, vars)
    local template_path = "{WEBROOT}/lua/templates/" .. template_name .. ".html"
    local file = io.open(template_path, "r")

    if not file then
        return "<h1>Template not found: " .. template_name .. " at " .. template_path .. "</h1>"
    end

    local content = file:read("*all")
    file:close()

    if vars then
        for key, value in pairs(vars) do
            local pattern = "{{{{%s*" .. key .. "%s*}}}}"
            content = content:gsub(pattern, tostring(value))
        end
    end

    return content
end

package.loaded["utils"] = dev_utils

-- Mock session for development
local original_session = require("session")
local dev_session = {{}}
for k, v in pairs(original_session) do
    dev_session[k] = v
end

dev_session.get = function(env)
    return {{
        id = "dev_session_123",
        user = "root",
        created = os.time(),
        last_activity = os.time(),
        remote_addr = env.REMOTE_ADDR or "127.0.0.1"
    }}
end

dev_session.create = function(env, user)
    return "dev_session_123"
end

package.loaded["session"] = dev_session

-- Load main handler
dofile("{WEBROOT}/lua/main.lua")

local env = {{
    REQUEST_URI = "{path}{('?' + query) if query else ''}",
    REQUEST_METHOD = "{method}",
    QUERY_STRING = "{query}",
    REMOTE_ADDR = "127.0.0.1",
    HTTP_HOST = "localhost:{PORT}",
    CONTENT_LENGTH = "{len(post_data)}",
    CONTENT_TYPE = "application/x-www-form-urlencoded"
}}



-- Mock stdin for POST data
if "{post_data}" ~= "" then
    local original_read = io.read
    local post_data = "{post_data}"
    local post_index = 1
    io.read = function(format)
        if format == "*a" or format == "*all" then
            local result = post_data:sub(post_index)
            post_index = #post_data + 1
            return result
        elseif format == "*l" or format == "*line" then
            local newline_pos = post_data:find("\\n", post_index)
            if newline_pos then
                local result = post_data:sub(post_index, newline_pos - 1)
                post_index = newline_pos + 1
                return result
            else
                local result = post_data:sub(post_index)
                post_index = #post_data + 1
                return result
            end
        else
            return original_read(format)
        end
    end
end

handle_request(env)
'''
            
            # Execute Lua script
            result = subprocess.run(
                ['lua', '-e', lua_script],
                cwd=os.getcwd(),
                capture_output=True,
                text=True,
                timeout=30
            )
            
            if result.returncode == 0:
                output = result.stdout

                # Parse CGI-style response
                if 'Status:' in output or 'Content-Type:' in output:
                    # Split headers and body
                    if '\r\n\r\n' in output:
                        header_part, body_part = output.split('\r\n\r\n', 1)
                    elif '\n\n' in output:
                        header_part, body_part = output.split('\n\n', 1)
                    else:
                        # No proper header/body separation, treat as plain HTML
                        header_part = ""
                        body_part = output

                    status_code = 200
                    headers = {}

                    # Parse headers
                    for line in header_part.split('\n'):
                        line = line.strip()
                        if line.startswith('Status:'):
                            try:
                                status_code = int(line.split()[1])
                            except (IndexError, ValueError):
                                status_code = 200
                        elif ':' in line and line.strip():
                            key, value = line.split(':', 1)
                            headers[key.strip()] = value.strip()

                    self.send_response(status_code)
                    for key, value in headers.items():
                        self.send_header(key, value)
                    if 'Content-Type' not in headers:
                        self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.end_headers()

                    self.wfile.write(body_part.encode('utf-8'))
                else:
                    # Plain HTML response
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html; charset=utf-8')
                    self.end_headers()
                    self.wfile.write(output.encode('utf-8'))
            else:
                # Lua error
                error_html = f'''
<!DOCTYPE html>
<html>
<head><title>Lua Error</title></head>
<body style="font-family: monospace; margin: 2rem; background: #1a1a1a; color: #fff;">
<h1>Lua Error</h1>
<pre style="background: #4a1a1a; border: 1px solid #ff6b6b; padding: 1rem; border-radius: 4px;">{result.stderr}</pre>
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
<head><title>Server Error</title></head>
<body style="font-family: monospace; margin: 2rem; background: #1a1a1a; color: #fff;">
<h1>Server Error</h1>
<pre style="background: #4a1a1a; border: 1px solid #ff6b6b; padding: 1rem; border-radius: 4px;">{str(e)}</pre>
</body>
</html>
'''
            self.send_response(500)
            self.send_header('Content-Type', 'text/html; charset=utf-8')
            self.end_headers()
            self.wfile.write(error_html.encode('utf-8'))

if __name__ == "__main__":
    # Check if webroot exists
    if not os.path.exists(WEBROOT):
        print(f"❌ Error: Cannot find {WEBROOT}")
        print("💡 Make sure you're running this from the thingino root directory")
        exit(1)
    
    print("🚀 Simple Lua CGI Server for Thingino")
    print(f"📁 Web root: {WEBROOT}")
    print(f"🌐 URL: http://localhost:{PORT}")
    print("📝 Executing real Lua scripts via CGI")
    print("⏹️  Press Ctrl+C to stop")
    print()
    
    with socketserver.TCPServer(("", PORT), LuaCGIHandler) as httpd:
        try:
            httpd.serve_forever()
        except KeyboardInterrupt:
            print("\\n👋 Server stopped")
