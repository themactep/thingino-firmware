#!/usr/bin/env lua

-- Simple development server for thingino Lua web interface
-- Usage: lua dev-server.lua [port]

local PORT = tonumber(arg and arg[1]) or 8080
local WEBROOT = "../files/www"

-- Check if we're in the right directory
local function check_webroot()
    local file = io.open(WEBROOT .. "/lua/main.lua", "r")
    if file then
        file:close()
        return true
    end
    return false
end

if not check_webroot() then
    print("Error: Cannot find " .. WEBROOT .. "/lua/main.lua")
    print("Make sure you're running this from the thingino root directory")
    os.exit(1)
end

-- Mock uhttpd global for development
uhttpd = {
    send = function(data)
        io.write(data)
    end
}

-- Mock session storage for development
local dev_sessions = {}

-- Development utilities
local dev_utils = {
    -- Mock file system functions
    file_exists = function(path)
        local file = io.open(path, "r")
        if file then
            file:close()
            return true
        end
        return false
    end,

    -- Mock system info
    get_hostname = function()
        return "thingino-dev"
    end,

    get_system_info = function()
        return {
            uptime = "2 days, 3 hours",
            memory_usage = {percentage = 45, used = "23MB", total = "64MB"},
            load_average = {one_min = "0.15", five_min = "0.12", fifteen_min = "0.08"}
        }
    end,

    get_camera_status = function()
        return {
            streaming = true,
            resolution = "1920x1080",
            fps = 25,
            night_mode = false
        }
    end
}

-- Simple HTTP server using Python (most reliable cross-platform option)
local function start_python_server()
    print("Starting Thingino Development Server...")
    print("Web root: " .. WEBROOT)
    print("URL: http://localhost:" .. PORT .. "/lua/login")
    print("Press Ctrl+C to stop")
    print("")

    -- Create a simple Python CGI server
    local python_script = string.format([[
import http.server
import socketserver
import os
import subprocess
import urllib.parse
import sys

PORT = %d
WEBROOT = "%s"

class ThingioHandler(http.server.SimpleHTTPRequestHandler):
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
            # Set up environment
            env = os.environ.copy()
            env['REQUEST_URI'] = self.path
            env['REQUEST_METHOD'] = self.command
            env['REMOTE_ADDR'] = self.client_address[0]
            env['HTTP_HOST'] = self.headers.get('Host', 'localhost')

            # Run Lua script
            result = subprocess.run([
                'lua', '-e', '''
                package.path = "%s/lua/lib/?.lua;" .. package.path
                dofile("%s/lua/main.lua")
                local env = {
                    REQUEST_URI = os.getenv("REQUEST_URI"),
                    REQUEST_METHOD = os.getenv("REQUEST_METHOD"),
                    REMOTE_ADDR = os.getenv("REMOTE_ADDR"),
                    HTTP_HOST = os.getenv("HTTP_HOST")
                }
                handle_request(env)
                '''
            ], env=env, capture_output=True, text=True)

            if result.returncode == 0:
                output = result.stdout
                if output.startswith('Status:'):
                    # Parse CGI response
                    lines = output.split('\\n')
                    status_line = lines[0]
                    status_code = int(status_line.split()[1])

                    self.send_response(status_code)

                    # Parse headers
                    i = 1
                    while i < len(lines) and lines[i].strip():
                        if ':' in lines[i]:
                            key, value = lines[i].split(':', 1)
                            self.send_header(key.strip(), value.strip())
                        i += 1

                    self.end_headers()

                    # Send body
                    body = '\\n'.join(lines[i+1:])
                    self.wfile.write(body.encode())
                else:
                    self.send_response(200)
                    self.send_header('Content-Type', 'text/html')
                    self.end_headers()
                    self.wfile.write(output.encode())
            else:
                error_html = f'''
                <html><body>
                <h1>Lua Error</h1>
                <pre>{result.stderr}</pre>
                </body></html>
                '''
                self.send_response(500)
                self.send_header('Content-Type', 'text/html')
                self.end_headers()
                self.wfile.write(error_html.encode())

        except Exception as e:
            error_html = f'<html><body><h1>Server Error</h1><pre>{str(e)}</pre></body></html>'
            self.send_response(500)
            self.send_header('Content-Type', 'text/html')
            self.end_headers()
            self.wfile.write(error_html.encode())

os.chdir(os.path.dirname(os.path.abspath(__file__)))
with socketserver.TCPServer(("", PORT), ThingioHandler) as httpd:
    print(f"Development server running on http://localhost:{PORT}")
    httpd.serve_forever()
]], PORT, WEBROOT, WEBROOT, WEBROOT)

    -- Write and execute Python script
    local script_file = io.open("/tmp/thingino_dev_server.py", "w")
    if script_file then
        script_file:write(python_script)
        script_file:close()
        os.execute("python3 /tmp/thingino_dev_server.py")
    else
        print("Error: Cannot create temporary Python script")
    end
end

-- Start the development server
start_python_server()
