-- Main Lua handler for thingino web interface
package.path = "/var/www/lua/lib/?.lua;" .. package.path

local session = require("session")
local auth = require("auth")
local utils = require("utils")
local config = require("config")
local i18n = require("i18n")

-- Initialize i18n system
i18n.init()

-- Global configuration
local CONFIG = {
    session_timeout = 0, -- Disabled - sessions are permanent until logout
    debug = true, -- Debug enabled for troubleshooting
    disable_auth = true, -- DISABLE AUTHENTICATION FOR CLI TOOLS

    -- SSL Certificate paths
    ssl_cert_path = "/etc/ssl/certs/uhttpd.crt",
    ssl_key_path = "/etc/ssl/private/uhttpd.key",

    -- Font paths
    fonts_path = "/opt/fonts",

    -- Prudynt configuration path
    prudynt_config_path = "/etc/prudynt.json",

    -- ROI zones configuration path
    motion_config_path = "/etc/streamer.d/roi.json",

    -- Streamer configuration
    streamer_port = 8080,
    streamer_host = "localhost",

    -- Date/time format template
    datetime_format = "%Y-%m-%d %H:%M:%S",

    -- Motion detection configuration path
    motion_config_path = "/etc/motion.json"
}

function handle_request(env)
    local uri = env.REQUEST_URI or "/"
    local method = env.REQUEST_METHOD or "GET"

    -- Parse URI and query string
    local path, query = uri:match("^([^?]*)%??(.*)$")
    path = path:gsub("^/lua", "") -- Remove /lua prefix
    if path == "" or path == "/" then
        path = "/dashboard"
    end

    -- Debug logging
    if CONFIG.debug then
        utils.log("Request: " .. method .. " " .. path)
    end

    -- Check session for protected pages
    local sess = session.get(env)
    local is_authenticated = sess and sess.user and not session.is_expired(sess)

    -- Check if authentication is disabled globally
    if CONFIG.disable_auth then
        utils.log("AUTH DISABLED: Creating fake session for all requests")
        -- Create a fake session for all requests when auth is disabled
        sess = {
            id = "disabled-auth",
            user = "root",
            created = os.time(),
            last_activity = os.time(),
            remote_addr = env.REMOTE_ADDR or "unknown"
        }
        is_authenticated = true
        utils.log("AUTH DISABLED: is_authenticated = " .. tostring(is_authenticated))
    else
        -- Check if request is from localhost (bypass authentication)
        local remote_addr = env.REMOTE_ADDR or ""
        local http_host = env.HTTP_HOST or ""

        -- Simple localhost detection
        local is_localhost = false
        if remote_addr == "127.0.0.1" or remote_addr == "::1" or
           http_host == "localhost" or http_host == "127.0.0.1" or
           remote_addr == "" then
            is_localhost = true
        end

        if is_localhost then
            -- Create a fake session for localhost requests
            sess = {
                id = "localhost",
                user = "root",
                created = os.time(),
                last_activity = os.time(),
                remote_addr = "localhost"
            }
            is_authenticated = true
        end
    end

    -- Public pages (no auth required)
    if path == "/login" then
        if is_authenticated then
            return utils.redirect("/lua/dashboard")
        end
        return serve_login_page(env, query)
    elseif path == "/api/login" then
        return handle_login_api(env)
    elseif path == "/debug" then
        -- Debug endpoint to test localhost detection (always public)
        local remote_addr = env.REMOTE_ADDR or "none"
        local http_host = env.HTTP_HOST or "none"
        local is_local = (remote_addr == "127.0.0.1" or http_host == "localhost")
        utils.send_html("<h1>Debug Info</h1><p>REMOTE_ADDR: " .. remote_addr .. "</p><p>HTTP_HOST: " .. http_host .. "</p><p>is_localhost: " .. tostring(is_local) .. "</p><p>is_authenticated: " .. tostring(is_authenticated) .. "</p>")
        return
    elseif path:match("^/static/") then
        return serve_static_file(path)
    end

    -- Protected pages (auth required)
    utils.log("AUTH CHECK: is_authenticated = " .. tostring(is_authenticated) .. " for path = " .. path)
    if not is_authenticated then
        utils.log("AUTH FAILED: Redirecting to login for path = " .. path)
        return utils.redirect("/lua/login")
    end
    utils.log("AUTH SUCCESS: Proceeding with request for path = " .. path)

    -- Update session activity
    session.update_activity(sess)

    -- Route to appropriate handler
    if path == "/dashboard" then
        return serve_dashboard(sess)
    elseif path == "/info" or path == "/info/system" then
        return serve_info_page("system", sess)
    elseif path == "/info/network" then
        return serve_info_page("network", sess)
    elseif path == "/info/camera" then
        return serve_info_page("camera", sess)
    elseif path == "/info/logs" then
        return serve_info_page("logs", sess)
    elseif path == "/preview" then
        return serve_preview_page(sess)
    elseif path == "/motion" then
        return serve_motion_page(sess)
    elseif path:match("^/streamer") then
        return handle_streamer_page(path, env, sess)
    elseif path:match("^/config") then
        return handle_config_page(path, env, sess)
    elseif path == "/mjpeg" then
        return api_get_mjpeg_stream(sess)
    elseif path:match("^/api/") then
        return handle_api_request(path, env, sess)
    elseif path == "/logout" then
        return handle_logout(env)
    else
        return utils.send_error(404, "Page not found")
    end
end

function serve_login_page(env, query)
    local error_msg = ""
    if query:match("error=1") then
        error_msg = '<div class="alert alert-danger">Invalid username or password</div>'
    elseif query:match("expired=1") then
        error_msg = '<div class="alert alert-warning">Your session has expired. Please login again.</div>'
    end

    local html = utils.load_template("login", {
        error_message = error_msg,
        hostname = utils.get_hostname()
    })

    utils.send_html(html)
end

