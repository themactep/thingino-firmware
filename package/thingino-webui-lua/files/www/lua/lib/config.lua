local config = {}
local utils = require("utils")

-- Configuration file paths
local CONFIG_FILE = "/etc/thingino.conf"
local BACKUP_DIR = "/tmp/config_backups"

-- Load configuration from file
function config.load()
    local conf = {}
    local file = io.open(CONFIG_FILE, "r")
    
    if file then
        for line in file:lines() do
            -- Skip comments and empty lines
            if not line:match("^%s*#") and not line:match("^%s*$") then
                local key, value = line:match("^([^=]+)=(.*)$")
                if key and value then
                    -- Remove quotes from value
                    value = value:gsub('^"(.*)"$', '%1')
                    conf[key] = value
                end
            end
        end
        file:close()
    end
    
    return conf
end

-- Save configuration to file
function config.save(conf)
    -- Create backup first
    config.create_backup()
    
    local file = io.open(CONFIG_FILE, "w")
    if not file then
        return false, "Cannot write to configuration file"
    end
    
    -- Write header
    file:write("# Thingino configuration file\n")
    local utils = require("utils")
    file:write("# Generated on " .. os.date(utils.DATETIME_FORMAT) .. "\n\n")
    
    -- Sort keys for consistent output
    local keys = {}
    for k in pairs(conf) do
        table.insert(keys, k)
    end
    table.sort(keys)
    
    -- Write configuration
    for _, key in ipairs(keys) do
        local value = conf[key]
        if value and value ~= "" then
            -- Quote values that contain spaces or special characters
            if value:match("[%s\"'\\]") then
                value = '"' .. value:gsub('"', '\\"') .. '"'
            end
            file:write(key .. "=" .. value .. "\n")
        end
    end
    
    file:close()
    return true, "Configuration saved"
end

-- Get specific configuration section
function config.get_config(section)
    local conf = config.load()
    local result = {}
    
    if section == "network" then
        result = config.get_network_config(conf)
    elseif section == "camera" then
        result = config.get_camera_config(conf)
    elseif section == "system" then
        result = config.get_system_config(conf)
    elseif section == "webui" then
        result = config.get_webui_config(conf)
    else
        result = conf
    end
    
    return result
end

-- Get network configuration
function config.get_network_config(conf)
    conf = conf or config.load()

    -- Get current network info as fallbacks
    local current_ip = utils.execute_command("ip route get 1 2>/dev/null | awk '{print $7; exit}'") or ""
    current_ip = current_ip:gsub("%s+", "") -- trim whitespace

    local current_gateway = utils.execute_command("ip route | grep default | awk '{print $3; exit}'") or ""
    current_gateway = current_gateway:gsub("%s+", "")

    return {
        hostname = conf.network_hostname or utils.get_hostname() or "thingino",
        interface = conf.network_interface or "wlan0",
        dhcp = conf.network_dhcp or "true",
        ip_address = conf.network_ip_address or current_ip,
        netmask = conf.network_netmask or "255.255.255.0",
        gateway = conf.network_gateway or current_gateway,
        dns1 = conf.network_dns1 or "8.8.8.8",
        dns2 = conf.network_dns2 or "8.8.4.4",
        wifi_ssid = conf.wlansta_ssid or "",
        wifi_password = conf.wlansta_password or "",
        wifi_encryption = conf.wlansta_encryption or "wpa2"
    }
end

-- Get camera configuration
function config.get_camera_config(conf)
    conf = conf or config.load()
    
    return {
        sensor = conf.sensor_model or "unknown",
        resolution = conf.stream0_resolution or "1920x1080",
        fps = conf.stream0_fps or "25",
        bitrate = conf.stream0_bitrate or "2048",
        codec = conf.stream0_codec or "h264",
        flip_horizontal = conf.image_hflip or "false",
        flip_vertical = conf.image_vflip or "false",
        night_mode = conf.daynight_mode or "auto",
        ir_cut = conf.gpio_ircut or "",
        ir_led = conf.gpio_ir850 or ""
    }
end

-- Get system configuration
function config.get_system_config(conf)
    conf = conf or config.load()

    -- Read current timezone from system files
    local current_timezone = "UTC"
    local tz_name_file = io.open("/etc/timezone", "r")
    if tz_name_file then
        current_timezone = tz_name_file:read("*l") or "UTC"
        tz_name_file:close()
        -- Clean up any whitespace
        current_timezone = current_timezone:gsub("^%s+", ""):gsub("%s+$", "")
    end

    return {
        timezone = current_timezone,
        ntp_server = conf.ntp_server or "pool.ntp.org",
        ntp_server_backup = conf.ntp_server_backup or "time.nist.gov",
        log_level = conf.log_level or "info",
        ssh_enabled = conf.ssh_enabled or "true",
        telnet_enabled = conf.telnet_enabled or "false",
        webui_theme = conf.webui_theme or "dark",
        webui_username = conf.ui_username or "root",
        webui_paranoid = conf.webui_paranoid or "false"
    }
end

-- Get web UI configuration
function config.get_webui_config(conf)
    conf = conf or config.load()
    
    return {
        theme = conf.webui_theme or "dark",
        paranoid = conf.webui_paranoid or "false",
        username = conf.ui_username or "root",
        ws_token = conf.ws_token or ""
    }
end

