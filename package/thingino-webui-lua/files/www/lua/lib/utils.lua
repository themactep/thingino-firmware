local utils = {}

-- Constants
utils.DATETIME_FORMAT = "%Y-%m-%d %H:%M:%S"

-- Client-side localization - no server-side translation processing needed
function utils.translate_template(content)
    -- For client-side localization, we don't process translation keys on the server
    -- Translation keys like {{t:key}} will be handled by JavaScript on the client
    return content
end

-- HTTP response functions
function utils.send_html(content)
    uhttpd.send("Status: 200 OK\r\n")
    uhttpd.send("Content-Type: text/html; charset=utf-8\r\n")
    uhttpd.send("Cache-Control: no-store\r\n")
    uhttpd.send("Pragma: no-cache\r\n\r\n")
    uhttpd.send(content)
end

function utils.send_json(data, status_code)
    local json_str = utils.table_to_json(data)
    local status = status_code or 200

    uhttpd.send("Status: " .. status .. " OK\r\n")
    uhttpd.send("Content-Type: application/json\r\n")
    uhttpd.send("Cache-Control: no-store\r\n\r\n")
    uhttpd.send(json_str)
end

function utils.send_error(code, message)
    uhttpd.send("Status: " .. code .. " " .. message .. "\r\n")
    uhttpd.send("Content-Type: text/html\r\n\r\n")
    uhttpd.send("<h1>" .. code .. " " .. message .. "</h1>")
end

function utils.send_redirect(location, headers)
    uhttpd.send("Status: 302 Found\r\n")
    uhttpd.send("Location: " .. location .. "\r\n")

    if headers then
        for key, value in pairs(headers) do
            uhttpd.send(key .. ": " .. value .. "\r\n")
        end
    end

    uhttpd.send("Content-Type: text/html\r\n\r\n")
    uhttpd.send("Redirecting...")
end

