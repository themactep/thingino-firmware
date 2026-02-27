#!/usr/bin/env lua

-- Enhanced Lua Web Server for Thingino Development
-- Serves real Lua scripts with full functionality

local socket = require("socket")
local url = require("socket.url")

local PORT = tonumber(arg and arg[1]) or 8085
local WEBROOT = "../files/www"

print("🚀 Thingino Lua Web Server")
print("📁 Web root: " .. WEBROOT)
print("🌐 URL: http://localhost:" .. PORT)
print("📝 Serving real Lua scripts with full functionality")
print("⏹️  Press Ctrl+C to stop")
print()

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
    print("❌ Error: Cannot find " .. WEBROOT .. "/lua/main.lua")
    print("💡 Make sure you're running this from the thingino root directory")
    os.exit(1)
end

-- HTTP response helper
local function send_response(client, status, headers, body)
    local response = "HTTP/1.1 " .. status .. "\r\n"
    
    headers = headers or {}
    headers["Server"] = "Thingino Lua Web Server"
    headers["Connection"] = "close"
    
    if not headers["Content-Type"] then
        headers["Content-Type"] = "text/html; charset=utf-8"
    end
    
    if body then
        headers["Content-Length"] = tostring(#body)
    end
    
    for key, value in pairs(headers) do
        response = response .. key .. ": " .. value .. "\r\n"
    end
    response = response .. "\r\n"
    
    if body then
        response = response .. body
    end
    
    client:send(response)
end

-- Parse HTTP request with headers and POST data
local function parse_request(client)
    local request_line = client:receive("*l")
    if not request_line then return nil end
    
    local method, path, version = request_line:match("(%S+)%s+(%S+)%s+(%S+)")
    
    local headers = {}
    local content_length = 0
    
    while true do
        local header_line = client:receive("*l")
        if not header_line or header_line == "" then
            break
        end
        
        local key, value = header_line:match("([^:]+):%s*(.+)")
        if key and value then
            headers[key:lower()] = value
            if key:lower() == "content-length" then
                content_length = tonumber(value) or 0
            end
        end
    end
    
    local post_data = ""
    if method == "POST" and content_length > 0 then
        post_data = client:receive(content_length) or ""
    end
    
    return {
        method = method,
        path = path,
        version = version,
        headers = headers,
        post_data = post_data
    }
end

-- Serve static files
local function serve_static(client, path)
    local file_path = WEBROOT .. path
    local file = io.open(file_path, "rb")
    
    if not file then
        send_response(client, "404 Not Found", {}, "<h1>404 Not Found</h1>")
        return
    end
    
    local content = file:read("*all")
    file:close()
    
    local content_type = "text/plain"
    if path:match("%.html$") then
        content_type = "text/html; charset=utf-8"
    elseif path:match("%.css$") then
        content_type = "text/css"
    elseif path:match("%.js$") then
        content_type = "application/javascript"
    elseif path:match("%.png$") then
        content_type = "image/png"
    elseif path:match("%.jpg$") or path:match("%.jpeg$") then
        content_type = "image/jpeg"
    end
    
    send_response(client, "200 OK", {["Content-Type"] = content_type}, content)
end

-- Serve Lua scripts with full functionality
local function serve_lua(client, path, method, query, post_data)
    package.path = WEBROOT .. "/lua/lib/?.lua;" .. package.path
    
    local output = {}
    local original_write = io.write
    io.write = function(data)
        table.insert(output, data)
    end
    
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
    
    local success, error_msg = pcall(function()
        -- Mock uhttpd global first
        uhttpd = {
            send = function(data)
                io.write(data)
            end
        }

        -- Load and override utils for development
        local original_utils = require("utils")
        local dev_utils = {}
        for k, v in pairs(original_utils) do
            dev_utils[k] = v
        end
        
        dev_utils.file_exists = mock_file_exists
        dev_utils.get_hostname = function() return "thingino-dev" end
        dev_utils.get_system_info = function()
            return {
                uptime = "2 days, 3 hours",
                memory_usage = {percentage = 45, used = "23MB", total = "64MB"},
                load_average = {one_min = "0.15", five_min = "0.12", fifteen_min = "0.08"}
            }
        end
        dev_utils.get_camera_status = function()
            return {
                streaming = true,
                resolution = "1920x1080",
                fps = 25,
                night_mode = false
            }
        end
        dev_utils.get_system_info_detailed = function()
            return {
                cpu_model = "Ingenic T31",
                cpu_cores = "1",
                architecture = "MIPS",
                kernel = "Linux 3.10.14",
                firmware_version = "Thingino v1.0.0",
                memory_total = "64MB",
                memory_used = "23MB",
                memory_percentage = "45",
                disk_usage = "25",
                cpu_temp = "42",
                uptime = "2 days, 3 hours",
                load_average = {one_min = "0.15", five_min = "0.12", fifteen_min = "0.08"}
            }
        end
        dev_utils.get_network_info = function()
            return {
                primary_interface = "wlan0",
                ip_address = "192.168.1.109",
                netmask = "255.255.255.0",
                gateway = "192.168.1.1",
                mac_address = "aa:bb:cc:dd:ee:ff",
                hostname = "thingino-camera",
                dns_primary = "8.8.8.8",
                dns_secondary = "8.8.4.4",
                dhcp_status = "Enabled",
                wlan0_ip = "192.168.1.109",
                wlan0_mac = "aa:bb:cc:dd:ee:ff",
                eth0_mac = "aa:bb:cc:dd:ee:00"
            }
        end
        dev_utils.get_camera_info = function()
            return {
                sensor_model = "IMX307",
                max_resolution = "1920x1080",
                isp_version = "T31",
                video_encoder = "H.264",
                night_vision_status = "Available",
                stream_status = "Online",
                current_resolution = "1920x1080",
                current_fps = "25",
                current_bitrate = "2048",
                current_codec = "H.264",
                sensor_details = "Sensor: IMX307\\nInterface: MIPI\\nBit depth: 12-bit",
                streaming_config = "Resolution: 1920x1080\\nFPS: 25\\nBitrate: 2048 kbps\\nCodec: H.264"
            }
        end
        dev_utils.get_logs_info = function()
            return {
                system = "Jan 15 10:30:15 thingino kernel: [    0.000000] Linux version 3.10.14\\nJan 15 10:30:15 thingino kernel: [    0.000000] CPU: Ingenic T31\\nJan 15 10:30:16 thingino init: Starting system services\\nJan 15 10:30:17 thingino prudynt: Video streaming started",
                kernel = "Jan 15 10:30:15 thingino kernel: [    0.000000] Linux version 3.10.14\\nJan 15 10:30:15 thingino kernel: [    0.000000] CPU: Ingenic T31\\nJan 15 10:30:15 thingino kernel: [    0.000000] Memory: 64MB",
                camera = "Jan 15 10:30:17 thingino prudynt: Video streaming started\\nJan 15 10:30:17 thingino prudynt: Sensor IMX307 detected\\nJan 15 10:30:18 thingino prudynt: Stream resolution: 1920x1080@25fps",
                network = "Jan 15 10:30:16 thingino wpa_supplicant: Connected to WiFi network\\nJan 15 10:30:16 thingino dhcpcd: DHCP lease obtained: 192.168.1.109\\nJan 15 10:30:16 thingino ntpd: Time synchronized",
                security = "Jan 15 10:30:15 thingino sshd: SSH daemon started\\nJan 15 10:30:16 thingino login: root login from 192.168.1.100\\nJan 15 10:30:20 thingino uhttpd: Web interface accessed from 192.168.1.100"
            }
        end
        dev_utils.send_file = function(file_path, content_type)
            if file_path == "/tmp/snapshot.jpg" then
                uhttpd.send("Status: 200 OK\r\n")
                uhttpd.send("Content-Type: " .. content_type .. "\r\n\r\n")
                uhttpd.send("FAKE_JPEG_DATA_FOR_DEVELOPMENT")
            else
                uhttpd.send("Status: 404 Not Found\r\n\r\n")
                uhttpd.send("File not found in development mode")
            end
        end

        -- Process template includes for development
        dev_utils.process_includes = function(content)
            -- Process {{include:filename}} directives
            local function include_replacer(include_name)
                local include_path = WEBROOT .. "/lua/templates/common/" .. include_name .. ".html"
                local file = io.open(include_path, "r")

                if not file then
                    return "<!-- Include not found: " .. include_name .. " at " .. include_path .. " -->"
                end

                local include_content = file:read("*all")
                file:close()

                return include_content
            end

            -- Replace {{include:filename}} with file contents
            content = content:gsub("{{%s*include:([%w_%-]+)%s*}}", include_replacer)

            return content
        end

        dev_utils.load_template = function(template_name, vars)
            local template_path = WEBROOT .. "/lua/templates/" .. template_name .. ".html"
            local file = io.open(template_path, "r")

            if not file then
                return "<h1>Template not found: " .. template_name .. " at " .. template_path .. "</h1>"
            end

            local content = file:read("*all")
            file:close()

            -- Process includes first (before variable replacement)
            content = dev_utils.process_includes(content)

            if vars then
                for key, value in pairs(vars) do
                    local pattern = "{{%s*" .. key .. "%s*}}"
                    content = content:gsub(pattern, tostring(value))
                end
            end

            return content
        end

        package.loaded["utils"] = dev_utils
        
        -- Mock session for development
        local original_session = require("session")
        local dev_session = {}
        for k, v in pairs(original_session) do
            dev_session[k] = v
        end
        
        dev_session.get = function(env)
            return {
                id = "dev_session_123",
                user = "root",
                created = os.time(),
                last_activity = os.time(),
                remote_addr = env.REMOTE_ADDR or "127.0.0.1"
            }
        end
        
        dev_session.create = function(env, user)
            return "dev_session_123"
        end
        
        package.loaded["session"] = dev_session
        
        -- Load main handler
        dofile(WEBROOT .. "/lua/main.lua")
        
        local env = {
            REQUEST_URI = path,
            REQUEST_METHOD = method or "GET",
            QUERY_STRING = query or "",
            REMOTE_ADDR = "127.0.0.1",
            HTTP_HOST = "localhost:" .. PORT,
            CONTENT_LENGTH = tostring(#(post_data or "")),
            CONTENT_TYPE = "application/x-www-form-urlencoded"
        }
        
        -- Mock stdin for POST data
        if post_data and post_data ~= "" then
            local original_read = io.read
            local post_index = 1
            io.read = function(format)
                if format == "*a" or format == "*all" then
                    local result = post_data:sub(post_index)
                    post_index = #post_data + 1
                    return result
                elseif format == "*l" or format == "*line" then
                    local newline_pos = post_data:find("\n", post_index)
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
            
            handle_request(env)
            io.read = original_read
        else
            handle_request(env)
        end
    end)
    
    io.write = original_write
    
    if success then
        local response_data = table.concat(output)
        if response_data:match("Status:") then
            local headers_end = response_data:find("\r\n\r\n") or response_data:find("\n\n")
            if headers_end then
                local header_part = response_data:sub(1, headers_end)
                local body_part = response_data:sub(headers_end + 4)
                
                local status = "200 OK"
                local headers = {}
                
                for line in header_part:gmatch("[^\r\n]+") do
                    if line:match("^Status:") then
                        status = line:match("^Status:%s*(.+)")
                    else
                        local key, value = line:match("([^:]+):%s*(.+)")
                        if key and value then
                            headers[key] = value
                        end
                    end
                end
                
                send_response(client, status, headers, body_part)
            else
                send_response(client, "200 OK", {}, response_data)
            end
        else
            send_response(client, "200 OK", {}, response_data)
        end
    else
        local error_html = string.format([[
<!DOCTYPE html>
<html>
<head><title>Lua Error</title></head>
<body style="font-family: monospace; margin: 2rem; background: #1a1a1a; color: #fff;">
<h1>Lua Error</h1>
<pre style="background: #4a1a1a; border: 1px solid #ff6b6b; padding: 1rem; border-radius: 4px;">%s</pre>
</body>
</html>
]], error_msg or "Unknown error")
        send_response(client, "500 Internal Server Error", {}, error_html)
    end
end

-- Main server loop
local function start_server()
    local server = socket.tcp()
    server:bind("127.0.0.1", PORT)
    server:listen(32)

    while true do
        local client = server:accept()
        if client then
            client:settimeout(10)

            local request = parse_request(client)
            if request then
                local path = request.path
                local query = path:match("%?(.+)") or ""
                path = path:match("([^%?]+)")

                print(string.format("🌐 %s %s", request.method, request.path))
                if request.post_data and request.post_data ~= "" then
                    print("POST data:", request.post_data:sub(1, 100) .. (request.post_data:len() > 100 and "..." or ""))
                end

                if path:match("^/lua/") then
                    serve_lua(client, path, request.method, query, request.post_data)
                elseif path:match("^/static/") then
                    serve_static(client, path)
                elseif path == "/" then
                    send_response(client, "302 Found", {["Location"] = "/lua/dashboard"}, "")
                else
                    serve_static(client, path)
                end
            end

            client:close()
        end
    end
end

-- Check dependencies
local ok, err = pcall(require, "socket")
if not ok then
    print("❌ Error: lua-socket not found. Install with:")
    print("  sudo apt-get install lua-socket")
    os.exit(1)
end

print("✅ All dependencies found")
start_server()