-- Update configuration
function config.update_config(section, post_data)
    local conf = config.load()
    local success = false
    local message = ""
    
    if section == "network" then
        success, message = config.update_network_config(conf, post_data)
    elseif section == "camera" then
        success, message = config.update_camera_config(conf, post_data)
    elseif section == "system" then
        success, message = config.update_system_config(conf, post_data)
    elseif section == "webui" then
        success, message = config.update_webui_config(conf, post_data)
    else
        return false, "Unknown configuration section"
    end
    
    if success then
        local save_success, save_message = config.save(conf)
        if not save_success then
            return false, save_message
        end
    end
    
    return success, message
end

-- Update network configuration
function config.update_network_config(conf, data)
    if data.hostname then
        conf.network_hostname = data.hostname
    end
    
    if data.dhcp then
        conf.network_dhcp = data.dhcp
        if data.dhcp == "false" then
            conf.network_ip_address = data.ip_address or ""
            conf.network_netmask = data.netmask or ""
            conf.network_gateway = data.gateway or ""
        end
    end
    
    if data.dns1 then
        conf.network_dns1 = data.dns1
    end
    
    if data.dns2 then
        conf.network_dns2 = data.dns2
    end
    
    if data.wifi_ssid then
        conf.wlansta_ssid = data.wifi_ssid
    end
    
    if data.wifi_password then
        conf.wlansta_password = data.wifi_password
    end
    
    if data.wifi_encryption then
        conf.wlansta_encryption = data.wifi_encryption
    end
    
    return true, "Network configuration updated"
end

-- Update camera configuration
function config.update_camera_config(conf, data)
    if data.resolution then
        conf.stream0_resolution = data.resolution
    end
    
    if data.fps then
        conf.stream0_fps = data.fps
    end
    
    if data.bitrate then
        conf.stream0_bitrate = data.bitrate
    end
    
    if data.codec then
        conf.stream0_codec = data.codec
    end
    
    if data.flip_horizontal then
        conf.image_hflip = data.flip_horizontal
    end
    
    if data.flip_vertical then
        conf.image_vflip = data.flip_vertical
    end
    
    if data.night_mode then
        conf.daynight_mode = data.night_mode
    end
    
    return true, "Camera configuration updated"
end

-- Update system configuration
function config.update_system_config(conf, data)
    if data.timezone then
        conf.TZ = data.timezone

        -- Also update system timezone files if timezone_data is provided
        if data.timezone_data and data.timezone_data ~= "" then
            -- Write timezone name to /etc/timezone
            local tz_name_file = io.open("/etc/timezone", "w")
            if tz_name_file then
                tz_name_file:write(data.timezone)
                tz_name_file:close()
            end

            -- Write timezone data to /etc/TZ
            local tz_data_file = io.open("/etc/TZ", "w")
            if tz_data_file then
                tz_data_file:write(data.timezone_data)
                tz_data_file:close()
            end

            -- Restart timezone service to apply changes
            os.execute("service restart timezone > /dev/null 2>&1")
        end
    end

    if data.ntp_server then
        conf.ntp_server = data.ntp_server
    end

    if data.ntp_server_backup then
        conf.ntp_server_backup = data.ntp_server_backup
    end

    if data.log_level then
        conf.log_level = data.log_level
    end

    if data.ssh_enabled then
        conf.ssh_enabled = data.ssh_enabled
    end

    if data.telnet_enabled then
        conf.telnet_enabled = data.telnet_enabled
    end

    return true, "System configuration updated"
end

-- Update web UI configuration
function config.update_webui_config(conf, data)
    if data.theme then
        conf.webui_theme = data.theme
    end
    
    if data.paranoid then
        conf.webui_paranoid = data.paranoid
    end
    
    if data.username then
        conf.ui_username = data.username
    end
    
    return true, "Web UI configuration updated"
end

-- Create configuration backup
function config.create_backup()
    os.execute("mkdir -p " .. BACKUP_DIR)
    
    local timestamp = os.date("%Y%m%d_%H%M%S")
    local backup_file = BACKUP_DIR .. "/thingino_" .. timestamp .. ".conf"
    
    os.execute("cp " .. CONFIG_FILE .. " " .. backup_file .. " 2>/dev/null")
    
    -- Keep only last 10 backups
    local cmd = "ls -t " .. BACKUP_DIR .. "/thingino_*.conf 2>/dev/null | tail -n +11 | xargs rm -f"
    os.execute(cmd)
end

-- Restore configuration from backup
function config.restore_backup(backup_file)
    if not utils.file_exists(backup_file) then
        return false, "Backup file not found"
    end
    
    local result = os.execute("cp " .. backup_file .. " " .. CONFIG_FILE)
    if result == 0 then
        return true, "Configuration restored from backup"
    else
        return false, "Failed to restore configuration"
    end
end

-- List available backups
function config.list_backups()
    local backups = {}
    local handle = io.popen("ls -t " .. BACKUP_DIR .. "/thingino_*.conf 2>/dev/null")
    
    if handle then
        for filename in handle:lines() do
            local basename = filename:match("([^/]+)$")
            local timestamp = basename:match("thingino_(%d+_%d+)%.conf")
            if timestamp then
                local year, month, day, hour, min, sec = timestamp:match("(%d%d%d%d)(%d%d)(%d%d)_(%d%d)(%d%d)(%d%d)")
                local date_str = string.format("%s-%s-%s %s:%s:%s", year, month, day, hour, min, sec)
                table.insert(backups, {
                    filename = filename,
                    timestamp = timestamp,
                    date = date_str
                })
            end
        end
        handle:close()
    end
    
    return backups
end

return config