function handle_login_api(env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_error(405, "Method not allowed")
    end

    -- Parse POST data
    local post_data = utils.read_post_data(env)
    local username = post_data.username or ""
    local password = post_data.password or ""

    if auth.verify_user(username, password) then
        local sess = session.create(username, env.REMOTE_ADDR or "unknown")
        local cookie = session.make_cookie(sess.id)

        utils.send_redirect("/lua/dashboard", {
            ["Set-Cookie"] = cookie
        })
    else
        utils.send_redirect("/lua/login?error=1")
    end
end

-- Helper function to add debug information to template variables
function add_debug_info(template_vars, sess)
    local now = os.time()
    local time_since_activity = now - (sess.last_activity or now)
    local time_remaining = math.max(0, CONFIG.session_timeout - time_since_activity)

    template_vars.session_id = sess.id or "unknown"
    template_vars.session_created = os.date(CONFIG.datetime_format, sess.created or now)
    template_vars.session_last_activity = os.date(CONFIG.datetime_format, sess.last_activity or now)
    template_vars.session_time_since = time_since_activity .. "s"
    template_vars.session_timeout = CONFIG.session_timeout
    template_vars.session_time_remaining = time_remaining .. "s"
    template_vars.server_time = os.date(CONFIG.datetime_format, now)

    local system_info = utils.get_system_info()
    template_vars.system_uptime = system_info.uptime or "Unknown"

    return template_vars
end

function serve_dashboard(sess)
    local camera_status = utils.get_camera_status()
    local system_info = utils.get_system_info_detailed()

    -- Get memory data from detailed system info
    local memory_percentage = system_info.memory_percentage or 0
    local memory_used = system_info.memory_used or "N/A"
    local memory_total = system_info.memory_total or "N/A"

    -- Format load average for template
    local load_average_str = "N/A"
    if system_info.load_1min and system_info.load_5min and system_info.load_15min then
        load_average_str = string.format("%s, %s, %s",
            system_info.load_1min,
            system_info.load_5min,
            system_info.load_15min)
    end

    local template_vars = {
        page_title = "Dashboard",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "active",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "",

        -- System stats
        stream_status = "Online",
        cpu_temp = system_info.cpu_temp or "N/A",
        memory_usage = memory_percentage,
        storage_usage = system_info.disk_usage or 0,

        -- System info
        uptime = system_info.uptime or "System running",
        load_average = load_average_str,

        -- Activity timestamps
        boot_time = os.date(CONFIG.datetime_format, sess.created),
        stream_start_time = os.date(CONFIG.datetime_format, sess.last_activity),
        last_snapshot_time = "Just now",

        system_load = load_average_str,
        system_memory = string.format("%s / %s (%s%%)",
              memory_used,
              memory_total,
              memory_percentage),
        system_storage = "Unknown"  -- Will be updated below
    }

    -- Get storage information
    local df_output = utils.execute_command("df -h / | tail -1")
    if df_output then
        local used, available, usage_pct = df_output:match("(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%%")
        if used and available and usage_pct then
            template_vars.system_storage = string.format("%s / %s (%s%%)", used, available, usage_pct)
        end
    end

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("dashboard", template_vars)
    utils.send_html(html)
end

function serve_info_page(info_type, sess)
    local template_vars = {
        page_title = info_type:gsub("^%l", string.upper) .. " Information",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "active",
        nav_config_active = "",

        -- Info submenu active states
        info_system_active = (info_type == "system") and "active" or "",
        info_network_active = (info_type == "network") and "active" or "",
        info_camera_active = (info_type == "camera") and "active" or "",
        info_logs_active = (info_type == "logs") and "active" or ""
    }

    -- Get data based on info type
    if info_type == "system" then
        local info = utils.get_system_info_detailed()

        -- Format load average for template
        local load_average_str = "N/A"
        if info.load_average then
            local la = info.load_average
            load_average_str = string.format("%s, %s, %s",
                la.one_min or "0.00",
                la.five_min or "0.00",
                la.fifteen_min or "0.00")
        end

        template_vars.cpu_model = info.cpu_model or "Unknown"
        template_vars.cpu_cores = info.cpu_cores or "Unknown"
        template_vars.architecture = info.architecture or "Unknown"
        template_vars.kernel = info.kernel or "Unknown"
        template_vars.firmware_version = info.firmware_version or "Unknown"
        template_vars.memory_total = info.memory_total or "Unknown"
        template_vars.memory_used = info.memory_used or "Unknown"
        template_vars.memory_percentage = info.memory_percentage or "0"
        template_vars.disk_usage = info.disk_usage or "0"
        template_vars.cpu_temp = info.cpu_temp or "Unknown"
        template_vars.uptime = info.uptime or "Unknown"
        template_vars.load_average = load_average_str
        template_vars.load_1min = (info.load_average and info.load_average.one_min) or "0.00"
        template_vars.load_5min = (info.load_average and info.load_average.five_min) or "0.00"
        template_vars.load_15min = (info.load_average and info.load_average.fifteen_min) or "0.00"

    elseif info_type == "network" then
        local info = utils.get_network_info()
        template_vars.primary_interface = info.primary_interface or "wlan0"
        template_vars.ip_address = info.ip_address or "192.168.1.109"
        template_vars.netmask = info.netmask or "255.255.255.0"
        template_vars.gateway = info.gateway or "192.168.1.1"
        template_vars.mac_address = info.mac_address or "aa:bb:cc:dd:ee:ff"
        template_vars.hostname = info.hostname or "thingino-camera"
        template_vars.dns_primary = info.dns_primary or "8.8.8.8"
        template_vars.dns_secondary = info.dns_secondary or "8.8.4.4"
        template_vars.dhcp_status = info.dhcp_status or "Enabled"
        template_vars.wlan0_ip = info.wlan0_ip or "192.168.1.109"
        template_vars.wlan0_mac = info.wlan0_mac or "aa:bb:cc:dd:ee:ff"
        template_vars.eth0_mac = info.eth0_mac or "aa:bb:cc:dd:ee:00"

    elseif info_type == "camera" then
        local info = utils.get_camera_info()
        template_vars.sensor_model = info.sensor_model or "IMX307"
        template_vars.max_resolution = info.max_resolution or "1920x1080"
        template_vars.isp_version = info.isp_version or "T31"
        template_vars.video_encoder = info.video_encoder or "H.264"
        template_vars.night_vision_status = info.night_vision_status or "Available"
        template_vars.night_vision_badge_class = "bg-success"
        template_vars.stream_status = info.stream_status or "Online"
        template_vars.stream_status_badge_class = "bg-success"
        template_vars.current_resolution = info.current_resolution or "1920x1080"
        template_vars.current_fps = info.current_fps or "25"
        template_vars.current_bitrate = info.current_bitrate or "2048"
        template_vars.current_codec = info.current_codec or "H.264"
        template_vars.sensor_details = info.sensor_details or "Sensor: IMX307\nInterface: MIPI\nBit depth: 12-bit"
        template_vars.streaming_config = info.streaming_config or "Resolution: 1920x1080\nFPS: 25\nBitrate: 2048 kbps\nCodec: H.264"

    elseif info_type == "logs" then
        local info = utils.get_system_logs()
        template_vars.system_logs = info.system or "System logs will be displayed here..."
        template_vars.kernel_logs = info.kernel or "Kernel logs will be displayed here..."
        template_vars.boot_logs = info.boot or "Boot logs will be displayed here..."
        template_vars.camera_logs = "Camera logs will be displayed here..."
        template_vars.network_logs = "Network logs will be displayed here..."
        template_vars.security_logs = "Security logs will be displayed here..."
    end

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("info/" .. info_type, template_vars)
    utils.send_html(html)
end

function serve_preview_page(sess)
    local camera_config = config.get_camera_config()

    local html = utils.load_template("preview", {
        page_title = "Camera Preview",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "active",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "",

        -- Camera config
        ws_token = utils.get_websocket_token(),
        camera_config = camera_config
    })

    utils.send_html(html)
end

function serve_motion_page(sess)
    local template_vars = {
        page_title = "Motion Detection",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "active",
        nav_info_active = "",
        nav_config_active = ""
    }

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("motion", template_vars)
    utils.send_html(html)
end

function handle_config_page(path, env, sess)
    local config_type = path:match("/config%-(.+)") or path:match("/config/(.+)") or "general"

    -- Clean up config_type - remove leading slash if present
    config_type = config_type:gsub("^/", "")

    utils.log("Raw path: " .. path)
    utils.log("Extracted config_type: " .. config_type)

    -- Handle specific new configuration pages
    if config_type == "datetime" then
        return handle_datetime_config(env, sess)
    elseif config_type == "user" then
        return handle_user_config(env, sess)
    elseif config_type == "security" then
        return handle_security_config(env, sess)
    elseif config_type == "storage" then
        return handle_storage_config(env, sess)
    elseif config_type == "maintenance" then
        return handle_maintenance_config(env, sess)
    elseif config_type == "firmware" then
        return handle_firmware_config(env, sess)
    end

    if env.REQUEST_METHOD == "POST" then
        return handle_config_update(config_type, env, sess)
    else
        return serve_config_page(config_type, sess)
    end
end

function serve_config_page(config_type, sess)
    local config_data = config.get_config(config_type)

    -- Debug logging
    utils.log("=== CONFIG PAGE DEBUG START ===")
    utils.log("Config type: " .. config_type)
    utils.log("Config data: " .. utils.table_to_json(config_data or {}))

    -- Simple test of template replacement
    local test_template = "Hello {{test_var}}!"
    local test_result = test_template:gsub("{{%s*test_var%s*}}", "WORLD")
    utils.log("Template test: '" .. test_template .. "' -> '" .. test_result .. "'")

    -- Test the actual utils.load_template function
    local test_content = "Test: {{config_hostname}} and {{config_ip_address}}"
    local test_vars = {config_hostname = "test-host", config_ip_address = "192.168.1.100"}
    utils.log("Testing template replacement directly...")
    for k, v in pairs(test_vars) do
        local pattern = "{{%s*" .. k .. "%s*}}"
        local before = test_content
        test_content = test_content:gsub(pattern, tostring(v))
        utils.log("Pattern: " .. pattern .. " | Before: " .. before .. " | After: " .. test_content)
    end

    -- Flatten config data for template compatibility
    local template_vars = {
        user = sess.user,
        hostname = utils.get_hostname(),
        page_title = config_type:gsub("^%l", string.upper) .. " Configuration",
        username = sess.user
    }

    -- Add flattened config variables
    if config_data then
        for key, value in pairs(config_data) do
            template_vars["config_" .. key] = value or ""
            utils.log("Template var: config_" .. key .. " = " .. tostring(value or ""))
        end

        -- Add special conditional variables for network config
        if config_type == "network" then
            template_vars.interface_wlan0_selected = (config_data.interface == "wlan0") and "selected" or ""
            template_vars.interface_eth0_selected = (config_data.interface == "eth0") and "selected" or ""
            template_vars.dhcp_checked = (config_data.dhcp == "true") and "checked" or ""
            template_vars.dhcp_section_hidden = (config_data.dhcp == "true") and "hidden" or ""
            template_vars.wifi_encryption_wpa2_selected = (config_data.wifi_encryption == "wpa2") and "selected" or ""
            template_vars.wifi_encryption_wpa3_selected = (config_data.wifi_encryption == "wpa3") and "selected" or ""
            template_vars.wifi_encryption_wep_selected = (config_data.wifi_encryption == "wep") and "selected" or ""
            template_vars.wifi_encryption_none_selected = (config_data.wifi_encryption == "none") and "selected" or ""
        elseif config_type == "camera" then
            -- Add fallbacks for camera config values
            template_vars.config_sensor = (config_data.sensor and config_data.sensor ~= "" and config_data.sensor ~= "unknown") and config_data.sensor or "N/A"
            template_vars.config_ir_cut = (config_data.ir_cut and config_data.ir_cut ~= "") and config_data.ir_cut or "N/A"
            template_vars.config_ir_led = (config_data.ir_led and config_data.ir_led ~= "") and config_data.ir_led or "N/A"
            template_vars.config_bitrate = config_data.bitrate or "2048"

            -- Camera configuration (data-driven)
            template_vars.current_resolution = config_data.resolution or "1920x1080"
            template_vars.current_fps = config_data.fps or "25"
            template_vars.current_codec = config_data.codec or "h264"

            -- Flip checkboxes
            template_vars.flip_horizontal_checked = (config_data.flip_horizontal == "true") and "checked" or ""
            template_vars.flip_vertical_checked = (config_data.flip_vertical == "true") and "checked" or ""

            -- Night mode configuration (data-driven)
            template_vars.current_night_mode = config_data.night_mode or "auto"
        elseif config_type == "system" then
            -- Add fallbacks for system config values
            template_vars.config_ntp_server = config_data.ntp_server or "pool.ntp.org"
            template_vars.config_ntp_server_backup = config_data.ntp_server_backup or "time.nist.gov"
            template_vars.config_webui_username = config_data.webui_username or "root"
            template_vars.config_admin_username = config_data.webui_username or "root" -- Alias for template compatibility
            template_vars.config_timezone = config_data.timezone or "UTC"
            template_vars.config_log_level = config_data.log_level or "info"
            template_vars.config_webui_theme = config_data.webui_theme or "dark"

            -- Add system information for system config page
            local system_info = utils.get_system_info_detailed()
            template_vars.system_uptime = system_info.uptime or "Unknown"
            template_vars.system_load = string.format("%s, %s, %s",
                system_info.load_1min or "0.00",
                system_info.load_5min or "0.00",
                system_info.load_15min or "0.00")
            template_vars.system_memory = string.format("%s / %s (%s%%)",
                system_info.memory_used or "Unknown",
                system_info.memory_total or "Unknown",
                system_info.memory_percentage or "0")

            -- Get storage information
            local df_output = utils.execute_command("df -h / | tail -1")
            if df_output then
                local used, available, usage_pct = df_output:match("(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%%")
                if used and available and usage_pct then
                    template_vars.system_storage = string.format("%s / %s (%s%%)", used, available, usage_pct)
                else
                    template_vars.system_storage = "Unknown"
                end
            else
                template_vars.system_storage = "Unknown"
            end

            -- Add additional system information for overview page
            template_vars.hostname = utils.get_hostname() or "thingino"

            -- Get firmware information from os-release
            local os_release = utils.read_file("/etc/os-release") or ""
            template_vars.firmware_version = os_release:match('VERSION="([^"]+)"') or os_release:match("VERSION=([^\n]+)") or "Unknown"
            template_vars.firmware_build = os_release:match('BUILD_ID="([^"]+)"') or os_release:match("BUILD_ID=([^\n]+)") or "Unknown"
            template_vars.firmware_profile = os_release:match('IMAGE_ID=([^\n]+)') or "Unknown"

            -- Timezone selection (data-driven from /usr/share/tz.json.gz)
            template_vars.current_timezone = config_data.timezone or "UTC"

            -- Access checkboxes
            template_vars.ssh_enabled_checked = (config_data.ssh_enabled == "true") and "checked" or ""
            template_vars.enable_ssh_checked = (config_data.ssh_enabled == "true") and "checked" or "" -- Alias
            template_vars.telnet_enabled_checked = (config_data.telnet_enabled == "true") and "checked" or ""
            template_vars.enable_https_checked = "" -- Placeholder for HTTPS setting
            template_vars.config_session_timeout = "30" -- Default session timeout
            template_vars.config_log_retention = config_data.log_retention or "7" -- Default log retention

            -- Timezone selection is now handled dynamically via /lua/api/timezones API

            -- Log level configuration (data-driven)
            template_vars.current_log_level = config_data.log_level or "info"

            -- SSL Certificate status
            local ssl_cert_exists = utils.file_exists(CONFIG.ssl_cert_path) and utils.file_exists(CONFIG.ssl_key_path)

            if ssl_cert_exists then
                template_vars.ssl_status_class = "bg-success"
                template_vars.ssl_status_text = "Installed"

                -- SSL button visibility - show Remove, hide Generate
                template_vars.ssl_remove_class = ""
                template_vars.ssl_remove_style = ""
                template_vars.ssl_generate_class = "d-none"
                template_vars.ssl_generate_style = "style=\"display: none;\""

                -- Try to get certificate info using improved parsing
                utils.log("Attempting to read SSL certificate: " .. CONFIG.ssl_cert_path)

                local cert_content = utils.read_file(CONFIG.ssl_cert_path)
                if cert_content then
                    local cert_info = utils.get_certificate_info(cert_content)
                    if cert_info then
                        template_vars.ssl_cert_info = cert_info.common_name or "SSL Certificate"
                        template_vars.ssl_cert_expires = cert_info.expires or "Unknown"
                        utils.log("Found certificate CN: " .. template_vars.ssl_cert_info)
                        utils.log("Found certificate expiry: " .. template_vars.ssl_cert_expires)
                    else
                        -- Fallback: try cert_app directly
                        utils.log("Trying alternative certificate parsing methods...")

                        -- Try cert_app directly
                        local cert_info_output = utils.execute_command("cert_app mode=file filename=" .. CONFIG.ssl_cert_path .. " 2>/dev/null")
                        if cert_info_output and cert_info_output ~= "" then
                            utils.log("cert_app output: " .. cert_info_output)

                            -- Parse output for common name and expiry
                            local subject_line = cert_info_output:match("subject name%s*:%s*([^\r\n]+)")
                            local cn = "SSL Certificate"
                            if subject_line then
                                cn = subject_line:match("CN=([^,\r\n]+)") or "SSL Certificate"
                                cn = cn:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                            end

                            local expires = cert_info_output:match("expires on%s*:%s*([^\r\n]+)") or "Unknown"
                            if expires ~= "Unknown" then
                                expires = expires:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                            end

                            template_vars.ssl_cert_info = cn
                            template_vars.ssl_cert_expires = expires
                        else
                            template_vars.ssl_cert_info = "SSL Certificate"
                            template_vars.ssl_cert_expires = "Unknown"
                            utils.log("All certificate parsing methods failed")
                        end
                    end
                else
                    template_vars.ssl_cert_info = "Certificate file"
                    template_vars.ssl_cert_expires = "Unknown"
                    utils.log("Could not read certificate file")
                end
            else
                template_vars.ssl_status_class = "bg-secondary"
                template_vars.ssl_status_text = "Not Installed"
                template_vars.ssl_cert_info = "No certificate installed"
                template_vars.ssl_cert_expires = "N/A"

                -- SSL button visibility - show Generate, hide Remove
                template_vars.ssl_remove_class = "d-none"
                template_vars.ssl_remove_style = "style=\"display: none;\""
                template_vars.ssl_generate_class = ""
                template_vars.ssl_generate_style = ""
            end

            -- Get firmware information from /etc/os-release
            local firmware_version = "Unknown"
            local firmware_profile = "Unknown"
            local firmware_build = "Unknown"

            local os_release_file = io.open("/etc/os-release", "r")
            if os_release_file then
                local content = os_release_file:read("*a")
                os_release_file:close()

                -- Extract Thingino-specific fields
                local image_id = content:match('IMAGE_ID="([^"]+)"') or content:match("IMAGE_ID=([^\r\n]+)")
                local build_id = content:match('BUILD_ID="([^"]+)"') or content:match("BUILD_ID=([^\r\n]+)")
                local build_time = content:match('BUILD_TIME="([^"]+)"') or content:match("BUILD_TIME=([^\r\n]+)")

                -- Set firmware_profile from IMAGE_ID
                if image_id then
                    firmware_profile = image_id:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                end

                -- Set firmware_build from BUILD_ID
                if build_id then
                    firmware_build = build_id:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                end

                -- Set firmware_version (for backward compatibility with Firmware Update card)
                if build_id then
                    firmware_version = build_id
                    if build_time then
                        firmware_version = firmware_version .. " (" .. build_time .. ")"
                    end
                else
                    -- Fallback to standard fields
                    firmware_version = content:match('VERSION="([^"]+)"') or
                                     content:match("VERSION=([^\r\n]+)") or
                                     content:match('VERSION_ID="([^"]+)"') or
                                     content:match("VERSION_ID=([^\r\n]+)") or
                                     content:match('PRETTY_NAME="([^"]+)"') or
                                     content:match("PRETTY_NAME=([^\r\n]+)") or
                                     "Unknown"
                    firmware_version = firmware_version:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
                end
            end

            template_vars.firmware_version = firmware_version
            template_vars.firmware_profile = firmware_profile
            template_vars.firmware_build = firmware_build

            utils.log("Firmware profile: " .. firmware_profile)
            utils.log("Firmware build: " .. firmware_build)
            utils.log("Firmware version: " .. firmware_version)

            -- Log level configuration already handled above

            -- Theme configuration (data-driven)
            template_vars.current_webui_theme = config_data.webui_theme or "dark"

            -- Paranoid mode checkbox
            template_vars.webui_paranoid_checked = (config_data.webui_paranoid == "true") and "checked" or ""

            -- Status display values
            template_vars.ssh_status = (config_data.ssh_enabled == "true") and "Enabled" or "Disabled"
        end
    end

    -- Add navigation state variables
    local clean_config_type = config_type:gsub("^/", "") -- Remove leading slash
    template_vars.page_title = clean_config_type:gsub("^%l", string.upper) .. " Configuration"
    template_vars.username = sess.user

    -- Navigation state
    template_vars.nav_dashboard_active = ""
    template_vars.nav_preview_active = ""
    template_vars.nav_motion_active = ""
    template_vars.nav_info_active = ""
    template_vars.nav_config_active = "active"

    -- Config submenu active states
    template_vars.config_network_active = (config_type == "network") and "active" or ""
    template_vars.config_camera_active = (config_type == "camera") and "active" or ""
    template_vars.config_system_active = (config_type == "system") and "active" or ""

    -- Debug: log all template variables
    utils.log("All template vars for " .. config_type .. ":")
    for k, v in pairs(template_vars) do
        utils.log("  " .. k .. " = " .. tostring(v))
    end

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local template_path = "config/" .. config_type
    utils.log("Loading template: " .. template_path)

    local html = utils.load_template(template_path, template_vars)

    -- Debug: check if template variables are still present in output
    local remaining_vars = {}
    for var in html:gmatch("{{[^}]+}}") do
        table.insert(remaining_vars, var)
    end
    if #remaining_vars > 0 then
        utils.log("WARNING: Unreplaced template variables found: " .. table.concat(remaining_vars, ", "))
    end

    utils.send_html(html)
end

function handle_config_update(config_type, env, sess)
    local post_data = utils.read_post_data(env)
    local success, message = config.update_config(config_type, post_data)

    if success then
        utils.send_redirect("/lua/config-" .. config_type .. "?success=1")
    else
        utils.send_redirect("/lua/config-" .. config_type .. "?error=" .. utils.url_encode(message))
    end
end

-- Individual configuration page handlers
function handle_datetime_config(env, sess)
    if env.REQUEST_METHOD == "POST" then
        local post_data = utils.read_post_data(env)
        local success, message = config.update_system_config(config.load(), post_data)

        if success then
            utils.send_redirect("/lua/config/datetime?success=1")
        else
            utils.send_redirect("/lua/config/datetime?error=" .. utils.url_encode(message))
        end
        return
    end

    local system_config = config.get_system_config()
    local template_vars = {
        page_title = "Date & Time Configuration",
        username = sess.user,
        config_timezone = system_config.timezone,
        config_ntp_server = system_config.ntp_server,
        config_ntp_server_backup = system_config.ntp_server_backup,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/datetime", template_vars)
    utils.send_html(html)
end

function handle_user_config(env, sess)
    if env.REQUEST_METHOD == "POST" then
        local post_data = utils.read_post_data(env)
        local success, message = config.update_system_config(config.load(), post_data)

        if success then
            utils.send_redirect("/lua/config/user?success=1")
        else
            utils.send_redirect("/lua/config/user?error=" .. utils.url_encode(message))
        end
        return
    end

    local system_config = config.get_system_config()
    local template_vars = {
        page_title = "User Management",
        username = sess.user,
        config_session_timeout = system_config.session_timeout or "120",

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/user", template_vars)
    utils.send_html(html)
end

function handle_security_config(env, sess)
    if env.REQUEST_METHOD == "POST" then
        local post_data = utils.read_post_data(env)
        local success, message = config.update_system_config(config.load(), post_data)

        if success then
            utils.send_redirect("/lua/config/security?success=1")
        else
            utils.send_redirect("/lua/config/security?error=" .. utils.url_encode(message))
        end
        return
    end

    local system_config = config.get_system_config()
    local template_vars = {
        page_title = "Security & SSL Configuration",
        username = sess.user,
        hostname = utils.get_hostname(),
        enable_https_checked = (system_config.enable_https == "true") and "checked" or "",
        enable_ssh_checked = (system_config.ssh_enabled == "true") and "checked" or "",

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- SSL Certificate status (reuse existing logic)
    local ssl_cert_exists = utils.file_exists(CONFIG.ssl_cert_path) and utils.file_exists(CONFIG.ssl_key_path)

    if ssl_cert_exists then
        template_vars.ssl_status_class = "bg-success"
        template_vars.ssl_status_text = "Installed"
        template_vars.ssl_remove_class = ""
        template_vars.ssl_remove_style = ""
        template_vars.ssl_generate_class = "d-none"
        template_vars.ssl_generate_style = "style=\"display: none;\""

        -- Get SSL certificate information
        utils.log("=== SSL CERTIFICATE PARSING DEBUG ===")
        utils.log("Attempting to read SSL certificate: " .. CONFIG.ssl_cert_path)
        local cert_content = utils.read_file(CONFIG.ssl_cert_path)
        if cert_content then
            utils.log("Certificate file read successfully, length: " .. #cert_content)
            local cert_info = utils.get_certificate_info(cert_content)
            if cert_info then
                template_vars.ssl_cert_info = cert_info.common_name or "SSL Certificate"
                template_vars.ssl_cert_expires = cert_info.expires or "Unknown"
                utils.log("Certificate parsing SUCCESS:")
                utils.log("  CN: " .. template_vars.ssl_cert_info)
                utils.log("  Expires: " .. template_vars.ssl_cert_expires)
                utils.log("  Issuer: " .. (cert_info.issuer or "Unknown"))
            else
                template_vars.ssl_cert_info = "SSL Certificate"
                template_vars.ssl_cert_expires = "Unknown"
                utils.log("Certificate parsing FAILED - cert_info is nil")
            end
        else
            template_vars.ssl_cert_info = "Certificate file"
            template_vars.ssl_cert_expires = "Unknown"
            utils.log("Could not read certificate file: " .. CONFIG.ssl_cert_path)
        end
        utils.log("=== END SSL CERTIFICATE PARSING DEBUG ===")
    else
        template_vars.ssl_status_class = "bg-secondary"
        template_vars.ssl_status_text = "Not Installed"
        template_vars.ssl_cert_info = "No certificate installed"
        template_vars.ssl_cert_expires = "N/A"
        template_vars.ssl_remove_class = "d-none"
        template_vars.ssl_remove_style = "style=\"display: none;\""
        template_vars.ssl_generate_class = ""
        template_vars.ssl_generate_style = ""
    end

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/security", template_vars)
    utils.send_html(html)
end

function handle_storage_config(env, sess)
    if env.REQUEST_METHOD == "POST" then
        local post_data = utils.read_post_data(env)
        local success, message = config.update_system_config(config.load(), post_data)

        if success then
            utils.send_redirect("/lua/config/storage?success=1")
        else
            utils.send_redirect("/lua/config/storage?error=" .. utils.url_encode(message))
        end
        return
    end

    local system_config = config.get_system_config()
    local template_vars = {
        page_title = "Storage & Logging Configuration",
        username = sess.user,
        config_log_retention = system_config.log_retention or "7",

        -- Log level configuration (data-driven)
        current_log_level = system_config.log_level or "info",

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/storage", template_vars)
    utils.send_html(html)
end

function handle_maintenance_config(env, sess)
    -- Get system information using the correct functions
    local system_info = utils.get_system_info_detailed()

    local template_vars = {
        page_title = "System Maintenance",
        username = sess.user,
        system_uptime = system_info.uptime or "Unknown",
        system_load = string.format("%s, %s, %s",
            system_info.load_1min or "0.00",
            system_info.load_5min or "0.00",
            system_info.load_15min or "0.00"),
        system_memory = string.format("%s / %s (%s%%)",
            system_info.memory_used or "Unknown",
            system_info.memory_total or "Unknown",
            system_info.memory_percentage or "0"),

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- Get storage information
    local df_output = utils.execute_command("df -h / | tail -1")
    if df_output then
        local used, available, usage_pct = df_output:match("(%S+)%s+(%S+)%s+(%S+)%s+(%d+)%%")
        if used and available and usage_pct then
            template_vars.system_storage = string.format("%s / %s (%s%%)", used, available, usage_pct)
        else
            template_vars.system_storage = "Unknown"
        end
    else
        template_vars.system_storage = "Unknown"
    end

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/maintenance", template_vars)
    utils.send_html(html)
end

function handle_firmware_config(env, sess)
    local template_vars = {
        page_title = "Firmware Update",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_info_active = "",
        nav_config_active = "active"
    }

    -- Get firmware information from os-release
    local os_release = utils.read_file("/etc/os-release") or ""
    template_vars.firmware_version = os_release:match('VERSION="([^"]+)"') or os_release:match("VERSION=([^\n]+)") or "Unknown"
    template_vars.firmware_build = os_release:match('BUILD_ID="([^"]+)"') or os_release:match("BUILD_ID=([^\n]+)") or "Unknown"
    template_vars.firmware_profile = os_release:match('IMAGE_ID=([^\n]+)') or "Unknown"

    -- Add debug information
    template_vars = add_debug_info(template_vars, sess)

    local html = utils.load_template("config/firmware", template_vars)
    utils.send_html(html)
end

function handle_streamer_page(path, env, sess)
    local streamer_type = path:gsub("^/streamer/?", "")

    if streamer_type == "" or streamer_type == "/" then
        streamer_type = "motion"  -- Default to motion page
    end

    if streamer_type == "motion" then
        return handle_streamer_motion(env, sess)
    elseif streamer_type == "control" then
        return handle_streamer_control(env, sess)
    elseif streamer_type == "osd" then
        return handle_streamer_osd(env, sess)
    elseif streamer_type == "config" then
        return handle_streamer_config(env, sess)
    else
        return utils.send_error(404, "Streamer page not found")
    end
end

function handle_streamer_motion(env, sess)
    -- Redirect to the existing working motion page
    utils.send_redirect("/lua/motion")
end

function handle_streamer_control(env, sess)
    local template_vars = {
        page_title = "Camera Control",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_streamer_active = "active",
        nav_info_active = "",
        nav_config_active = "",

        -- Streamer submenu state
        streamer_motion_active = "",
        streamer_control_active = "active",
        streamer_osd_active = "",
        streamer_config_active = ""
    }

    local html = utils.load_template("streamer/control", template_vars)
    utils.send_html(html)
end

function handle_streamer_osd(env, sess)
    local template_vars = {
        page_title = "On-Screen Display",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_streamer_active = "active",
        nav_info_active = "",
        nav_config_active = "",

        -- Streamer submenu state
        streamer_motion_active = "",
        streamer_control_active = "",
        streamer_osd_active = "active",
        streamer_config_active = "",

        -- Camera preview component variables
        preview_title = "OSD Preview",
        preview_description = "Preview shows how OSD elements will appear on the camera stream"
    }

    local html = utils.load_template("streamer/osd", template_vars)
    utils.send_html(html)
end

function handle_streamer_config(env, sess)
    -- Read prudynt.json file
    local prudynt_config = utils.read_file(CONFIG.prudynt_config_path)

    -- Debug logging
    utils.log("=== STREAMER CONFIG DEBUG ===")
    if prudynt_config then
        utils.log("prudynt.json file read successfully, size: " .. #prudynt_config)
        utils.log("First 100 chars: " .. prudynt_config:sub(1, 100))
    else
        utils.log("ERROR: Failed to read " .. CONFIG.prudynt_config_path)
        prudynt_config = "{}"
    end

    -- Parse configuration for form values
    local config_values = parse_prudynt_config(prudynt_config)
    utils.log("Parsed config values count: " .. (config_values and #config_values or 0))

    local template_vars = {
        page_title = "Streamer Configuration",
        username = sess.user,

        -- Navigation state
        nav_dashboard_active = "",
        nav_preview_active = "",
        nav_motion_active = "",
        nav_streamer_active = "active",
        nav_info_active = "",
        nav_config_active = "",

        -- Streamer submenu state
        streamer_motion_active = "",
        streamer_control_active = "",
        streamer_osd_active = "",
        streamer_config_active = "active",

        -- Configuration file content
        prudynt_config = prudynt_config,

        -- Form values from config
        main_bitrate = config_values.video0_bitrate or "2048",
        sub_bitrate = config_values.video1_bitrate or "512",

        -- Video configuration (data-driven)
        current_main_resolution = config_values.video0_size or "1920x1080",
        current_sub_resolution = config_values.video1_size or "640x480",
        current_main_fps = config_values.video0_fps or "25",
        current_sub_fps = config_values.video1_fps or "15",
        current_codec = config_values.video0_codec or "h264",
        current_profile = config_values.video0_profile or "main"
    }

    local html = utils.load_template("streamer/config", template_vars)
    utils.send_html(html)
end

function parse_prudynt_config(config_content)
    local values = {}

    -- Parse JSON configuration
    local success, json_data = pcall(function()
        return utils.json_decode(config_content)
    end)

    if success and json_data then
        -- Flatten JSON structure for compatibility with existing code
        for section_name, section_data in pairs(json_data) do
            if type(section_data) == "table" then
                for key, value in pairs(section_data) do
                    values[section_name .. "_" .. key] = tostring(value)
                end
            else
                values[section_name] = tostring(section_data)
            end
        end
    else
        utils.log("Failed to parse JSON configuration: " .. (config_content or "nil"))
    end

    return values
end

function get_current_font_name()
    -- Check for custom fonts in fonts directory first
    local custom_fonts = utils.execute_command("ls " .. CONFIG.fonts_path .. "/*.ttf " .. CONFIG.fonts_path .. "/*.otf 2>/dev/null | head -1")
    if custom_fonts and custom_fonts ~= "" then
        local font_file = custom_fonts:match("([^/]+)$")
        if font_file then
            return font_file:gsub("\n", "")
        end
    end

    -- Check prudynt config for font setting using jct
    local font_path = utils.execute_command("jct " .. CONFIG.prudynt_config_path .. " get font 2>/dev/null")
    if font_path and font_path ~= "" then
        font_path = font_path:gsub("^%s+", ""):gsub("%s+$", "") -- trim whitespace
        local font_file = font_path:match("([^/]+)$")
        if font_file then
            return font_file:gsub('"', ''):gsub("'", "")
        end
    end

    return "Default system font"
end

function send_websocket_message(message)
    -- Try multiple approaches to send WebSocket message to prudynt
    local ws_port = "8089"  -- HTTP WebSocket port

    -- Method 1: Try using websocat if available
    local websocat_cmd = string.format("echo '%s' | websocat ws://localhost:%s/ 2>/dev/null", message, ws_port)
    local result = os.execute(websocat_cmd)
    if result == 0 then
        return true
    end

    -- Method 2: Try using curl with WebSocket upgrade
    local curl_cmd = string.format("curl -s --no-buffer " ..
                                 "--header 'Connection: Upgrade' " ..
                                 "--header 'Upgrade: websocket' " ..
                                 "--header 'Sec-WebSocket-Version: 13' " ..
                                 "--header 'Sec-WebSocket-Key: dGhlIHNhbXBsZSBub25jZQ==' " ..
                                 "--data '%s' " ..
                                 "http://localhost:%s/ 2>/dev/null",
                                 message, ws_port)
    result = os.execute(curl_cmd)
    if result == 0 then
        return true
    end

    -- Method 3: Try netcat with basic WebSocket frame
    -- WebSocket frame: 0x81 (FIN + text frame) + length + payload
    local payload_len = string.len(message)
    local frame_header = string.format("\\x81\\x%02x", payload_len)
    local nc_cmd = string.format("printf '%s%s' | nc localhost %s 2>/dev/null",
                                frame_header, message, ws_port)
    result = os.execute(nc_cmd)

    return result == 0
end

-- Helper function to get streamer configuration
function get_streamer_config()
    -- Try to get streamer port from environment or configuration
    local streamer_port = os.getenv("STREAMER_PORT") or CONFIG.streamer_port
    local streamer_host = os.getenv("STREAMER_HOST") or CONFIG.streamer_host

    -- Convert port to number if it's a string
    if type(streamer_port) == "string" then
        streamer_port = tonumber(streamer_port) or CONFIG.streamer_port
    end

    return {
        host = streamer_host,
        port = streamer_port
    }
end

-- Helper function to get streamer URLs
function get_streamer_urls(channel)
    channel = channel or 0  -- Default to main channel
    local streamer_config = get_streamer_config()

    return {
        image = string.format("http://%s:%d/image%d.jpg",
                             streamer_config.host,
                             streamer_config.port,
                             channel),
        mjpeg = string.format("http://%s:%d/stream%d.mjpeg",
                             streamer_config.host,
                             streamer_config.port,
                             channel)
    }
end

-- Helper function to fetch image from streamer
function fetch_streamer_image(channel)
    channel = channel or 0  -- Default to main channel
    local urls = get_streamer_urls(channel)

    -- Use curl to fetch the image
    local temp_file = "/tmp/webui_snapshot_" .. channel .. ".jpg"

    -- Clean up any existing temp file first
    os.execute("rm -f '" .. temp_file .. "'")

    local curl_cmd = string.format("curl -s -f --max-time 5 -o '%s' '%s' 2>/dev/null",
                                  temp_file, urls.image)

    -- Debug logging
    if CONFIG.debug then
        utils.log("Fetching image from: " .. urls.image)
        utils.log("Curl command: " .. curl_cmd)
    end

    local exit_code = os.execute(curl_cmd)

    -- Handle different Lua versions' os.execute return values
    local success = false
    if type(exit_code) == "number" then
        success = (exit_code == 0)
    elseif type(exit_code) == "boolean" then
        success = exit_code
    else
        -- For some Lua versions, check if file exists as fallback
        success = utils.file_exists(temp_file)
    end

    if CONFIG.debug then
        utils.log("Curl exit code: " .. tostring(exit_code) .. " (type: " .. type(exit_code) .. ")")
        utils.log("Success: " .. tostring(success))
        utils.log("Temp file exists: " .. tostring(utils.file_exists(temp_file)))
        if utils.file_exists(temp_file) then
            local file_info = io.popen("ls -la '" .. temp_file .. "'"):read("*a")
            utils.log("File info: " .. (file_info or "unknown"))
        end
    end

    if success and utils.file_exists(temp_file) then
        -- Check if file has content (not empty)
        local file = io.open(temp_file, "rb")
        if file then
            local size = file:seek("end")
            file:close()
            if size and size > 0 then
                return temp_file
            end
        end
    end

    -- Clean up failed download
    os.execute("rm -f '" .. temp_file .. "'")
    return nil
end

function handle_api_request(path, env, sess)
    local api_path = path:gsub("^/api/", "")

    if api_path == "status" then
        return api_get_status(sess)
    elseif api_path == "camera/snapshot" then
        return api_get_snapshot(sess)
    elseif api_path == "camera/mjpeg" then
        return api_get_mjpeg_stream(sess)
    elseif api_path == "camera/stream-urls" then
        return api_get_stream_urls(sess)
    elseif api_path == "camera/test-streamer" then
        return api_test_streamer(sess)
    elseif api_path == "camera/status" then
        return api_get_camera_status(sess)
    elseif api_path == "camera/ir-led" then
        return api_control_ir_led(sess, env)
    elseif api_path == "camera/white-light" then
        return api_control_white_light(sess, env)
    elseif api_path == "camera/ir-cut" then
        return api_control_ir_cut(sess, env)
    elseif api_path == "camera/mode" then
        return api_set_camera_mode(sess, env)
    elseif api_path == "camera/move" then
        return api_move_camera_new(sess, env)
    elseif api_path:match("^camera/move/") then
        local direction = api_path:match("^camera/move/(.+)")
        return api_move_camera(sess, direction)
    elseif api_path == "camera/night-vision" then
        return api_toggle_night_vision(sess)
    elseif api_path == "system/reboot" then
        return api_system_reboot(sess)
    elseif api_path == "system/restart-streaming" then
        return api_restart_streaming(sess)
    elseif api_path == "motion/config" then
        return api_motion_config(sess, env)
    elseif api_path == "camera/resolution" then
        return api_get_camera_resolution(sess)
    elseif api_path == "debug/logs" then
        return api_get_debug_logs(sess)
    elseif api_path == "debug/clear-logs" then
        return api_clear_debug_logs(sess, env)
    elseif api_path == "debug/ssl-tools" then
        return api_debug_ssl_tools(sess)
    elseif api_path == "rtsp/config" then
        return api_rtsp_config(sess)
    elseif api_path == "ssl/upload" then
        return api_ssl_upload(sess, env)
    elseif api_path == "ssl/generate-self-signed" then
        return api_ssl_generate_self_signed(sess, env)
    elseif api_path == "ssl/remove" then
        return api_ssl_remove(sess, env)
    elseif api_path == "timezones" then
        return api_get_timezones(sess)
    elseif api_path == "streamer/config" then
        return api_get_streamer_config(sess)
    elseif api_path == "streamer/update-config" then
        return api_update_streamer_config(sess, env)
    elseif api_path == "streamer/save-config" then
        return api_save_streamer_config(sess, env)
    elseif api_path == "streamer/restart" then
        return api_restart_streamer(sess)
    elseif api_path == "streamer/reset-defaults" then
        return api_reset_streamer_defaults(sess)
    elseif api_path == "streamer/upload-font" then
        return api_upload_font(sess, env)
    elseif api_path == "streamer/list-fonts" then
        return api_list_fonts(sess)
    elseif api_path == "streamer/delete-font" then
        return api_delete_font(sess, env)
    elseif api_path == "streamer/get-channel-fonts" then
        return api_get_channel_fonts(sess)
    elseif api_path == "streamer/set-channel-font" then
        return api_set_channel_font(sess, env)
    elseif api_path:match("^streamer/get%-font/") then
        local font_name = api_path:match("^streamer/get%-font/(.+)")
        return api_get_font_file(sess, font_name)
    elseif api_path == "streamer/save-osd" then
        return api_save_osd_config(sess, env)
    elseif api_path == "streamer/get-osd" then
        return api_get_osd_config(sess)
    elseif api_path == "snapshot" then
        return api_get_snapshot(sess)
    elseif api_path == "websocket-token" then
        return api_get_websocket_token(sess)
    elseif api_path == "language/list" then
        return api_language_list(sess)
    elseif api_path == "language/set" then
        return api_language_set(sess, env)
    elseif api_path == "language/download" then
        return api_language_download(sess, env)
    elseif api_path == "language/pack" then
        return api_get_current_language_pack(sess)
    elseif api_path:match("^language/pack/") then
        local lang = api_path:match("^language/pack/(.+)")
        return api_get_language_pack(sess, lang)
    elseif api_path == "language/debug" then
        return api_language_debug(sess)
    elseif api_path == "language/test-persistence" then
        return api_language_test_persistence(sess)
    elseif api_path == "language/refresh-available" then
        return api_language_refresh_available(sess)
    else
        return utils.send_json({error = "API endpoint not found"}, 404)
    end
end

function api_get_status(sess)
    local status = {
        system = utils.get_system_info(),
        camera = utils.get_camera_status(),
        timestamp = os.time()
    }

    utils.send_json(status)
end

function api_get_snapshot(sess)
    -- Parse query parameters to get channel (default to 0 for main channel)
    local query_string = os.getenv("QUERY_STRING") or ""
    local channel = 0  -- Default to main channel

    -- Parse channel parameter from query string
    for param in query_string:gmatch("[^&]+") do
        local key, value = param:match("([^=]+)=([^=]*)")
        if key == "channel" then
            channel = tonumber(value) or 0
        end
    end

    -- Ensure channel is valid (0 or 1)
    if channel ~= 0 and channel ~= 1 then
        channel = 0
    end

    -- Debug logging
    if CONFIG.debug then
        utils.log("Snapshot request - Channel: " .. channel .. ", Query: " .. query_string)
    end

    -- Try to fetch image from new streamer first
    local snapshot_path = fetch_streamer_image(channel)

    if snapshot_path then
        -- Send the image and clean up
        utils.send_file(snapshot_path, "image/jpeg")
        os.execute("rm -f '" .. snapshot_path .. "'")
    else
        -- Fallback to old method for backward compatibility
        local fallback_path = "/tmp/snapshot.jpg"
        if utils.file_exists(fallback_path) then
            utils.send_file(fallback_path, "image/jpeg")
        else
            -- Enhanced error message with debug info
            local streamer_config = get_streamer_config()
            local urls = get_streamer_urls(channel)
            local error_msg = string.format("Snapshot not available. Tried: %s (streamer: %s:%d)",
                                           urls.image, streamer_config.host, streamer_config.port)
            utils.send_error(500, error_msg)
        end
    end
end

function api_test_streamer(sess)
    -- Test streamer connectivity and return debug info
    local streamer_config = get_streamer_config()
    local test_results = {
        config = streamer_config,
        tests = {}
    }

    -- Test both channels
    for channel = 0, 1 do
        local urls = get_streamer_urls(channel)
        local temp_file = "/tmp/webui_test_" .. channel .. ".jpg"

        -- Clean up first
        os.execute("rm -f '" .. temp_file .. "'")

        local curl_cmd = string.format("curl -s -f --max-time 5 -o '%s' '%s' 2>/dev/null",
                                      temp_file, urls.image)

        local exit_code = os.execute(curl_cmd)
        local file_exists = utils.file_exists(temp_file)
        local file_size = 0

        if file_exists then
            local file = io.open(temp_file, "rb")
            if file then
                file_size = file:seek("end") or 0
                file:close()
            end
        end

        test_results.tests["channel_" .. channel] = {
            url = urls.image,
            curl_command = curl_cmd,
            exit_code = exit_code,
            exit_code_type = type(exit_code),
            file_exists = file_exists,
            file_size = file_size,
            temp_file = temp_file
        }

        -- Clean up
        os.execute("rm -f '" .. temp_file .. "'")
    end

    utils.send_json({
        success = true,
        debug = test_results
    })
end

function api_get_stream_urls(sess)
    -- Return available stream URLs from the streamer
    local streamer_config = get_streamer_config()

    local stream_urls = {
        main_channel = {
            snapshot = string.format("http://%s:%d/image0.jpg",
                                    streamer_config.host, streamer_config.port),
            mjpeg = string.format("http://%s:%d/stream0.mjpeg",
                                 streamer_config.host, streamer_config.port)
        },
        sub_channel = {
            snapshot = string.format("http://%s:%d/image1.jpg",
                                    streamer_config.host, streamer_config.port),
            mjpeg = string.format("http://%s:%d/stream1.mjpeg",
                                 streamer_config.host, streamer_config.port)
        },
        webui_endpoints = {
            snapshot_main = "/lua/api/camera/snapshot?channel=0",
            snapshot_sub = "/lua/api/camera/snapshot?channel=1",
            mjpeg_main = "/lua/api/camera/mjpeg?channel=0",
            mjpeg_sub = "/lua/api/camera/mjpeg?channel=1",
            mjpeg_main_redirect = "/lua/api/camera/mjpeg?channel=0&redirect=1",
            mjpeg_sub_redirect = "/lua/api/camera/mjpeg?channel=1&redirect=1"
        }
    }

    utils.send_json({
        success = true,
        streamer = stream_urls
    })
end

function api_get_mjpeg_stream(sess)
    -- Parse query parameters to get channel (default to 0 for main channel)
    local query_string = os.getenv("QUERY_STRING") or ""
    local channel = 0  -- Default to main channel

    -- Parse channel parameter from query string
    for param in query_string:gmatch("[^&]+") do
        local key, value = param:match("([^=]+)=([^=]*)")
        if key == "channel" then
            channel = tonumber(value) or 0
        end
    end

    -- Ensure channel is valid (0 or 1)
    if channel ~= 0 and channel ~= 1 then
        channel = 0
    end

    -- Get streamer URLs
    local urls = get_streamer_urls(channel)

    -- Check if we should redirect directly to streamer (more efficient)
    -- This can be controlled via query parameter: ?redirect=1
    local redirect_mode = false
    for param in query_string:gmatch("[^&]+") do
        local key, value = param:match("([^=]+)=([^=]*)")
        if key == "redirect" and value == "1" then
            redirect_mode = true
            break
        end
    end

    if redirect_mode then
        -- Direct redirect to streamer MJPEG stream (most efficient)
        uhttpd.send("Status: 302 Found\r\n")
        uhttpd.send("Location: " .. urls.mjpeg .. "\r\n")
        uhttpd.send("Cache-Control: no-cache\r\n")
        uhttpd.send("\r\n")
        return
    end

    -- Try to proxy the native MJPEG stream
    local curl_cmd = string.format("curl -s -f --max-time 30 '%s'", urls.mjpeg)
    local handle = io.popen(curl_cmd, "r")

    if handle then
        -- Send appropriate headers for MJPEG stream
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: multipart/x-mixed-replace; boundary=--thingino-mjpeg\r\n")
        uhttpd.send("Cache-Control: no-store, no-cache, must-revalidate, pre-check=0, post-check=0, max-age=0\r\n")
        uhttpd.send("Pragma: no-cache\r\n")
        uhttpd.send("Connection: close\r\n")
        uhttpd.send("\r\n")

        -- Stream the data directly from streamer
        local chunk_size = 8192
        while true do
            local chunk = handle:read(chunk_size)
            if not chunk or #chunk == 0 then
                break
            end
            uhttpd.send(chunk)
        end

        handle:close()
    else
        -- Fallback: try to get a single snapshot and send as MJPEG
        local snapshot_path = fetch_streamer_image(channel)

        if snapshot_path then
            uhttpd.send("Status: 200 OK\r\n")
            uhttpd.send("Content-Type: multipart/x-mixed-replace; boundary=--thingino-mjpeg\r\n")
            uhttpd.send("Cache-Control: no-store, no-cache, must-revalidate, pre-check=0, post-check=0, max-age=0\r\n")
            uhttpd.send("Pragma: no-cache\r\n")
            uhttpd.send("Connection: close\r\n")
            uhttpd.send("\r\n")

            uhttpd.send("--thingino-mjpeg\r\n")
            uhttpd.send("Content-Type: image/jpeg\r\n")

            local file = io.open(snapshot_path, "rb")
            if file then
                local content = file:read("*a")
                file:close()

                uhttpd.send("Content-Length: " .. #content .. "\r\n")
                uhttpd.send("\r\n")
                uhttpd.send(content)
                uhttpd.send("\r\n")
            end

            -- Clean up temporary file
            os.execute("rm -f '" .. snapshot_path .. "'")
        else
            -- Final fallback to old method
            local fallback_path = "/tmp/snapshot.jpg"
            if utils.file_exists(fallback_path) then
                uhttpd.send("Status: 200 OK\r\n")
                uhttpd.send("Content-Type: multipart/x-mixed-replace; boundary=--thingino-mjpeg\r\n")
                uhttpd.send("Cache-Control: no-store, no-cache, must-revalidate, pre-check=0, post-check=0, max-age=0\r\n")
                uhttpd.send("Pragma: no-cache\r\n")
                uhttpd.send("Connection: close\r\n")
                uhttpd.send("\r\n")

                uhttpd.send("--thingino-mjpeg\r\n")
                uhttpd.send("Content-Type: image/jpeg\r\n")

                local file = io.open(fallback_path, "rb")
                if file then
                    local content = file:read("*a")
                    file:close()

                    uhttpd.send("Content-Length: " .. #content .. "\r\n")
                    uhttpd.send("\r\n")
                    uhttpd.send(content)
                    uhttpd.send("\r\n")
                end
            else
                -- Send error response
                uhttpd.send("Status: 500 Internal Server Error\r\n")
                uhttpd.send("Content-Type: text/plain\r\n")
                uhttpd.send("\r\n")
                uhttpd.send("MJPEG stream not available from streamer\r\n")
            end
        end
    end
end

function api_move_camera(sess, direction)
    -- Camera movement (if supported by hardware)
    local valid_directions = {up = true, down = true, left = true, right = true}

    if not valid_directions[direction] then
        return utils.send_json({error = "Invalid direction"}, 400)
    end

    -- Execute camera movement command (placeholder)
    local cmd = string.format("motor %s 2>/dev/null", direction)
    local result = os.execute(cmd)

    if result == 0 then
        utils.send_json({message = "Camera moved " .. direction})
    else
        utils.send_json({error = "Camera movement not supported or failed"}, 500)
    end
end

function api_toggle_night_vision(sess)
    -- Toggle night vision/IR LEDs
    local ir_status_file = "/tmp/ir_status"
    local current_status = utils.file_exists(ir_status_file)

    if current_status then
        -- Turn off IR
        os.execute("gpio clear ir_led 2>/dev/null")
        os.remove(ir_status_file)
        utils.send_json({message = "Night vision disabled", status = "off"})
    else
        -- Turn on IR
        os.execute("gpio set ir_led 2>/dev/null")
        local file = io.open(ir_status_file, "w")
        if file then
            file:write("on")
            file:close()
        end
        utils.send_json({message = "Night vision enabled", status = "on"})
    end
end

function api_restart_streaming(sess)
    -- Restart the streaming service
    local result = os.execute("/etc/init.d/S95prudynt restart 2>/dev/null")

    if result == 0 then
        utils.send_json({message = "Streaming service restarted"})
    else
        utils.send_json({error = "Failed to restart streaming service"}, 500)
    end
end

function api_system_reboot(sess)
    -- Schedule reboot
    os.execute("(sleep 2; reboot) &")
    utils.send_json({message = "System reboot initiated"})
end

function api_get_camera_status(sess)
    -- Mock camera status for testing
    local status = {
        success = true,
        ir850_enabled = false,
        ir940_enabled = false,
        white_light_enabled = false,
        ir_cut_enabled = true,
        camera_mode = "color"
    }
    utils.send_json(status)
end

function api_get_timezones(sess)
    -- Serve timezone data from /usr/share/tz.json.gz
    local timezone_file = "/usr/share/tz.json.gz"

    -- Check if timezone file exists
    if not utils.file_exists(timezone_file) then
        utils.log("Timezone file not found: " .. timezone_file)
        return utils.send_json({error = "Timezone data not available"}, 404)
    end

    -- Read and decompress timezone data
    local cmd = "zcat " .. timezone_file
    local handle = io.popen(cmd)
    if not handle then
        utils.log("Failed to execute zcat command")
        return utils.send_json({error = "Failed to read timezone data"}, 500)
    end

    local timezone_data = handle:read("*a")
    handle:close()

    if not timezone_data or timezone_data == "" then
        utils.log("Empty timezone data")
        return utils.send_json({error = "Empty timezone data"}, 500)
    end

    -- Send raw JSON data with proper headers
    uhttpd.send("Status: 200 OK\r\n")
    uhttpd.send("Content-Type: application/json\r\n")
    uhttpd.send("Cache-Control: public, max-age=86400\r\n") -- Cache for 24 hours
    uhttpd.send("Access-Control-Allow-Origin: *\r\n")
    uhttpd.send("Content-Length: " .. #timezone_data .. "\r\n")
    uhttpd.send("\r\n")
    uhttpd.send(timezone_data)
end

function api_control_ir_led(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Simple response for testing
    uhttpd.send("Status: 200 OK\r\n")
    uhttpd.send("Content-Type: application/json\r\n")
    uhttpd.send("\r\n")
    uhttpd.send('{"success": true, "message": "IR LED control received"}')
end

function api_control_white_light(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local action = post_data.action or ""

    -- Mock white light control
    utils.send_json({
        success = true,
        message = "White light " .. action,
        action = action
    })
end

function api_control_ir_cut(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local action = post_data.action or ""

    -- Mock IR cut filter control
    utils.send_json({
        success = true,
        message = "IR cut filter " .. action,
        action = action
    })
end

function api_set_camera_mode(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local mode = post_data.mode or ""

    -- Mock camera mode control
    utils.send_json({
        success = true,
        message = "Camera mode set to " .. mode,
        mode = mode
    })
end

function api_move_camera_new(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local direction = post_data.direction or ""
    local pan = post_data.pan or 0
    local tilt = post_data.tilt or 0
    local home = post_data.home or false

    -- Mock camera movement control
    utils.send_json({
        success = true,
        message = "Camera moved " .. direction,
        direction = direction,
        pan = pan,
        tilt = tilt,
        home = home
    })
end

function api_get_camera_resolution(sess)
    -- Get camera resolution from configuration
    local camera_config = config.get_camera_config()
    local resolution = camera_config.resolution or "1920x1080"

    -- Parse resolution string (e.g., "1920x1080")
    local width, height = resolution:match("(%d+)x(%d+)")
    width = tonumber(width) or 1920
    height = tonumber(height) or 1080

    -- Also try to get sensor dimensions as fallback
    local sensor_width = nil
    local sensor_height = nil

    -- Try to read from sensor proc files
    local width_file = io.open("/proc/jz/sensor/width", "r")
    if width_file then
        local w = width_file:read("*line")
        width_file:close()
        if w and w ~= "" then
            sensor_width = tonumber(w)
        end
    end

    local height_file = io.open("/proc/jz/sensor/height", "r")
    if height_file then
        local h = height_file:read("*line")
        height_file:close()
        if h and h ~= "" then
            sensor_height = tonumber(h)
        end
    end

    -- Use sensor dimensions if available, otherwise use config
    local final_width = sensor_width or width
    local final_height = sensor_height or height

    utils.send_json({
        success = true,
        resolution = {
            width = final_width,
            height = final_height,
            string = final_width .. "x" .. final_height
        },
        source = sensor_width and "sensor" or "config"
    })
end

function api_motion_config(sess, env)
    if env.REQUEST_METHOD == "GET" then
        -- Load ROI zones configuration
        local config_file = CONFIG.motion_config_path
        local file = io.open(config_file, "r")
        local config = {}

        if file then
            local content = file:read("*a")
            file:close()

            -- Send the raw JSON content and let frontend parse it
            if content and content ~= "" then
                -- Just send the raw content, don't try to parse it
                uhttpd.send("Status: 200 OK\r\n")
                uhttpd.send("Content-Type: application/json\r\n")
                uhttpd.send("Cache-Control: no-store\r\n\r\n")
                uhttpd.send('{"success":true,"config":' .. content .. '}')
                return
            end
        end

        utils.send_json({
            success = true,
            config = config
        })
    elseif env.REQUEST_METHOD == "POST" then
        -- Save ROI zones configuration - handle raw JSON to avoid parsing issues
        local content_length = tonumber(env.CONTENT_LENGTH or "0")
        local config_file = CONFIG.motion_config_path

        if content_length <= 0 then
            utils.send_json({
                success = false,
                error = "No data received"
            }, 400)
            return
        end

        -- Read raw JSON data directly without parsing
        local raw_json = nil
        local success, data = pcall(function()
            return io.read(content_length)
        end)

        if success and data and type(data) == "string" and #data > 0 then
            raw_json = data
        else
            utils.send_json({
                success = false,
                error = "Failed to read POST data"
            }, 400)
            return
        end

        -- Write raw JSON directly to file
        utils.log("Saving ROI zones configuration to " .. config_file)
        local file = io.open(config_file, "w")
        if file then
            file:write(raw_json)
            file:close()
            utils.log("ROI zones configuration saved successfully")

            utils.send_json({
                success = true,
                message = "ROI zones configuration saved to persistent storage"
            })
        else
            utils.log("Failed to save ROI zones configuration file")
            utils.send_json({
                success = false,
                error = "Failed to save configuration file"
            }, 500)
        end
    else
        utils.send_json({error = "Method not allowed"}, 405)
    end
end

function handle_logout(env)
    local sess = session.get(env)
    if sess then
        session.destroy(sess.id)
    end

    utils.send_redirect("/lua/login", {
        ["Set-Cookie"] = "session_id=; expires=Thu, 01 Jan 1970 00:00:00 GMT; path=/"
    })
end

function serve_static_file(path)
    local file_path = "/var/www" .. path
    if utils.file_exists(file_path) then
        local content_type = utils.get_content_type(path)
        utils.send_file(file_path, content_type)
    else
        utils.send_error(404, "File not found")
    end
end

function api_rtsp_config(sess)
    -- Use jct command to get RTSP configuration
    local function get_prudynt_config(key)
        local cmd = string.format("jct %s get %s 2>/dev/null", CONFIG.prudynt_config_path, key)
        local result = utils.execute_command(cmd)
        if result then
            result = result:match("^%s*(.-)%s*$") -- trim whitespace
            -- Remove quotes if present
            result = result:gsub('^"(.*)"$', '%1')
            if result and result ~= "" then
                return result
            end
        end
        return nil
    end

    -- Fallback method using jct
    local function get_config_fallback(key)
        local cmd = string.format("jct %s get %s 2>/dev/null", CONFIG.prudynt_config_path, key)
        local result = utils.execute_command(cmd)
        if result then
            result = result:match("^%s*(.-)%s*$") -- trim whitespace
            -- Remove quotes if present
            result = result:gsub('^"(.*)"$', '%1')
            if result and result ~= "" then
                return result
            end
        end
        return nil
    end

    -- Get camera IP address
    local function get_camera_ip()
        -- Try multiple methods to get IP
        local ip_commands = {
            "ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}'",
            "hostname -I | awk '{print $1}'",
            "ifconfig | grep 'inet addr:' | grep -v '127.0.0.1' | head -1 | awk '{print $2}' | cut -d: -f2"
        }

        for _, cmd in ipairs(ip_commands) do
            local result = utils.execute_command(cmd)
            if result then
                result = result:match("^%s*(.-)%s*$") -- trim whitespace
                if result and result ~= "" and result:match("^%d+%.%d+%.%d+%.%d+$") then
                    return result
                end
            end
        end
        return "camera-ip"
    end

    local camera_ip = get_camera_ip()

    -- Extract RTSP configuration using jct
    local rtsp_username = get_prudynt_config("rtsp.username") or get_config_fallback("username") or "thingino"
    local rtsp_password = get_prudynt_config("rtsp.password") or get_config_fallback("password") or "thingino"
    local rtsp_port = get_prudynt_config("rtsp.port") or "554"
    local main_endpoint = get_prudynt_config("stream0.rtsp_endpoint") or "ch0"
    local sub_endpoint = get_prudynt_config("stream1.rtsp_endpoint") or "ch1"

    -- Remove quotes from endpoints if present
    main_endpoint = main_endpoint:gsub('^"(.*)"$', '%1')
    sub_endpoint = sub_endpoint:gsub('^"(.*)"$', '%1')

    -- Get stream parameters
    local main_width = get_prudynt_config("stream0.width") or "1920"
    local main_height = get_prudynt_config("stream0.height") or "1080"
    local main_fps = get_prudynt_config("stream0.fps") or "25"
    local main_bitrate = get_prudynt_config("stream0.bitrate") or "2048"

    local sub_width = get_prudynt_config("stream1.width") or "640"
    local sub_height = get_prudynt_config("stream1.height") or "360"
    local sub_fps = get_prudynt_config("stream1.fps") or "15"
    local sub_bitrate = get_prudynt_config("stream1.bitrate") or "512"

    local rtsp_config = {
        camera_ip = camera_ip,
        rtsp_username = rtsp_username,
        rtsp_password = rtsp_password,
        rtsp_port = rtsp_port,
        main_stream = main_endpoint,
        sub_stream = sub_endpoint,
        main_stream_params = {
            resolution = main_width .. "x" .. main_height,
            fps = main_fps,
            bitrate = main_bitrate .. " kbps"
        },
        sub_stream_params = {
            resolution = sub_width .. "x" .. sub_height,
            fps = sub_fps,
            bitrate = sub_bitrate .. " kbps"
        }
    }

    -- Build RTSP URLs
    rtsp_config.main_stream_url = string.format("rtsp://%s:%s@%s:%s/%s",
        rtsp_config.rtsp_username,
        rtsp_config.rtsp_password,
        rtsp_config.camera_ip,
        rtsp_config.rtsp_port,
        rtsp_config.main_stream)

    rtsp_config.sub_stream_url = string.format("rtsp://%s:%s@%s:%s/%s",
        rtsp_config.rtsp_username,
        rtsp_config.rtsp_password,
        rtsp_config.camera_ip,
        rtsp_config.rtsp_port,
        rtsp_config.sub_stream)

    utils.send_json({
        success = true,
        config = rtsp_config
    })
end

function api_get_debug_logs(sess)
    -- Serve the debug log file
    local log_file = "/tmp/webui-lua.log"

    if utils.file_exists(log_file) then
        utils.send_file(log_file, "text/plain")
    else
        utils.send_error(404, "Debug log file not found")
    end
end

function api_clear_debug_logs(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local log_file = "/tmp/webui-lua.log"

    -- Clear the log file
    local file = io.open(log_file, "w")
    if file then
        file:write("")
        file:close()

        utils.log("Debug logs cleared by user: " .. (sess.user or "unknown"))

        utils.send_json({
            success = true,
            message = "Debug logs cleared successfully"
        })
    else
        utils.send_json({
            success = false,
            error = "Failed to clear debug logs"
        }, 500)
    end
end

function api_debug_ssl_tools(sess)
    -- Check what SSL/certificate tools are available on the camera
    local tools = {
        "openssl", "ssl_server2", "cert_app", "wolfssl-certgen", "wolfssl-certgen-native",
        "openssl-certgen", "mbedtls-certgen", "mbedtls-certgen-native", "mbedtls_ssl_server2", "gnutls-cli", "certtool"
    }

    local available_tools = {}
    local cert_info = {}

    for _, tool in ipairs(tools) do
        local result = utils.execute_command("which " .. tool .. " 2>/dev/null")
        if result and result ~= "" then
            available_tools[tool] = result:gsub("^%s*(.-)%s*$", "%1") -- trim
        else
            available_tools[tool] = false
        end
    end

    -- Test certificate parsing with available tools
    local cert_file = CONFIG.ssl_cert_path
    if utils.file_exists(cert_file) then
        -- Try openssl if available
        if available_tools.openssl then
            local openssl_output = utils.execute_command("openssl x509 -in " .. cert_file .. " -text -noout 2>/dev/null")
            if openssl_output then
                cert_info.openssl_available = true
                cert_info.openssl_output = openssl_output:sub(1, 500) .. "..." -- truncate for display

                -- Extract specific fields
                local subject = utils.execute_command("openssl x509 -in " .. cert_file .. " -subject -noout 2>/dev/null")
                local expires = utils.execute_command("openssl x509 -in " .. cert_file .. " -enddate -noout 2>/dev/null")
                cert_info.openssl_subject = subject
                cert_info.openssl_expires = expires
            else
                cert_info.openssl_available = false
            end
        end

        -- Try wolfssl-certgen-native with JSON output if available
        if available_tools["wolfssl-certgen-native"] then
            local wolfssl_json_output = utils.execute_command("wolfssl-certgen-native -i " .. cert_file .. " --json 2>/dev/null")
            cert_info.wolfssl_certgen_native_available = true
            cert_info.wolfssl_json_output = wolfssl_json_output and wolfssl_json_output:sub(1, 1000) .. "..." or "Failed"
        end

        -- Try ssl_server2 if available
        if available_tools["ssl_server2"] then
            local ssl_server2_output = utils.execute_command("ssl_server2 crt_file=" .. cert_file .. " exchanges=0 verify=0 2>/dev/null")
            cert_info.ssl_server2_available = true
            cert_info.ssl_server2_output = ssl_server2_output and ssl_server2_output:sub(1, 1000) .. "..." or "Failed"
        end

        -- Test the actual certificate parsing function
        local cert_content = utils.read_file(cert_file)
        if cert_content then
            local parsed_info = utils.get_certificate_info(cert_content)
            cert_info.parsed_info = parsed_info
        end
    else
        cert_info.cert_file_exists = false
    end

    utils.send_json({
        success = true,
        available_tools = available_tools,
        cert_info = cert_info,
        cert_file = cert_file
    })
end

-- SSL Certificate Management API Functions
function api_ssl_upload(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Create SSL directories if they don't exist
    os.execute("mkdir -p /etc/ssl/certs /etc/ssl/private")

    -- Parse multipart form data
    local multipart_data, error_msg = utils.parse_multipart_data(env)
    if not multipart_data then
        return utils.send_json({
            success = false,
            error = "Failed to parse upload data: " .. (error_msg or "Unknown error")
        }, 400)
    end

    local files = multipart_data.files
    if not files.certificate or not files.private_key then
        return utils.send_json({
            success = false,
            error = "Both certificate and private key files are required"
        }, 400)
    end

    local cert_content = files.certificate.content
    local key_content = files.private_key.content

    -- Validate certificate format
    local cert_valid, cert_error = utils.validate_ssl_certificate(cert_content)
    if not cert_valid then
        return utils.send_json({
            success = false,
            error = "Certificate validation failed: " .. cert_error
        }, 400)
    end

    -- Validate private key format
    local key_valid, key_error = utils.validate_ssl_private_key(key_content)
    if not key_valid then
        return utils.send_json({
            success = false,
            error = "Private key validation failed: " .. key_error
        }, 400)
    end

    -- Verify certificate and key match
    local match_valid, match_error = utils.verify_cert_key_match(cert_content, key_content)
    if not match_valid then
        return utils.send_json({
            success = false,
            error = "Certificate and key validation failed: " .. match_error
        }, 400)
    end

    -- Get certificate information
    local cert_info = utils.get_certificate_info(cert_content)

    -- Save certificate and key files
    -- Backup existing files
    os.execute("cp " .. CONFIG.ssl_cert_path .. " " .. CONFIG.ssl_cert_path .. ".backup 2>/dev/null")
    os.execute("cp " .. CONFIG.ssl_key_path .. " " .. CONFIG.ssl_key_path .. ".backup 2>/dev/null")

    -- Write new certificate
    local cert_file = io.open(CONFIG.ssl_cert_path, "w")
    if not cert_file then
        return utils.send_json({
            success = false,
            error = "Failed to write certificate file"
        }, 500)
    end
    cert_file:write(cert_content)
    cert_file:close()

    -- Write new private key
    local key_file = io.open(CONFIG.ssl_key_path, "w")
    if not key_file then
        -- Restore backup certificate
        os.execute("mv " .. CONFIG.ssl_cert_path .. ".backup " .. CONFIG.ssl_cert_path .. " 2>/dev/null")
        return utils.send_json({
            success = false,
            error = "Failed to write private key file"
        }, 500)
    end
    key_file:write(key_content)
    key_file:close()

    -- Set proper permissions
    os.execute("chmod 644 " .. CONFIG.ssl_cert_path)
    os.execute("chmod 600 " .. CONFIG.ssl_key_path)

    -- Remove backup files on success
    os.execute("rm -f " .. CONFIG.ssl_cert_path .. ".backup " .. CONFIG.ssl_key_path .. ".backup")

    -- Restart uhttpd to load new certificate using robust restart
    utils.log("Restarting uhttpd service to apply new SSL certificate...")
    local restart_success = utils.restart_uhttpd()

    local response = {
        success = true,
        message = restart_success and "SSL certificate uploaded successfully. uhttpd service restarted." or "SSL certificate uploaded successfully. uhttpd restart may have failed."
    }

    if cert_info then
        response.certificate_info = {
            common_name = cert_info.common_name,
            expires = cert_info.expires,
            issuer = cert_info.issuer
        }
    end

    utils.send_json(response)
end

function api_ssl_generate_self_signed(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Create SSL directories
    os.execute("mkdir -p /etc/ssl/certs /etc/ssl/private")

    local hostname = utils.get_hostname() or "thingino"

    -- Backup existing files
    os.execute("cp " .. CONFIG.ssl_cert_path .. " " .. CONFIG.ssl_cert_path .. ".backup 2>/dev/null")
    os.execute("cp " .. CONFIG.ssl_key_path .. " " .. CONFIG.ssl_key_path .. ".backup 2>/dev/null")

    -- Try available certificate generators
    local success = false
    local error_msg = ""

    -- Try wolfssl-certgen first (if available)
    if utils.command_exists("wolfssl-certgen") then
        local wolfssl_cmd = string.format([[
            wolfssl-certgen -h "%s.local" -c "%s" -k "%s" -d 3650 2>&1
        ]], hostname, CONFIG.ssl_cert_path, CONFIG.ssl_key_path)

        local handle = io.popen(wolfssl_cmd)
        local result_output = handle:read("*a")
        local result = handle:close()

        if result then
            success = true
        else
            error_msg = "wolfSSL certificate generation failed: " .. (result_output or "Unknown error")
        end
    -- Try mbedtls-certgen as second option (if available)
    elseif utils.command_exists("mbedtls-certgen") then
        local mbedtls_cmd = string.format([[
            mbedtls-certgen -h "%s.local" -c "%s" -k "%s" -d 3650 -s 256 -t ecdsa 2>&1
        ]], hostname, CONFIG.ssl_cert_path, CONFIG.ssl_key_path)

        local handle = io.popen(mbedtls_cmd)
        local result_output = handle:read("*a")
        local result = handle:close()

        if result then
            success = true
        else
            error_msg = "mbedTLS certificate generation failed: " .. (result_output or "Unknown error")
        end
    -- Try openssl-certgen as fallback (if available)
    elseif utils.command_exists("openssl-certgen") then
        local openssl_cmd = string.format([[
            openssl-certgen -h "%s.local" -c "%s" -k "%s" -d 3650 2>&1
        ]], hostname, CONFIG.ssl_cert_path, CONFIG.ssl_key_path)

        local handle = io.popen(openssl_cmd)
        local result_output = handle:read("*a")
        local result = handle:close()

        if result then
            success = true
        else
            error_msg = "OpenSSL certificate generation failed: " .. (result_output or "Unknown error")
        end
    else
        error_msg = "No certificate generator available (neither wolfssl-certgen nor openssl-certgen found)"
    end

    if success then
        -- Set proper permissions
        os.execute("chmod 600 " .. CONFIG.ssl_key_path)
        os.execute("chmod 644 " .. CONFIG.ssl_cert_path)

        -- Remove backup files on success
        os.execute("rm -f " .. CONFIG.ssl_cert_path .. ".backup " .. CONFIG.ssl_key_path .. ".backup")

        -- Restart uhttpd to load new certificate using robust restart
        utils.log("Restarting uhttpd service to apply new self-signed SSL certificate...")
        local restart_success = utils.restart_uhttpd()

        -- Get certificate info for response
        local cert_content = utils.read_file(CONFIG.ssl_cert_path)
        local cert_info = utils.get_certificate_info(cert_content)

        local response = {
            success = true,
            message = restart_success and "Self-signed SSL certificate generated successfully. uhttpd service restarted." or "Self-signed SSL certificate generated successfully. uhttpd restart may have failed."
        }

        if cert_info then
            response.certificate_info = {
                common_name = cert_info.common_name,
                expires = cert_info.expires,
                issuer = cert_info.issuer
            }
        end

        utils.send_json(response)
    else
        -- Restore backup files on failure
        os.execute("mv " .. CONFIG.ssl_cert_path .. ".backup " .. CONFIG.ssl_cert_path .. " 2>/dev/null")
        os.execute("mv " .. CONFIG.ssl_key_path .. ".backup " .. CONFIG.ssl_key_path .. " 2>/dev/null")

        utils.send_json({
            success = false,
            error = error_msg ~= "" and error_msg or "Failed to generate SSL certificate"
        }, 500)
    end
end

-- Streamer API functions
function api_get_streamer_config(sess)
    local prudynt_config = utils.read_file(CONFIG.prudynt_config_path)
    if prudynt_config then
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: text/plain\r\n")
        uhttpd.send("Content-Length: " .. #prudynt_config .. "\r\n")
        uhttpd.send("\r\n")
        uhttpd.send(prudynt_config)
    else
        utils.send_json({error = "Failed to read configuration file"}, 500)
    end
end

function api_update_streamer_config(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local data = utils.json_decode(post_data)

    if not data or not data.section or not data.key or not data.value then
        return utils.send_json({error = "Missing required parameters"}, 400)
    end

    -- Update configuration using jct
    -- jct handles values without needing extra quotes
    local cmd = string.format("jct %s set %s.%s %s", CONFIG.prudynt_config_path, data.section, data.key, data.value)
    local result = os.execute(cmd)

    if result == 0 then
        utils.send_json({success = true, message = "Configuration updated"})
    else
        utils.send_json({error = "Failed to update configuration"}, 500)
    end
end

function api_save_streamer_config(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Read raw POST data for plain text content
    local content_length = tonumber(env.CONTENT_LENGTH or "0")
    local post_data = ""

    if content_length > 0 then
        local success, data = pcall(function()
            return io.read(content_length)
        end)
        if success and data and type(data) == "string" then
            post_data = data
        else
            return utils.send_json({error = "Failed to read POST data"}, 400)
        end
    else
        return utils.send_json({error = "No data received"}, 400)
    end

    -- Write the new configuration to file
    local file = io.open(CONFIG.prudynt_config_path, "w")
    if file then
        file:write(post_data)
        file:close()
        utils.send_json({success = true, message = "Configuration saved"})
    else
        utils.send_json({error = "Failed to write configuration file"}, 500)
    end
end

function api_restart_streamer(sess)
    local result = os.execute("/etc/init.d/S95prudynt restart 2>/dev/null")

    if result == 0 then
        utils.send_json({success = true, message = "Streaming service restarted"})
    else
        utils.send_json({error = "Failed to restart streaming service"}, 500)
    end
end

function api_reset_streamer_defaults(sess)
    -- This would restore default prudynt.json - implementation depends on how defaults are stored
    utils.send_json({error = "Reset to defaults not implemented yet"}, 501)
end

function api_upload_font(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Parse multipart form data for file upload
    local upload_data, error_msg = utils.parse_multipart_data(env)
    if not upload_data then
        return utils.send_json({error = "Failed to parse upload data: " .. (error_msg or "Unknown error")}, 400)
    end

    local font_file = upload_data.files.font_file
    if not font_file then
        return utils.send_json({error = "No font file uploaded"}, 400)
    end

    -- Validate file extension
    local filename = font_file.filename:lower()
    if not (filename:match("%.ttf$") or filename:match("%.otf$")) then
        return utils.send_json({error = "Invalid file type. Only TTF and OTF fonts are supported"}, 400)
    end

    -- Validate file size (max 5MB)
    if font_file.size > 5 * 1024 * 1024 then
        return utils.send_json({error = "Font file too large. Maximum size is 5MB"}, 400)
    end

    -- Create fonts directory if it doesn't exist
    os.execute("mkdir -p " .. CONFIG.fonts_path)

    -- Save font file
    local font_path = CONFIG.fonts_path .. "/" .. font_file.filename
    local file = io.open(font_path, "wb")
    if not file then
        return utils.send_json({error = "Failed to create font file"}, 500)
    end

    file:write(font_file.content)
    file:close()

    -- TODO: Update font cache for the custom directory (temporarily disabled to prevent session issues)
    -- os.execute("fc-cache -f " .. CONFIG.fonts_path .. " 2>/dev/null || true")

    utils.send_json({
        success = true,
        message = "Font uploaded successfully",
        filename = font_file.filename,
        path = font_path,
        size = font_file.size
    })
end

function api_list_fonts(sess)
    local fonts = {}

    -- List all font files in fonts directory
    local font_files = utils.execute_command("ls -la " .. CONFIG.fonts_path .. "/*.ttf " .. CONFIG.fonts_path .. "/*.otf 2>/dev/null")

    if font_files and font_files ~= "" then
        for line in font_files:gmatch("[^\n]+") do
            -- Parse ls output: permissions links owner group size month day time filename
            local size, filename = line:match("%S+%s+%S+%s+%S+%s+%S+%s+(%d+)%s+%S+%s+%S+%s+%S+%s+(.+)")
            if size and filename then
                -- Extract just the filename without path
                local font_name = filename:match("([^/]+)$")
                if font_name then
                    table.insert(fonts, {
                        name = font_name,
                        size = tonumber(size) or 0,
                        path = filename
                    })
                end
            end
        end
    end

    utils.send_json({
        success = true,
        fonts = fonts,
        count = #fonts
    })
end

function api_delete_font(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    if not post_data then
        return utils.send_json({error = "Failed to read POST data"}, 400)
    end

    local font_name = post_data.font_name

    if not font_name or font_name == "" then
        return utils.send_json({error = "Font name is required"}, 400)
    end

    -- Validate font name (security check)
    if font_name:match("[/\\]") or font_name:match("%.%.") then
        return utils.send_json({error = "Invalid font name"}, 400)
    end

    local font_path = CONFIG.fonts_path .. "/" .. font_name

    -- Check if file exists
    if not utils.file_exists(font_path) then
        return utils.send_json({error = "Font file not found"}, 404)
    end

    -- Delete the font file
    local result = os.execute("rm -f '" .. font_path:gsub("'", "'\"'\"'") .. "'")

    -- Handle different Lua versions: result can be boolean (true/false) or number (0/non-zero)
    local success = (result == true) or (result == 0)

    if success then
        -- TODO: Update font cache (temporarily disabled to prevent session issues)
        -- os.execute("fc-cache -f " .. CONFIG.fonts_path .. " 2>/dev/null || true")

        return utils.send_json({
            success = true,
            message = "Font deleted successfully",
            font_name = font_name
        })
    else
        return utils.send_json({error = "Failed to delete font file"}, 500)
    end
end

function api_get_channel_fonts(sess)
    local config_path = "/etc/prudynt.json"
    local ch0_font = ""
    local ch1_font = ""

    -- Get stream0.font
    local cmd = string.format("jct %s get stream0.font 2>/dev/null", config_path)
    local handle = io.popen(cmd)
    if handle then
        local value = handle:read("*line")
        handle:close()
        if value and value ~= "" then
            -- Remove quotes if present
            ch0_font = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
        end
    end

    -- Get stream1.font
    cmd = string.format("jct %s get stream1.font 2>/dev/null", config_path)
    handle = io.popen(cmd)
    if handle then
        local value = handle:read("*line")
        handle:close()
        if value and value ~= "" then
            -- Remove quotes if present
            ch1_font = value:gsub('^"(.*)"$', '%1'):gsub("^'(.*)'$", '%1')
        end
    end

    return utils.send_json({
        success = true,
        ch0_font = ch0_font,
        ch1_font = ch1_font
    })
end

function api_set_channel_font(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    local channel = tonumber(post_data.channel)
    local font_name = post_data.font_name or ""

    if not channel or (channel ~= 0 and channel ~= 1) then
        return utils.send_json({error = "Invalid channel. Must be 0 or 1"}, 400)
    end

    -- Validate font exists if not empty
    if font_name ~= "" then
        local font_path = CONFIG.fonts_path .. "/" .. font_name
        if not utils.file_exists(font_path) then
            return utils.send_json({error = "Font file not found"}, 404)
        end
    end

    -- Save the font selection using jct
    local config_path = "/etc/prudynt.json"
    local stream_key = "stream" .. channel .. ".font"
    local value = font_name == "" and '""' or ("'" .. font_name .. "'")

    -- Helper function to safely execute jct commands
    local function safe_jct_set(key, value)
        local cmd = "jct " .. config_path .. " set " .. key .. " " .. value
        local handle = io.popen(cmd .. " 2>&1")
        if handle then
            local result = handle:read("*all")
            local success = handle:close()
            return success, result
        end
        return false, "Failed to execute command"
    end

    local success, result = safe_jct_set(stream_key, value)

    if success then
        return utils.send_json({
            success = true,
            message = "Font selection saved successfully",
            channel = channel,
            font_name = font_name,
            font_path = font_name ~= "" and (CONFIG.fonts_path .. "/" .. font_name) or ""
        })
    else
        return utils.send_json({
            success = false,
            error = "Failed to save font selection: " .. (result or "unknown error")
        }, 500)
    end
end

function api_get_font_file(sess, font_name)
    -- URL decode the font name
    font_name = utils.url_decode(font_name)

    -- Validate font name (security check)
    if font_name:match("[/\\]") or font_name:match("%.%.") then
        return utils.send_error(400, "Invalid font name")
    end

    local font_path = CONFIG.fonts_path .. "/" .. font_name

    -- Check if file exists
    if not utils.file_exists(font_path) then
        return utils.send_error(404, "Font file not found")
    end

    -- Basic font file validation - check file size and magic bytes
    local file = io.open(font_path, "rb")
    if not file then
        return utils.send_error(500, "Cannot read font file")
    end

    -- Read first few bytes to check for valid font signatures
    local header = file:read(4)
    file:close()

    if not header or #header < 4 then
        return utils.send_error(400, "Invalid font file - too small")
    end

    -- Check for valid font signatures
    local is_valid_font = false
    -- TTF/OTF signatures
    if header == "\x00\x01\x00\x00" or  -- TTF
       header == "OTTO" or              -- OTF
       header == "true" or              -- TTF (Mac)
       header == "typ1" then            -- Type 1
        is_valid_font = true
    end

    if not is_valid_font then
        return utils.send_error(400, "Invalid font file format")
    end

    -- Determine content type based on extension
    local content_type = "application/octet-stream"
    if font_name:lower():match("%.ttf$") then
        content_type = "font/ttf"
    elseif font_name:lower():match("%.otf$") then
        content_type = "font/otf"
    end

    -- Send the font file with proper headers
    utils.send_file(font_path, content_type)
end

function api_get_websocket_token(sess)
    -- Read the WebSocket token from the file
    local token_file = "/var/run/prudynt_websocket_token"
    local token = utils.read_file(token_file)

    if token then
        token = token:gsub("\n", ""):gsub("\r", "") -- Remove newlines
        return utils.send_json({
            success = true,
            token = token
        })
    else
        return utils.send_json({
            success = false,
            error = "WebSocket token not available"
        }, 500)
    end
end

function api_ssl_remove(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    -- Remove certificate files
    os.execute("rm -f " .. CONFIG.ssl_cert_path .. " " .. CONFIG.ssl_key_path)

    return utils.send_json({
        success = true,
        message = "SSL certificate removed successfully"
    })
end

function api_save_osd_config(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    if not post_data then
        return utils.send_json({error = "Failed to read POST data"}, 400)
    end

    local config_path = "/etc/prudynt.json"
    local saved_settings = {}
    local errors = {}

    -- Helper function to safely execute jct commands
    local function safe_jct_set(key, value)
        local cmd = "jct " .. config_path .. " set " .. key .. " " .. value
        local handle = io.popen(cmd .. " 2>&1")
        if handle then
            local result = handle:read("*all")
            local success = handle:close()
            return success, result
        end
        return false, "Failed to execute command"
    end

    -- Try to save a few key settings using the safer approach (jct set)
    if post_data.osd_enabled then
        local value = post_data.osd_enabled == "true" and "true" or "false"
        local success, result = safe_jct_set("osd.enabled", value)
        if success then
            saved_settings.osd_enabled = value
        else
            table.insert(errors, "osd.enabled: " .. (result or "unknown error"))
        end
    end

    if post_data.timestamp_enabled then
        local value = post_data.timestamp_enabled == "true" and "true" or "false"
        local success, result = safe_jct_set("osd.timestamp.enabled", value)
        if success then
            saved_settings.timestamp_enabled = value
        else
            table.insert(errors, "osd.timestamp.enabled: " .. (result or "unknown error"))
        end
    end

    if post_data.camera_title and post_data.camera_title ~= "" then
        local escaped_value = "'" .. post_data.camera_title:gsub("'", "'\"'\"'") .. "'"
        local success, result = safe_jct_set("osd.title.text", escaped_value)
        if success then
            saved_settings.camera_title = post_data.camera_title
        else
            table.insert(errors, "osd.title.text: " .. (result or "unknown error"))
        end
    end

    -- Save text appearance settings
    if post_data.text_size then
        local success, result = safe_jct_set("osd.text.size", post_data.text_size)
        if success then
            saved_settings.text_size = post_data.text_size
        else
            table.insert(errors, "osd.text.size: " .. (result or "unknown error"))
        end
    end

    if post_data.text_color then
        local success, result = safe_jct_set("osd.text.color", post_data.text_color)
        if success then
            saved_settings.text_color = post_data.text_color
        else
            table.insert(errors, "osd.text.color: " .. (result or "unknown error"))
        end
    end

    if post_data.text_background then
        local success, result = safe_jct_set("osd.text.background", post_data.text_background)
        if success then
            saved_settings.text_background = post_data.text_background
        else
            table.insert(errors, "osd.text.background: " .. (result or "unknown error"))
        end
    end

    if post_data.text_opacity then
        local success, result = safe_jct_set("osd.text.opacity", post_data.text_opacity)
        if success then
            saved_settings.text_opacity = post_data.text_opacity
        else
            table.insert(errors, "osd.text.opacity: " .. (result or "unknown error"))
        end
    end

    -- Save timestamp settings
    if post_data.timestamp_format then
        local success, result = safe_jct_set("osd.timestamp.format", post_data.timestamp_format)
        if success then
            saved_settings.timestamp_format = post_data.timestamp_format
        else
            table.insert(errors, "osd.timestamp.format: " .. (result or "unknown error"))
        end
    end

    if post_data.timestamp_position then
        local success, result = safe_jct_set("osd.timestamp.position", post_data.timestamp_position)
        if success then
            saved_settings.timestamp_position = post_data.timestamp_position
        else
            table.insert(errors, "osd.timestamp.position: " .. (result or "unknown error"))
        end
    end

    if post_data.timestamp_x_offset then
        local success, result = safe_jct_set("osd.timestamp.x_offset", post_data.timestamp_x_offset)
        if success then
            saved_settings.timestamp_x_offset = post_data.timestamp_x_offset
        else
            table.insert(errors, "osd.timestamp.x_offset: " .. (result or "unknown error"))
        end
    end

    if post_data.timestamp_y_offset then
        local success, result = safe_jct_set("osd.timestamp.y_offset", post_data.timestamp_y_offset)
        if success then
            saved_settings.timestamp_y_offset = post_data.timestamp_y_offset
        else
            table.insert(errors, "osd.timestamp.y_offset: " .. (result or "unknown error"))
        end
    end

    if post_data.custom_timestamp and post_data.custom_timestamp ~= "" then
        local escaped_value = "'" .. post_data.custom_timestamp:gsub("'", "'\"'\"'") .. "'"
        local success, result = safe_jct_set("osd.timestamp.custom_format", escaped_value)
        if success then
            saved_settings.custom_timestamp = post_data.custom_timestamp
        else
            table.insert(errors, "osd.timestamp.custom_format: " .. (result or "unknown error"))
        end
    end

    -- Save title settings
    if post_data.title_enabled then
        local value = post_data.title_enabled == "true" and "true" or "false"
        local success, result = safe_jct_set("osd.title.enabled", value)
        if success then
            saved_settings.title_enabled = value
        else
            table.insert(errors, "osd.title.enabled: " .. (result or "unknown error"))
        end
    end

    if post_data.title_position then
        local success, result = safe_jct_set("osd.title.position", post_data.title_position)
        if success then
            saved_settings.title_position = post_data.title_position
        else
            table.insert(errors, "osd.title.position: " .. (result or "unknown error"))
        end
    end

    if post_data.title_x_offset then
        local success, result = safe_jct_set("osd.title.x_offset", post_data.title_x_offset)
        if success then
            saved_settings.title_x_offset = post_data.title_x_offset
        else
            table.insert(errors, "osd.title.x_offset: " .. (result or "unknown error"))
        end
    end

    if post_data.title_y_offset then
        local success, result = safe_jct_set("osd.title.y_offset", post_data.title_y_offset)
        if success then
            saved_settings.title_y_offset = post_data.title_y_offset
        else
            table.insert(errors, "osd.title.y_offset: " .. (result or "unknown error"))
        end
    end

    -- Save font settings
    if post_data.ch0_font then
        local font_name = post_data.ch0_font
        local font_name_value = font_name == "" and '""' or ("'" .. font_name .. "'")
        local font_path_value = '""'

        if font_name ~= "" then
            -- Determine full path: user fonts vs system fonts
            local user_font_path = "/opt/fonts/" .. font_name
            if utils.file_exists(user_font_path) then
                font_path_value = "'" .. user_font_path .. "'"
            else
                -- Assume it's a system font (fallback)
                font_path_value = "'/usr/share/fonts/" .. font_name .. "'"
            end
        end

        -- Save both font name and full path
        local success1, result1 = safe_jct_set("stream0.font", font_name_value)
        local success2, result2 = safe_jct_set("stream0.osd.font_path", font_path_value)

        if success1 and success2 then
            saved_settings.ch0_font = font_name
        else
            if not success1 then table.insert(errors, "stream0.font: " .. (result1 or "unknown error")) end
            if not success2 then table.insert(errors, "stream0.osd.font_path: " .. (result2 or "unknown error")) end
        end
    end

    if post_data.ch1_font then
        local font_name = post_data.ch1_font
        local font_name_value = font_name == "" and '""' or ("'" .. font_name .. "'")
        local font_path_value = '""'

        if font_name ~= "" then
            -- Determine full path: user fonts vs system fonts
            local user_font_path = "/opt/fonts/" .. font_name
            if utils.file_exists(user_font_path) then
                font_path_value = "'" .. user_font_path .. "'"
            else
                -- Assume it's a system font (fallback)
                font_path_value = "'/usr/share/fonts/" .. font_name .. "'"
            end
        end

        -- Save both font name and full path
        local success1, result1 = safe_jct_set("stream1.font", font_name_value)
        local success2, result2 = safe_jct_set("stream1.osd.font_path", font_path_value)

        if success1 and success2 then
            saved_settings.ch1_font = font_name
        else
            if not success1 then table.insert(errors, "stream1.font: " .. (result1 or "unknown error")) end
            if not success2 then table.insert(errors, "stream1.osd.font_path: " .. (result2 or "unknown error")) end
        end
    end

    return utils.send_json({
        success = #errors == 0,
        message = #errors == 0 and "OSD settings saved successfully" or "Some settings failed to save",
        saved = saved_settings,
        errors = errors
    })
end

function api_get_osd_config(sess)
    local config_path = "/etc/prudynt.json"

    -- Map config keys to form fields
    local config_mappings = {
        ["osd.enabled"] = "osd_enabled",
        ["osd.timestamp.enabled"] = "timestamp_enabled",
        ["osd.timestamp.format"] = "timestamp_format",
        ["osd.timestamp.position"] = "timestamp_position",
        ["osd.timestamp.x_offset"] = "timestamp_x_offset",
        ["osd.timestamp.y_offset"] = "timestamp_y_offset",
        ["osd.timestamp.custom_format"] = "custom_timestamp",
        ["osd.title.enabled"] = "title_enabled",
        ["osd.title.text"] = "camera_title",
        ["osd.title.position"] = "title_position",
        ["osd.title.x_offset"] = "title_x_offset",
        ["osd.title.y_offset"] = "title_y_offset",
        ["osd.text.size"] = "text_size",
        ["osd.text.color"] = "text_color",
        ["osd.text.background"] = "text_background",
        ["osd.text.opacity"] = "text_opacity",
        ["stream0.font"] = "ch0_font",
        ["stream1.font"] = "ch1_font"
    }

    local config = {}

    -- Get each configuration value using jct
    for config_key, form_field in pairs(config_mappings) do
        local cmd = string.format("jct %s get %s 2>/dev/null", config_path, config_key)
        local handle = io.popen(cmd)
        if handle then
            local value = handle:read("*line")
            handle:close()

            if value and value ~= "" then
                -- Remove quotes if present
                value = value:gsub('^"(.*)"$', '%1')
                config[form_field] = value
            end
        end
    end

    return utils.send_json({
        success = true,
        config = config
    })
end

-- Add API endpoint for language pack management
function api_language_list(sess)
    return utils.send_json({
        success = true,
        current = i18n.get_language(),
        available = i18n.get_available_languages(),
        names = i18n.get_language_names()
    })
end

function api_language_set(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    if not post_data or not post_data.lang then
        return utils.send_json({
            success = false,
            error = "No language specified"
        }, 400)
    end

    -- Settings-based language change: download from GitHub if needed, then set
    local success, result = pcall(function()
        local lang = post_data.lang

        -- Try to download language pack from GitHub if not available locally
        local download_success, download_msg = i18n.download_language_pack_from_github(lang)

        -- Set the language (will work with built-in or downloaded pack)
        local set_success = i18n.set_language(lang)

        -- Use the requested language instead of trying to detect it (avoids race conditions)
        local current = set_success and lang or "en"

        -- Get the proper language name for the message
        local language_names = i18n.get_language_names()
        local language_name = language_names[current] or current

        return {
            success = set_success,
            current = current,
            download_attempted = true,
            download_success = download_success,
            download_message = download_msg,
            message = "Language set to " .. language_name .. ". Please refresh the page to see changes."
        }
    end)

    if success then
        return utils.send_json(result)
    else
        return utils.send_json({
            success = false,
            error = "Internal error: " .. tostring(result)
        }, 500)
    end
end

function api_language_download(sess, env)
    if env.REQUEST_METHOD ~= "POST" then
        return utils.send_json({error = "Method not allowed"}, 405)
    end

    local post_data = utils.read_post_data(env)
    if not post_data or not post_data.lang or not post_data.url then
        return utils.send_json({
            success = false,
            error = "Missing language or URL"
        }, 400)
    end

    local success, message = i18n.download_language_pack(post_data.lang, post_data.url)

    return utils.send_json({
        success = success,
        message = success and message or nil,
        error = success and nil or message
    })
end

-- API endpoint to serve current language pack (simple version)
function api_get_current_language_pack(sess)
    local content = i18n.get_language_pack()
    if content then
        -- Parse JSON and send as object
        local translations = {}
        for key, value in content:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
            value = value:gsub('\\"', '"')  -- Handle escaped quotes
            translations[key] = value
        end

        -- Send raw JSON content with proper headers
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: application/json; charset=utf-8\r\n")
        uhttpd.send("Cache-Control: no-store\r\n\r\n")

        -- Convert translations table to JSON
        local json_parts = {}
        for k, v in pairs(translations) do
            table.insert(json_parts, '"' .. k .. '":"' .. v:gsub('"', '\\"') .. '"')
        end
        uhttpd.send('{' .. table.concat(json_parts, ',') .. '}')
    else
        -- No language pack = English (return empty object)
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: application/json; charset=utf-8\r\n")
        uhttpd.send("Cache-Control: no-store\r\n\r\n")
        uhttpd.send('{}')
    end
end

-- API endpoint to serve language pack JSON
function api_get_language_pack(sess, lang)
    if not lang or lang == "" then
        return utils.send_json({error = "Language code required"}, 400)
    end

    -- Add error handling
    local success, content = pcall(i18n.get_language_pack, lang)
    if not success then
        utils.log("Error getting language pack for " .. lang .. ": " .. tostring(content))
        return utils.send_json({error = "Internal server error"}, 500)
    end

    if content then
        -- Send raw JSON content with proper headers
        uhttpd.send("Status: 200 OK\r\n")
        uhttpd.send("Content-Type: application/json; charset=utf-8\r\n")
        uhttpd.send("Cache-Control: no-store\r\n\r\n")
        uhttpd.send(content)
    else
        utils.send_json({error = "Language pack not found for: " .. lang}, 404)
    end
end

-- Debug endpoint to check language pack availability
function api_language_debug(sess)
    local debug_info = {
        builtin_dir = "/var/www/lang_packs",
        download_dir = "/tmp/lang_packs",
        available_languages = {},
        file_checks = {}
    }

    -- Check if directories exist
    local function check_dir(path)
        local handle = io.popen("ls -la " .. path .. " 2>/dev/null")
        if handle then
            local result = handle:read("*a")
            handle:close()
            return result ~= "" and result or nil
        end
        return nil
    end

    debug_info.builtin_dir_content = check_dir(debug_info.builtin_dir)
    debug_info.download_dir_content = check_dir(debug_info.download_dir)

    -- Check specific files
    local test_files = {
        debug_info.builtin_dir .. "/en.json",
        debug_info.builtin_dir .. "/es.json"
    }

    for _, file_path in ipairs(test_files) do
        local file = io.open(file_path, "r")
        if file then
            local content = file:read("*all")
            file:close()
            debug_info.file_checks[file_path] = {
                exists = true,
                size = #content,
                preview = content:sub(1, 100)
            }
        else
            debug_info.file_checks[file_path] = {
                exists = false
            }
        end
    end

    -- Get available languages from i18n
    local success, available = pcall(i18n.get_available_languages)
    if success then
        debug_info.available_languages = available
    else
        debug_info.i18n_error = tostring(available)
    end

    utils.send_json(debug_info)
end

-- Test language persistence
function api_language_test_persistence(sess)
    local test_results = {}

    -- Test 1: Check if settings file exists and what it contains
    local settings_file = "/opt/webui/i18n/current_language"
    local file = io.open(settings_file, "r")
    if file then
        local content = file:read("*all")
        file:close()
        test_results.file_exists = true
        test_results.file_content = content
    else
        test_results.file_exists = false
        test_results.file_content = nil
    end

    -- Test 2: Try to write a test value
    local test_file = io.open(settings_file, "w")
    if test_file then
        test_file:write("test_lang")
        test_file:close()
        test_results.write_test = "success"

        -- Test 3: Try to read it back
        local read_file = io.open(settings_file, "r")
        if read_file then
            local read_content = read_file:read("*all")
            read_file:close()
            test_results.read_test = "success"
            test_results.read_content = read_content
        else
            test_results.read_test = "failed"
        end
    else
        test_results.write_test = "failed"
    end

    -- Test 4: Current i18n state
    test_results.current_lang = i18n.get_language()

    -- Test 5: Check debug log
    local debug_file = io.open("/tmp/i18n_debug.log", "r")
    if debug_file then
        local debug_content = debug_file:read("*all")
        debug_file:close()
        test_results.debug_log = debug_content
    else
        test_results.debug_log = "No debug log found"
    end

    return utils.send_json(test_results)
end

-- Refresh available languages from GitHub
function api_language_refresh_available(sess)
    -- GitHub API URL to list files in lang_packs directory
    local github_api_url = "https://api.github.com/repos/themactep/thingino-firmware/contents/package/thingino-webui-lua/files/lang_packs"

    -- Use curl to fetch the directory listing
    local temp_file = "/tmp/github_lang_list.json"
    local cmd = "curl -s -o " .. temp_file .. " '" .. github_api_url .. "'"
    local exit_code = os.execute(cmd)

    if not exit_code then
        return utils.send_json({
            success = false,
            error = "Failed to fetch language list from GitHub"
        }, 500)
    end

    -- Read the response
    local file = io.open(temp_file, "r")
    if not file then
        return utils.send_json({
            success = false,
            error = "Failed to read GitHub response"
        }, 500)
    end

    local content = file:read("*all")
    file:close()
    os.remove(temp_file)

    -- Parse the JSON response to extract .json files
    local available_languages = {"en"}  -- Always include English
    local language_names = {en = "English"}

    -- Simple JSON parsing to find .json files
    for filename in content:gmatch('"name"%s*:%s*"([^"]+%.json)"') do
        local lang_code = filename:match("^([^%.]+)%.json$")
        if lang_code and lang_code ~= "en" then
            table.insert(available_languages, lang_code)

            -- Add language display names
            local names = {
                es = "Español",
                fr = "Français",
                de = "Deutsch",
                it = "Italiano",
                pt = "Português",
                ru = "Русский",
                zh = "中文",
                ja = "日本語",
                ko = "한국어"
            }
            language_names[lang_code] = names[lang_code] or lang_code:upper()
        end
    end

    return utils.send_json({
        success = true,
        available = available_languages,
        names = language_names,
        source = "GitHub",
        message = "Language list refreshed from GitHub"
    })
end