function utils.send_file(file_path, content_type)
    local file = io.open(file_path, "rb")
    if not file then
        return utils.send_error(404, "File not found")
    end

    local content = file:read("*all")
    file:close()

    uhttpd.send("Status: 200 OK\r\n")
    uhttpd.send("Content-Type: " .. content_type .. "\r\n")
    uhttpd.send("Content-Length: " .. #content .. "\r\n\r\n")
    uhttpd.send(content)
end

-- URL encoding/decoding
function utils.url_decode(str)
    if not str then return "" end
    str = str:gsub("+", " ")
    str = str:gsub("%%(%x%x)", function(h) return string.char(tonumber(h, 16)) end)
    return str
end

function utils.url_encode(str)
    if not str then return "" end
    str = str:gsub("([^%w%-%.%_%~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end)
    return str
end

-- POST data parsing
function utils.read_post_data(env)
    local content_length = tonumber(env.CONTENT_LENGTH or "0")
    local post_data = {}

    if content_length > 0 then
        -- uhttpd.recv() returns byte count, not data in this version
        -- Try reading from stdin instead
        local raw_data = nil

        local success, data = pcall(function()
            return io.read(content_length)
        end)
        if success and data and type(data) == "string" and #data > 0 then
            raw_data = data
        end

        -- Check content type and parse accordingly
        local content_type = env.CONTENT_TYPE or ""
        if raw_data then
            if content_type:match("application/json") then
                -- Parse JSON data
                local json_data = utils.json_decode(raw_data)
                if json_data then
                    post_data = json_data
                end
            else
                -- Parse form data
                for pair in raw_data:gmatch("([^&]+)") do
                    local key, value = pair:match("([^=]+)=([^=]*)")
                    if key and value then
                        post_data[utils.url_decode(key)] = utils.url_decode(value)
                    end
                end
            end
        end
    end

    return post_data
end

-- Multipart form data parsing for file uploads
function utils.parse_multipart_data(env)
    local content_length = tonumber(env.CONTENT_LENGTH or "0")
    local content_type = env.CONTENT_TYPE or ""

    if content_length <= 0 then
        return nil, "No content"
    end

    -- Extract boundary from content type
    local boundary = content_type:match("boundary=([^;]+)")
    if not boundary then
        return nil, "No boundary found in content type"
    end

    -- Read raw data
    local success, raw_data = pcall(function()
        return io.read(content_length)
    end)

    if not success or not raw_data then
        return nil, "Failed to read POST data"
    end

    local files = {}
    local form_data = {}

    -- Split by boundary
    local boundary_pattern = "--" .. boundary
    local parts = {}
    for part in raw_data:gmatch(boundary_pattern .. "(.-)" .. boundary_pattern) do
        table.insert(parts, part)
    end

    for _, part in ipairs(parts) do
        if part and part ~= "" and part ~= "--\r\n" and part ~= "--" then
            -- Parse headers and content
            local header_end = part:find("\r\n\r\n")
            if header_end then
                local headers = part:sub(1, header_end - 1)
                local content = part:sub(header_end + 4)

                -- Remove trailing CRLF
                content = content:gsub("\r\n$", "")

                -- Parse Content-Disposition header
                local name = headers:match('name="([^"]+)"')
                local filename = headers:match('filename="([^"]*)"')

                if name then
                    if filename and filename ~= "" then
                        -- File upload
                        files[name] = {
                            filename = filename,
                            content = content,
                            size = #content
                        }
                    else
                        -- Regular form field
                        form_data[name] = content
                    end
                end
            end
        end
    end

    return {files = files, form_data = form_data}
end

-- Simple JSON decoding (basic implementation)
function utils.json_decode(json_str)
    if not json_str or json_str == "" then
        return {}
    end

    -- Remove whitespace
    json_str = json_str:gsub("^%s*", ""):gsub("%s*$", "")

    -- Simple JSON object parser
    if json_str:sub(1,1) == "{" and json_str:sub(-1,-1) == "}" then
        local result = {}
        local content = json_str:sub(2, -2) -- Remove { }

        -- Very simple parser - just handle basic key:value pairs
        local i = 1
        while i <= #content do
            -- Find key
            local key_start = content:find('"', i)
            if not key_start then break end
            local key_end = content:find('"', key_start + 1)
            if not key_end then break end
            local key = content:sub(key_start + 1, key_end - 1)

            -- Find colon
            local colon = content:find(':', key_end)
            if not colon then break end

            -- Find value
            local value_start = colon + 1
            while content:sub(value_start, value_start) == ' ' do
                value_start = value_start + 1
            end

            local value
            if content:sub(value_start, value_start) == '"' then
                -- String value
                local value_end = content:find('"', value_start + 1)
                if value_end then
                    value = content:sub(value_start + 1, value_end - 1)
                    i = value_end + 1
                else
                    break
                end
            else
                -- Non-string value
                local value_end = content:find(',', value_start)
                if not value_end then
                    value_end = #content + 1
                end
                value = content:sub(value_start, value_end - 1):gsub("^%s*", ""):gsub("%s*$", "")
                i = value_end + 1
            end

            result[key] = value

            -- Skip comma
            while i <= #content and (content:sub(i, i) == ',' or content:sub(i, i) == ' ') do
                i = i + 1
            end
        end

        return result
    end

    return {}
end

-- Template system with include support
function utils.load_template(template_name, vars)
    local template_path = "/var/www/lua/templates/" .. template_name .. ".html"
    utils.log("Attempting to load template: " .. template_path)

    local file = io.open(template_path, "r")

    if not file then
        utils.log("ERROR: Template file not found: " .. template_path)
        return "<h1>Template not found: " .. template_name .. "</h1>"
    end

    local content = file:read("*all")
    file:close()

    utils.log("Template loaded successfully, content length: " .. #content)

    -- Process includes first (before variable replacement)
    content = utils.process_includes(content)

    -- Simple template variable replacement
    if vars then
        utils.log("Starting template variable replacement with " .. tostring(table.getn and table.getn(vars) or "unknown") .. " variables")
        for key, value in pairs(vars) do
            local pattern = "{{%s*" .. key .. "%s*}}"
            local str_value = tostring(value or "")
            -- Escape % characters in replacement string to prevent gsub errors
            local replacement = str_value:gsub("%%", "%%%%")

            -- Count matches before replacement
            local _, match_count = content:gsub(pattern, function() return "" end)

            if match_count > 0 then
                utils.log("Found " .. match_count .. " instances of {{" .. key .. "}}, replacing with: '" .. str_value .. "'")
                content = content:gsub(pattern, replacement)
            end
        end

        -- Check for any remaining unreplaced variables
        local remaining = {}
        for var in content:gmatch("{{[^}]+}}") do
            table.insert(remaining, var)
        end
        if #remaining > 0 then
            utils.log("WARNING: " .. #remaining .. " unreplaced variables: " .. table.concat(remaining, ", "))
        else
            utils.log("All template variables successfully replaced")
        end
    else
        utils.log("No template variables provided for replacement")
    end

    return content
end

-- Process template includes
function utils.process_includes(content)
    -- Process {{include:filename}} directives
    local function include_replacer(include_name)
        local include_path = "/var/www/lua/templates/common/" .. include_name .. ".html"
        local file = io.open(include_path, "r")

        if not file then
            return "<!-- Include not found: " .. include_name .. " -->"
        end

        local include_content = file:read("*all")
        file:close()

        -- Don't apply translations here - let the main template processing handle it
        return include_content
    end

    -- Replace {{include:filename}} with file contents
    content = content:gsub("{{%s*include:([%w_%-]+)%s*}}", include_replacer)

    return content
end

-- System information functions
function utils.get_hostname()
    local file = io.open("/etc/hostname", "r")
    if file then
        local hostname = file:read("*line")
        file:close()
        return hostname or "thingino"
    end
    return "thingino"
end

function utils.get_system_info()
    local info = {}

    -- Uptime
    local uptime_file = io.open("/proc/uptime", "r")
    if uptime_file then
        local uptime_line = uptime_file:read("*line")
        uptime_file:close()
        if uptime_line then
            -- Parse first number from "/proc/uptime" format: "822.77 701.51"
            local uptime_seconds = tonumber(uptime_line:match("([%d%.]+)"))
            if uptime_seconds then
                info.uptime = utils.format_uptime(uptime_seconds)
            end
        end
    end

    -- Memory usage
    local meminfo = utils.read_file("/proc/meminfo")
    if meminfo then
        local total = tonumber(meminfo:match("MemTotal:%s*(%d+)"))
        local free = tonumber(meminfo:match("MemFree:%s*(%d+)"))
        local buffers = tonumber(meminfo:match("Buffers:%s*(%d+)"))
        local cached = tonumber(meminfo:match("Cached:%s*(%d+)"))

        if total and free then
            -- Calculate available memory: MemFree + Buffers + Cached
            local available = free + (buffers or 0) + (cached or 0)
            local used = total - available

            info.memory_usage = {
                total = math.floor(total / 1024),
                used = math.floor(used / 1024),
                available = math.floor(available / 1024),
                percentage = math.floor((used / total) * 100)
            }
        end
    end

    -- Disk usage
    local df_output = utils.execute_command("df -h /")
    if df_output then
        local usage = df_output:match("(%d+)%%")
        if usage then
            info.disk_usage = tonumber(usage)
        end
    end

    return info
end

function utils.get_camera_status()
    local status = {
        streaming = false,
        motion_detection = false,
        night_mode = false
    }

    -- Check if streaming is active
    if utils.file_exists("/tmp/prudynt.pid") then
        status.streaming = true
    end

    -- Check motion detection (placeholder)
    status.motion_detection = utils.file_exists("/tmp/motion_enabled")

    -- Check night mode (placeholder)
    status.night_mode = utils.file_exists("/tmp/night_mode")

    return status
end

function utils.get_websocket_token()
    local token_file = io.open("/run/prudynt_websocket_token", "r")
    if token_file then
        local token = token_file:read("*line")
        token_file:close()
        return token or ""
    end
    return ""
end



-- Get detailed system information for info page
function utils.get_system_info_detailed()
    local info = {}

    -- Uptime
    local uptime_file = io.open("/proc/uptime", "r")
    if uptime_file then
        local uptime_line = uptime_file:read("*line")
        uptime_file:close()
        if uptime_line then
            -- Parse first number from "/proc/uptime" format: "822.77 701.51"
            local uptime_seconds = tonumber(uptime_line:match("([%d%.]+)"))
            if uptime_seconds then
                info.uptime = utils.format_uptime(uptime_seconds)
            end
        end
    end

    -- CPU information
    local cpuinfo = utils.read_file("/proc/cpuinfo")
    if cpuinfo then
        info.cpu_model = cpuinfo:match("model name%s*:%s*([^\n]+)") or cpuinfo:match("Processor%s*:%s*([^\n]+)") or "Unknown"
        local cores = 0
        for _ in cpuinfo:gmatch("processor%s*:") do
            cores = cores + 1
        end
        info.cpu_cores = tostring(cores > 0 and cores or 1)
    end

    -- Kernel version
    local version = utils.read_file("/proc/version")
    if version then
        info.kernel = version:match("Linux version ([^%s]+)") or "Linux"
    end

    -- Memory information
    local meminfo = utils.read_file("/proc/meminfo")
    if meminfo then
        local total = tonumber(meminfo:match("MemTotal:%s*(%d+)"))
        local free = tonumber(meminfo:match("MemFree:%s*(%d+)"))
        local buffers = tonumber(meminfo:match("Buffers:%s*(%d+)"))
        local cached = tonumber(meminfo:match("Cached:%s*(%d+)"))

        if total and free then
            -- Calculate available memory: MemFree + Buffers + Cached
            local available = free + (buffers or 0) + (cached or 0)
            local used = total - available

            info.memory_total = string.format("%.1f MB", total / 1024)
            info.memory_available = string.format("%.1f MB", available / 1024)
            info.memory_used = string.format("%.1f MB", used / 1024)
            info.memory_percentage = math.floor((used / total) * 100)
        end
    end

    -- Load average
    local loadavg = utils.read_file("/proc/loadavg")
    if loadavg then
        local load1, load5, load15 = loadavg:match("([%d%.]+)%s+([%d%.]+)%s+([%d%.]+)")
        info.load_1min = load1 or "0.00"
        info.load_5min = load5 or "0.00"
        info.load_15min = load15 or "0.00"
    end

    return info
end

-- Get network information
function utils.get_network_info()
    local info = {}

    -- Network interfaces
    local interfaces = {}
    local ifconfig_output = utils.execute_command("ip addr show")
    if ifconfig_output then
        for interface_block in ifconfig_output:gmatch("(%d+: [^:]+:.-)\n%d+:") do
            local name = interface_block:match("%d+: ([^:]+):")
            local ip = interface_block:match("inet ([^/]+)")
            local mac = interface_block:match("link/ether ([^%s]+)")
            local state = interface_block:match("state (%w+)")

            if name then
                interfaces[name] = {
                    name = name,
                    ip_address = ip or "N/A",
                    mac_address = mac or "N/A",
                    state = state or "UNKNOWN"
                }
            end
        end
    end
    info.interfaces = interfaces

    -- Routing table
    local route_output = utils.execute_command("ip route show")
    if route_output then
        info.routes = {}
        for line in route_output:gmatch("[^\n]+") do
            table.insert(info.routes, line)
        end
    end

    -- DNS servers
    local resolv_conf = utils.read_file("/etc/resolv.conf")
    if resolv_conf then
        info.dns_servers = {}
        for nameserver in resolv_conf:gmatch("nameserver%s+([^\n]+)") do
            table.insert(info.dns_servers, nameserver)
        end
    end

    return info
end

-- Get camera information
function utils.get_camera_info()
    local info = {}

    -- Sensor information
    local sensor_file = utils.read_file("/proc/jz/sensor/info")
    if sensor_file then
        info.sensor = sensor_file
    else
        info.sensor = "Sensor information not available"
    end

    -- ISP information
    local isp_file = utils.read_file("/proc/jz/isp/info")
    if isp_file then
        info.isp = isp_file
    end

    -- Video encoder information
    local encoder_file = utils.read_file("/proc/jz/encoder/info")
    if encoder_file then
        info.encoder = encoder_file
    end

    -- Check if streaming is active
    info.streaming_active = utils.file_exists("/tmp/prudynt.pid")

    -- Get streaming configuration
    local prudynt_config = utils.read_file("/etc/prudynt.json")
    if prudynt_config then
        info.streaming_config = prudynt_config
    end

    return info
end

-- Get system logs
function utils.get_system_logs()
    local logs = {}

    -- Kernel messages
    local dmesg_output = utils.execute_command("dmesg | tail -50")
    if dmesg_output then
        logs.kernel = dmesg_output
    end

    -- System log
    local syslog_output = utils.execute_command("logread | tail -50")
    if syslog_output then
        logs.system = syslog_output
    end

    -- Boot log
    local boot_log = utils.read_file("/var/log/boot.log")
    if boot_log then
        logs.boot = boot_log
    end

    return logs
end

-- Utility functions
function utils.file_exists(path)
    local file = io.open(path, "r")
    if file then
        file:close()
        return true
    end
    return false
end

function utils.read_file(path)
    local file = io.open(path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        return content
    end
    return nil
end

function utils.execute_command(cmd)
    local handle = io.popen(cmd)
    if handle then
        local result = handle:read("*all")
        handle:close()
        return result
    end
    return nil
end

function utils.command_exists(cmd)
    local result = utils.execute_command("command -v " .. cmd .. " 2>/dev/null")
    return result and result ~= ""
end

-- Restart uhttpd service with robust handling for hanging processes
function utils.restart_uhttpd()
    utils.log("Attempting to restart uhttpd service...")

    -- Use the improved restart script
    local result = utils.execute_command("/etc/init.d/S60uhttpd-lua restart 2>&1")

    if result then
        utils.log("uhttpd restart output: " .. result)
    end

    -- Wait a moment and verify it's running
    os.execute("sleep 3")

    local is_running = utils.execute_command("pgrep uhttpd >/dev/null 2>&1 && echo 'running' || echo 'not running'")

    if is_running and is_running:match("running") then
        utils.log("uhttpd restarted successfully")
        return true
    else
        utils.log("uhttpd restart failed or service not running")
        return false
    end
end

-- Force kill and restart uhttpd (for emergency situations)
function utils.force_restart_uhttpd()
    utils.log("Force restarting uhttpd service...")

    -- Kill all uhttpd processes forcefully
    utils.execute_command("pkill -9 uhttpd 2>/dev/null")
    utils.execute_command("rm -f /var/run/uhttpd-lua.pid")

    -- Wait a moment
    os.execute("sleep 2")

    -- Start the service
    local result = utils.execute_command("/etc/init.d/S60uhttpd-lua start 2>&1")

    if result then
        utils.log("uhttpd force restart output: " .. result)
    end

    -- Verify it's running
    os.execute("sleep 3")
    local is_running = utils.execute_command("pgrep uhttpd >/dev/null 2>&1 && echo 'running' || echo 'not running'")

    return is_running and is_running:match("running")
end

-- SSL Certificate validation functions
function utils.validate_ssl_certificate(cert_content)
    if not cert_content or cert_content == "" then
        return false, "Certificate content is empty"
    end

    -- Check if it looks like a PEM certificate
    if not cert_content:match("%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-") then
        return false, "Invalid certificate format - must be PEM format"
    end

    if not cert_content:match("%-%-%-%-%-END CERTIFICATE%-%-%-%-%-") then
        return false, "Invalid certificate format - missing END marker"
    end

    -- Write to temporary file for validation
    local temp_cert = "/tmp/temp_cert.pem"
    local file = io.open(temp_cert, "w")
    if not file then
        return false, "Failed to create temporary certificate file"
    end
    file:write(cert_content)
    file:close()

    -- Validate using wolfSSL ssl_server2
    local result = utils.execute_command("ssl_server2 crt_file=" .. temp_cert .. " exchanges=0 2>/dev/null")
    os.remove(temp_cert)

    if not result or result == "" or result:match("[Ee]rror") or result:match("[Ff]ailed") then
        return false, "Certificate validation failed - invalid certificate"
    end

    return true, "Certificate is valid"
end

function utils.validate_ssl_private_key(key_content)
    if not key_content or key_content == "" then
        return false, "Private key content is empty"
    end

    -- Check if it looks like a PEM private key
    local has_private_key = key_content:match("%-%-%-%-%-BEGIN PRIVATE KEY%-%-%-%-%-") or
                           key_content:match("%-%-%-%-%-BEGIN RSA PRIVATE KEY%-%-%-%-%-") or
                           key_content:match("%-%-%-%-%-BEGIN EC PRIVATE KEY%-%-%-%-%-")

    if not has_private_key then
        return false, "Invalid private key format - must be PEM format"
    end

    local has_end_marker = key_content:match("%-%-%-%-%-END PRIVATE KEY%-%-%-%-%-") or
                          key_content:match("%-%-%-%-%-END RSA PRIVATE KEY%-%-%-%-%-") or
                          key_content:match("%-%-%-%-%-END EC PRIVATE KEY%-%-%-%-%-")

    if not has_end_marker then
        return false, "Invalid private key format - missing END marker"
    end

    return true, "Private key format is valid"
end

function utils.verify_cert_key_match(cert_content, key_content)
    -- Write temporary files
    local temp_cert = "/tmp/temp_cert_match.pem"
    local temp_key = "/tmp/temp_key_match.pem"

    local cert_file = io.open(temp_cert, "w")
    if not cert_file then
        return false, "Failed to create temporary certificate file"
    end
    cert_file:write(cert_content)
    cert_file:close()

    local key_file = io.open(temp_key, "w")
    if not key_file then
        os.remove(temp_cert)
        return false, "Failed to create temporary key file"
    end
    key_file:write(key_content)
    key_file:close()

    -- Use ssl_server2 to test if cert and key match
    local test_result = utils.execute_command("ssl_server2 crt_file=" .. temp_cert .. " key_file=" .. temp_key .. " exchanges=0 2>&1")

    -- Clean up
    os.remove(temp_cert)
    os.remove(temp_key)

    -- Check if the test was successful (ssl_server2 should start without errors)
    if test_result and not test_result:match("[Ee]rror") and not test_result:match("[Ff]ailed") and not test_result:match("failed") then
        return true, "Certificate and private key match"
    else
        return false, "Certificate and private key do not match"
    end
end

function utils.get_certificate_info(cert_content)
    if not cert_content or cert_content == "" then
        return nil
    end

    local info = {}

    -- Try to use enhanced wolfssl-certgen with JSON output for certificate inspection
    if utils.command_exists("wolfssl-certgen-native") then
        -- Write certificate to temporary file
        local temp_cert = "/tmp/temp_cert_info.pem"
        local file = io.open(temp_cert, "w")
        if file then
            file:write(cert_content)
            file:close()

            -- Use wolfssl-certgen with JSON output to inspect certificate
            local cert_json = utils.execute_command("wolfssl-certgen-native -i " .. temp_cert .. " --json 2>/dev/null")
            os.remove(temp_cert)

            -- Debug: log the raw output
            utils.log("Certificate JSON output: " .. (cert_json or "nil"))

            if cert_json and cert_json ~= "" then
                -- Parse JSON output (extract JSON part after "Inspecting certificate:" line)
                local json_start = cert_json:find("{")
                if json_start then
                    local json_data = cert_json:sub(json_start)
                    utils.log("Extracted JSON: " .. json_data)

                    local success, cert_data = pcall(utils.json_decode, json_data)
                    utils.log("JSON parse success: " .. tostring(success))

                    if success and cert_data then
                        utils.log("Certificate data parsed successfully")
                        -- Extract information from JSON
                        info.common_name = cert_data.common_name or "Unknown"
                        info.issuer = "Self-signed"

                        -- Convert ASN.1 time format to readable format
                        if cert_data.expires_on then
                            local expires_raw = cert_data.expires_on
                            utils.log("Raw expires date: '" .. expires_raw .. "' (length: " .. #expires_raw .. ")")

                            -- Clean the date string and extract just the date part
                            local clean_date = expires_raw:gsub("%s", ""):match("(%d%d%d%d%d%d%d%d%d%d%d%d%d%d)")
                            utils.log("Cleaned date: '" .. (clean_date or "nil") .. "'")

                            if clean_date and #clean_date == 14 then
                                utils.log("Date pattern matched, converting...")
                                local year = clean_date:sub(1, 4)
                                local month = clean_date:sub(5, 6)
                                local day = clean_date:sub(7, 8)
                                local hour = clean_date:sub(9, 10)
                                local min = clean_date:sub(11, 12)
                                local sec = clean_date:sub(13, 14)
                                info.expires = year .. "-" .. month .. "-" .. day .. " " .. hour .. ":" .. min .. ":" .. sec
                                utils.log("Converted date: " .. info.expires)
                            else
                                utils.log("Date pattern did not match, using raw value")
                                info.expires = expires_raw
                            end
                        else
                            utils.log("No expires_on field found")
                            info.expires = "Unknown"
                        end

                        -- Extract issuer common name
                        if cert_data.issuer then
                            local issuer_cn = cert_data.issuer:match("CN=([^/,]+)")
                            if issuer_cn then
                                issuer_cn = issuer_cn:gsub("^%s+", ""):gsub("%s+$", "") -- trim
                                if issuer_cn == info.common_name then
                                    info.issuer = issuer_cn .. " (Self-signed)"
                                else
                                    info.issuer = issuer_cn
                                end
                            else
                                info.issuer = "Thingino (Self-signed)"
                            end
                        else
                            info.issuer = "Self-signed"
                        end

                        utils.log("Final cert info - CN: " .. info.common_name .. ", Expires: " .. info.expires .. ", Issuer: " .. info.issuer)
                        return info
                    else
                        utils.log("JSON parsing failed")
                    end
                else
                    utils.log("No JSON start found in output")
                end
            else
                utils.log("No certificate JSON output received")
            end
        else
            utils.log("Failed to create temporary certificate file")
        end
    else
        utils.log("wolfssl-certgen-native command not found")
    end

    -- Fallback: Parse certificate content directly
    local cert_base64 = cert_content:match("%-%-%-%-%-BEGIN CERTIFICATE%-%-%-%-%-\r?\n(.+)\r?\n%-%-%-%-%-END CERTIFICATE%-%-%-%-%-")
    if not cert_base64 then
        return nil
    end

    -- Basic certificate info extraction
    info.common_name = "SSL Certificate"
    info.expires = "Unknown"

    -- Try to extract hostname from certificate content
    -- Look for readable hostname patterns in the certificate data
    local cert_text = cert_content

    -- Try to find hostname patterns (case-insensitive)
    local hostname_match = cert_text:match("([%w%-]+%.local)") or
                          cert_text:match("([%w%-]+%.com)") or
                          cert_text:match("([%w%-]+%.org)") or
                          cert_text:match("([%w%-]+%.net)")

    if hostname_match then
        info.common_name = hostname_match
        info.issuer = "Thingino (Self-signed)"
    else
        -- Fallback to pattern matching
        local cert_lower = cert_content:lower()
        if cert_lower:find("thingino") then
            info.common_name = "Thingino Camera"
            info.issuer = "Thingino (Self-signed)"
        elseif cert_lower:find("camera") then
            info.common_name = "Camera Certificate"
        elseif cert_lower:find("localhost") then
            info.common_name = "localhost"
        else
            info.common_name = "SSL Certificate"
        end
    end

    -- Calculate expiration based on certificate creation time
    local cert_file = CONFIG.ssl_cert_path
    if utils.file_exists(cert_file) then
        local stat_output = utils.execute_command("stat -c '%Y' " .. cert_file .. " 2>/dev/null")
        if stat_output and stat_output ~= "" then
            local timestamp = tonumber(stat_output:gsub("%s", ""))
            if timestamp then
                -- Thingino certificates are typically valid for 10 years
                local expire_timestamp = timestamp + (10 * 365 * 24 * 60 * 60)
                info.expires = os.date(utils.DATETIME_FORMAT, expire_timestamp)

                -- Add validity indicator
                local now = os.time()
                if expire_timestamp > now then
                    local days_left = math.floor((expire_timestamp - now) / (24 * 60 * 60))
                    if days_left > 365 then
                        info.expires = info.expires .. " (Valid for " .. math.floor(days_left / 365) .. " years)"
                    else
                        info.expires = info.expires .. " (Valid for " .. days_left .. " days)"
                    end
                else
                    info.expires = info.expires .. " (EXPIRED)"
                end
            end
        end
    end

    -- Check certificate size to determine if it's likely valid
    local cert_size = #cert_base64:gsub("%s", "")
    if cert_size > 800 then
        info.common_name = info.common_name .. " (Valid)"
    elseif cert_size > 400 then
        info.common_name = info.common_name .. " (Basic)"
    else
        info.common_name = info.common_name .. " (Minimal)"
    end

    return info
end

function utils.get_certificate_info2(cert_content)
    if not cert_content or cert_content == "" then
        return nil
    end

    -- Write to temporary file
    local temp_cert = "/tmp/temp_cert_info.pem"
    local file = io.open(temp_cert, "w")
    if not file then
        return nil
    end
    file:write(cert_content)
    file:close()

    -- Get certificate info using wolfSSL ssl_server2
    local cert_info = utils.execute_command("ssl_server2 crt_file=" .. temp_cert .. " exchanges=0 2>/dev/null")
    os.remove(temp_cert)

    if not cert_info or cert_info == "" then
        return nil
    end

    local info = {}

    -- Extract common name from subject name line
    -- Format: "subject name      : C=US, ST=State, L=City, O=Thingino, CN=camera.local"
    local subject_line = cert_info:match("subject name%s*:%s*([^\r\n]+)")
    if subject_line then
        info.common_name = subject_line:match("CN=([^,\r\n]+)") or "Unknown"
        info.common_name = info.common_name:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    else
        info.common_name = "Unknown"
    end

    -- Extract expiration date
    -- Format: "expires on        : 2035-05-29 20:09:37"
    info.expires = cert_info:match("expires on%s*:%s*([^\r\n]+)") or "Unknown"
    if info.expires ~= "Unknown" then
        info.expires = info.expires:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    end

    -- Extract issuer
    -- Format: "issuer name       : C=US, ST=State, L=City, O=Thingino, CN=camera.local"
    local issuer_line = cert_info:match("issuer name%s*:%s*([^\r\n]+)")
    if issuer_line then
        info.issuer = issuer_line:match("CN=([^,\r\n]+)") or issuer_line
        info.issuer = info.issuer:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
    else
        info.issuer = "Unknown"
    end

    return info
end

function utils.format_uptime(seconds)
    local days = math.floor(seconds / 86400)
    local hours = math.floor((seconds % 86400) / 3600)
    local minutes = math.floor((seconds % 3600) / 60)

    if days > 0 then
        return string.format("%d days, %d hours, %d minutes", days, hours, minutes)
    elseif hours > 0 then
        return string.format("%d hours, %d minutes", hours, minutes)
    else
        return string.format("%d minutes", minutes)
    end
end

function utils.get_content_type(path)
    local ext = path:match("%.([^%.]+)$")
    local content_types = {
        html = "text/html",
        css = "text/css",
        js = "application/javascript",
        json = "application/json",
        png = "image/png",
        jpg = "image/jpeg",
        jpeg = "image/jpeg",
        gif = "image/gif",
        svg = "image/svg+xml",
        ico = "image/x-icon"
    }

    return content_types[ext] or "application/octet-stream"
end

-- Simple JSON encoding (basic implementation)
function utils.table_to_json(t)
    if type(t) ~= "table" then
        if type(t) == "string" then
            return '"' .. t:gsub('"', '\\"') .. '"'
        else
            return tostring(t)
        end
    end

    local result = {}
    local is_array = true
    local max_index = 0

    -- Check if table is an array
    for k, v in pairs(t) do
        if type(k) ~= "number" then
            is_array = false
            break
        end
        max_index = math.max(max_index, k)
    end

    if is_array then
        result[#result + 1] = "["
        for i = 1, max_index do
            if i > 1 then result[#result + 1] = "," end
            result[#result + 1] = utils.table_to_json(t[i])
        end
        result[#result + 1] = "]"
    else
        result[#result + 1] = "{"
        local first = true
        for k, v in pairs(t) do
            if not first then result[#result + 1] = "," end
            result[#result + 1] = '"' .. tostring(k) .. '":'
            result[#result + 1] = utils.table_to_json(v)
            first = false
        end
        result[#result + 1] = "}"
    end

    return table.concat(result)
end

function utils.log(message)
    -- Try multiple logging methods
    local log_file = io.open("/tmp/webui-lua.log", "a")
    if log_file then
        log_file:write(os.date(utils.DATETIME_FORMAT) .. " " .. message .. "\n")
        log_file:close()
    end

    -- Also log to syslog as backup
    os.execute("logger 'WEBUI-LUA: " .. message .. "'")
end

function utils.redirect(location)
    return utils.send_redirect(location)
end

return utils
