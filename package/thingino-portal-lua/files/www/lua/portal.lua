#!/usr/bin/lua

-- Thingino Portal - Lua version for uhttpd
-- Initial camera configuration portal

-- Load required modules
local io = require("io")
local os = require("os")
local string = require("string")

-- Configuration
local CONFIG = {
    debug_file = "/var/log/portaldebug",
    ttl_in_sec = 600,
    os_release_file = "/etc/os-release",
    common_file = "/usr/share/common"
}

-- Utility functions
local utils = {}

function utils.log(message)
    local file = io.open(CONFIG.debug_file, "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. message .. "\n")
        file:close()
    end
end

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
        local content = file:read("*a")
        file:close()
        return content
    end
    return nil
end

function utils.write_file(path, content)
    local file = io.open(path, "w")
    if file then
        file:write(content)
        file:close()
        return true
    end
    return false
end

function utils.execute_command(cmd)
    local handle = io.popen(cmd)
    if handle then
        local result = handle:read("*a")
        local success = handle:close()
        return result, success
    end
    return nil, false
end

function utils.html_escape(text)
    if not text then return "" end
    text = string.gsub(text, "&", "&amp;")
    text = string.gsub(text, "<", "&lt;")
    text = string.gsub(text, ">", "&gt;")
    text = string.gsub(text, '"', "&quot;")
    text = string.gsub(text, "'", "&#39;")
    return text
end

function utils.url_decode(str)
    if not str then return "" end
    str = string.gsub(str, "+", " ")
    str = string.gsub(str, "%%(%x%x)", function(h)
        return string.char(tonumber(h, 16))
    end)
    return str
end

function utils.parse_query_string(query)
    local params = {}
    if not query then return params end

    for pair in string.gmatch(query, "[^&]+") do
        local key, value = string.match(pair, "([^=]+)=([^=]*)")
        if key then
            params[utils.url_decode(key)] = utils.url_decode(value or "")
        end
    end
    return params
end

function utils.read_post_data(env)
    local content_length = tonumber(env.CONTENT_LENGTH or "0")
    local post_data = {}

    if content_length > 0 then
        local success, raw_data = pcall(function()
            return io.read(content_length)
        end)

        if success and raw_data then
            -- Parse form data
            for pair in raw_data:gmatch("([^&]+)") do
                local key, value = pair:match("([^=]+)=([^=]*)")
                if key and value then
                    post_data[utils.url_decode(key)] = utils.url_decode(value)
                end
            end
        end
    end

    return post_data
end

-- System information functions
function get_system_info()
    local info = {
        hostname = "",
        image_id = "",
        build_id = "",
        wlan_mac = "",
        timestamp = os.time()
    }

    -- Get hostname
    local hostname_result = utils.execute_command("hostname")
    if hostname_result then
        info.hostname = string.gsub(hostname_result, "\n", "")
    end

    -- Get OS release info
    if utils.file_exists(CONFIG.os_release_file) then
        local os_release = utils.read_file(CONFIG.os_release_file)
        if os_release then
            info.image_id = string.match(os_release, "IMAGE_ID=([^\n]+)") or ""
            local build_match = string.match(os_release, 'BUILD_ID="([^"]+)"')
            info.build_id = build_match or string.match(os_release, "BUILD_ID=([^\n]+)") or ""
        end
    end

    -- Get WLAN MAC address
    local mac_result = utils.execute_command("cat /sys/class/net/wlan0/address 2>/dev/null")
    if mac_result then
        info.wlan_mac = string.gsub(mac_result, "\n", "")
    end

    return info
end

-- Environment variable functions
function get_env_vars()
    local env = {}

    -- Source common file if it exists
    if utils.file_exists(CONFIG.common_file) then
        local result = utils.execute_command(". " .. CONFIG.common_file .. " && env")
        if result then
            for line in string.gmatch(result, "[^\n]+") do
                local key, value = string.match(line, "([^=]+)=(.*)")
                if key then
                    env[key] = value
                end
            end
        end
    end

    return env
end

-- WiFi functions
function convert_psk(ssid, passphrase)
    if not ssid or not passphrase then return passphrase end

    -- Use wpa_passphrase to convert to PSK if available
    local cmd = string.format("wpa_passphrase '%s' '%s' 2>/dev/null | grep -E '^[[:space:]]*psk=' | cut -d= -f2",
                             ssid, passphrase)
    local result = utils.execute_command(cmd)
    if result and result ~= "" then
        return string.gsub(result, "\n", "")
    end

    -- Fallback to original passphrase
    return passphrase
end

-- Main portal logic
function handle_portal_request(env)
    -- Use env parameter like the main web UI
    env = env or {}
    local method = env.REQUEST_METHOD or "GET"
    local query_string = env.QUERY_STRING or ""
    local script_name = env.SCRIPT_NAME or "/lua/portal.lua"

    utils.log("=== PORTAL REQUEST DEBUG ===")
    utils.log("METHOD: " .. method)
    utils.log("QUERY_STRING: " .. query_string)
    utils.log("SCRIPT_NAME: " .. script_name)
    utils.log("CONTENT_LENGTH: " .. (env.CONTENT_LENGTH or "0"))
    utils.log(method .. " request to " .. script_name)

    local params = {}
    local system_info = get_system_info()
    local env_vars = get_env_vars()

    -- Parse parameters based on method
    if method == "GET" then
        params = utils.parse_query_string(query_string)
    elseif method == "POST" then
        -- Use the web UI's POST data reading method
        params = utils.read_post_data(env)
        utils.log("POST data received, parsed parameters:")
        for k, v in pairs(params) do
            utils.log("PARAM: " .. k .. " = " .. v)
        end
    end

    -- Initialize form data with current values or parameters
    local form_data = {
        hostname = params.hostname or system_info.hostname or "thingino-cam",
        rootpass = params.rootpass or "",
        rootpkey = params.rootpkey or "",
        timezone = params.timezone or "",
        wlanap_enabled = params.wlanap_enabled or "false",
        wlanap_ssid = params.wlanap_ssid or env_vars.wlanap_ssid or "",
        wlanap_pass = params.wlanap_pass or "",
        wlan_ssid = params.wlan_ssid or env_vars.wlan_ssid or "",
        wlan_pass = params.wlan_pass or "",
        mode = params.mode or "edit",
        timestamp = params.timestamp or tostring(system_info.timestamp),
        error_message = ""
    }

    -- Check for expired POST request
    local current_time = system_info.timestamp
    local post_timestamp = tonumber(form_data.timestamp) or current_time
    local is_expired = (method == "POST") and (post_timestamp < (current_time - CONFIG.ttl_in_sec))

    if is_expired then
        utils.log("POST request expired")
        send_redirect(script_name)
        return
    end

    -- Handle different modes
    if method == "POST" and form_data.mode == "save" then
        handle_save_configuration(form_data, system_info, script_name)
    elseif method == "POST" and form_data.mode == "review" then
        send_review_page(form_data, system_info, script_name)
    elseif method == "GET" and form_data.wlan_ssid ~= "" and form_data.wlan_pass ~= "" then
        send_completion_page(form_data, system_info, "wlan")
    elseif method == "GET" and form_data.wlanap_ssid ~= "" and form_data.wlanap_pass ~= "" then
        send_completion_page(form_data, system_info, "wlanap")
    else
        send_configuration_form(form_data, system_info, script_name)
    end
end

-- HTTP response functions
function send_http_headers(status, content_type, extra_headers)
    status = status or "200 OK"
    content_type = content_type or "text/html; charset=UTF-8"

    print("Status: " .. status)
    print("Content-Type: " .. content_type)
    print("Cache-Control: no-store")
    print("Pragma: no-cache")
    print("Date: " .. os.date("!%a, %d %b %Y %T GMT"))
    print("Server: Thingino Portal Lua")

    if extra_headers then
        for _, header in ipairs(extra_headers) do
            print(header)
        end
    end

    print("") -- Empty line to end headers
end

function send_redirect(location)
    send_http_headers("303 See Other", nil, {"Location: " .. location})
end

function validate_form_data(form_data)
    local errors = {}

    -- Validate hostname
    if not form_data.hostname or form_data.hostname == "" then
        table.insert(errors, "Hostname is required")
    else
        local bad_chars = string.gsub(form_data.hostname, "[0-9A-Za-z%.%-]", "")
        if bad_chars ~= "" then
            table.insert(errors, "Hostname contains invalid characters: " .. bad_chars)
        end
    end

    -- Validate root password
    if not form_data.rootpass or form_data.rootpass == "" then
        table.insert(errors, "Root password is required")
    end

    -- Validate WiFi settings
    if form_data.wlanap_enabled == "true" then
        if not form_data.wlanap_ssid or form_data.wlanap_ssid == "" then
            table.insert(errors, "WiFi AP SSID is required")
        end
        if not form_data.wlanap_pass or string.len(form_data.wlanap_pass) < 8 then
            table.insert(errors, "WiFi AP password must be at least 8 characters")
        end
    else
        if not form_data.wlan_ssid or form_data.wlan_ssid == "" then
            table.insert(errors, "WiFi network SSID is required")
        end
        if not form_data.wlan_pass or string.len(form_data.wlan_pass) < 8 then
            table.insert(errors, "WiFi network password must be at least 8 characters")
        end
    end

    return errors
end

function handle_save_configuration(form_data, system_info, script_name)
    utils.log("=== SAVE CONFIGURATION ===")
    utils.log("Saving configuration")
    utils.log("Form data received:")
    for k, v in pairs(form_data) do
        utils.log("SAVE PARAM: " .. k .. " = " .. tostring(v))
    end

    local errors = validate_form_data(form_data)
    if #errors > 0 then
        form_data.error_message = table.concat(errors, "; ")
        form_data.mode = "edit"
        send_configuration_form(form_data, system_info, script_name)
        return
    end

    -- Update hostname
    utils.execute_command("hostname '" .. form_data.hostname .. "'")
    utils.write_file("/etc/hostname", form_data.hostname .. "\n")

    -- Update WiFi settings
    local temp_file = "/tmp/portal_env_" .. os.time()
    local env_content = ""

    if form_data.wlanap_enabled == "true" then
        local wlanap_psk = convert_psk(form_data.wlanap_ssid, form_data.wlanap_pass)
        env_content = string.format("wlanap_ssid %s\nwlanap_pass %s\n",
                                   form_data.wlanap_ssid, wlanap_psk)
    else
        local wlan_psk = convert_psk(form_data.wlan_ssid, form_data.wlan_pass)
        env_content = string.format("wlan_ssid %s\nwlan_pass %s\n",
                                   form_data.wlan_ssid, wlan_psk)
    end

    utils.write_file(temp_file, env_content)
    utils.execute_command("fw_setenv -s " .. temp_file)
    utils.execute_command("rm -f " .. temp_file)

    -- Set wlanap status
    utils.execute_command("conf s wlanap_enabled " .. form_data.wlanap_enabled)

    -- Update environment dump
    utils.execute_command("refresh_env_dump")

    -- Update timezone
    if form_data.timezone and form_data.timezone ~= "" then
        utils.write_file("/etc/timezone", form_data.timezone .. "\n")
    end

    -- Update root password
    utils.execute_command("echo 'root:" .. form_data.rootpass .. "' | chpasswd -c sha512")

    -- Update SSH key
    if form_data.rootpkey and form_data.rootpkey ~= "" then
        local clean_key = string.gsub(form_data.rootpkey, "\r", "")
        clean_key = string.gsub(clean_key, "^ +", "")
        utils.write_file("/root/.ssh/authorized_keys", clean_key .. "\n")
    end

    -- Update ONVIF interface
    utils.execute_command("jct /etc/onvif.json set ifs wlan0")

    utils.log("Configuration saved, showing completion page")

    -- Show completion page based on configuration type
    if form_data.wlanap_enabled == "true" then
        send_completion_page(form_data, system_info, "wlanap")
    else
        send_completion_page(form_data, system_info, "wlan")
    end

    -- Schedule reboot after showing the page
    utils.execute_command("reboot -d 5 &")
end

-- HTML generation functions
function send_html_header(title)
    title = title or "Thingino Initial Configuration"

    print([[<!DOCTYPE html>
<html lang="en" data-bs-theme="dark">
<head>
<meta charset="utf-8">
<meta content="width=device-width,initial-scale=1" name="viewport">
<title>]] .. utils.html_escape(title) .. [[</title>
<link rel="stylesheet" href="/a/bootstrap.min.css">
<style>
h1,h2 {font-weight:400}
h1 {font-size:3rem}
h1 span {color:#f80}
h2 {font-size:1.3rem}
.container {max-width:26rem}
.form-label {margin:0}
#logo {max-width:16rem}
#verify dd, b {color:#f80;font-weight:700}
#verify dd#pkey {max-height:5em;overflow:auto;font-size:medium}
</style>
<script src="/a/bootstrap.bundle.min.js"></script>
</head>
<body>
<header class="my-4 text-center">
<div class="container">
<h1><img src="/a/logo.svg" alt="Thingino Logo" class="img-fluid" id="logo"></h1>
<h2>Initial Configuration</h2>
</div>
</header>
<main>
<div class="container">]])
end

function send_html_footer(system_info)
    print([[
<p class="small text-muted text-center">Built for ]] .. utils.html_escape(system_info.image_id) .. [[<br>]] .. utils.html_escape(system_info.build_id) .. [[</p>
</div>
</main>

<div class="offcanvas offcanvas-bottom" tabindex="-1" id="timeout">
<div class="offcanvas-header">
<h5 class="offcanvas-title">Timeout Warning</h5>
<button type="button" class="btn-close" data-bs-dismiss="offcanvas" aria-label="Close"></button>
</div>
<div class="offcanvas-body small">
<p class="alert alert-warning text-center">
For security, portal will automatically shutoff after 5 minutes.
Power cycle camera to re-activate portal.
</p>
</div>
</div>

</body>
</html>]])
end

function send_completion_page(form_data, system_info, mode)
    send_http_headers()
    send_html_header()

    if mode == "wlan" then
        print([[
<div class="alert alert-success text-center">
<h3>Configuration Completed</h3>
<p class="lead">Your camera is rebooting to connect to your wireless network.</p>
<p class="alert alert-warning mb-0">The MAC address is<br><span class="lead">]] .. utils.html_escape(system_info.wlan_mac) .. [[</span></p>
</div>

<p>To get started, just tap the reset button on your camera. If it's connected to the internet, it'll tell
 you its IP address. If you're not hearing that, no worries! Find the IP address among DHCP server leases
 (usually in your wireless router).</p>

<p>For configuration information and troubleshooting steps please refer to
 <a href="https://github.com/themactep/thingino-firmware/wiki/">the project Wiki</a>.</p>]])

    elseif mode == "wlanap" then
        print([[
<div class="alert alert-success text-center">
<h3>Configuration Completed</h3>
<p class="lead mb-0">Your camera is rebooting to create a wireless access point.</p>
</div>

<p>To start, locate the <b>]] .. utils.html_escape(form_data.wlanap_ssid) .. [[</b> wireless network on your device,
 connect using your password <b>]] .. utils.html_escape(form_data.wlanap_pass) .. [[</b>, then open the web interface
 at <b>http://thingino.local/</b> using login <b>root</b> and the password you have
 just set up for that user.</p>]])
    end

    send_html_footer(system_info)
end

function send_configuration_form(form_data, system_info, script_name)
    send_http_headers()
    send_html_header()

    -- Show error message if present
    if form_data.error_message and form_data.error_message ~= "" then
        print('<p class="alert alert-danger">' .. utils.html_escape(form_data.error_message) .. '</p>')
    end

    print([[
<form action="]] .. utils.html_escape(script_name) .. [[" method="post" class="my-3 needs-validation" novalidate style="max-width:26rem">
<div class="mb-2">
<label class="form-label">Hostname</label>
<input class="form-control bg-light text-dark" type="text" name="hostname" value="]] .. utils.html_escape(form_data.hostname) .. [[" required autocapitalize="none">
<div class="invalid-feedback">Please enter hostname</div>
</div>
<div class="mb-2">
<label class="form-label">Create a password for user <b>root</b></label>
<input class="form-control bg-light text-dark" type="text" name="rootpass" id="rootpass" value="]] .. utils.html_escape(form_data.rootpass) .. [[" required autocapitalize="none">
<div class="invalid-feedback">Please enter password</div>
</div>
<div class="mb-2">
<label class="form-label"><a data-bs-toggle="collapse" href="#collapse-rootpkey" role="button" aria-expanded="false" aria-controls="collapse-rootpkey">Public SSH Key for user <b>root</b></a> <span class="small">(optional)</span></label>
<div class="collapse" id="collapse-rootpkey">
<textarea class="form-control bg-light text-dark text-break" name="rootpkey" id="rootpkey" rows="3">]] .. utils.html_escape(form_data.rootpkey) .. [[</textarea>
</div>
</div>
<ul class="nav nav-underline mb-3" role="tablist">
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link active" aria-current="page" data-bs-toggle="tab" data-bs-target="#wlan-tab-pane" id="wlan-tab">Wi-Fi Network</button></li>
<li class="nav-item" role="presentation"><button type="button" role="tab" class="nav-link" data-bs-toggle="tab" data-bs-target="#wlanap-tab-pane" id="wlanap-tab">Wi-Fi Access Point</button></li>
</ul>
<div class="tab-content" id="wireless-tabs">
<div class="tab-pane fade show active" id="wlan-tab-pane" role="tabpanel" aria-labelledby="wlan-tab" tabindex="0">
<div class="mb-2">
<label class="form-label">Wireless Network Name (SSID)</label>
<input class="form-control bg-light text-dark" type="text" id="wlan_ssid" name="wlan_ssid" value="]] .. utils.html_escape(form_data.wlan_ssid) .. [[" autocapitalize="none" required>
<div class="invalid-feedback">Please enter network name</div>
</div>
<div class="mb-2">
<label class="form-label">Wireless Network Password</label>
<input class="form-control bg-light text-dark" type="text" id="wlan_pass" name="wlan_pass" value="]] .. utils.html_escape(form_data.wlan_pass) .. [[" autocapitalize="none" minlength="8" pattern=".{8,64}" required>
<div class="invalid-feedback">Please enter a password 8 - 64 characters</div>
</div>
</div>
<div class="tab-pane fade" id="wlanap-tab-pane" role="tabpanel" aria-labelledby="wlanap-tab" tabindex="1">
<div class="mb-2 boolean" id="wlanap_enabled_wrap">
<span class="form-check form-switch">
<input type="hidden" id="wlanap_enabled-false" name="wlanap_enabled" value="false">
<input type="checkbox" id="wlanap_enabled" name="wlanap_enabled" value="true" role="switch" class="form-check-input"]] .. (form_data.wlanap_enabled == "true" and " checked" or "") .. [[>
<label for="wlanap_enabled" class="form-check-label">Enable Wireless AP</label>
</span>
</div>
<div class="mb-2">
<label class="form-label">Wireless AP Network Name (SSID)</label>
<input class="form-control bg-light text-dark" type="text" id="wlanap_ssid" name="wlanap_ssid" value="]] .. utils.html_escape(form_data.wlanap_ssid) .. [[" autocapitalize="none">
<div class="invalid-feedback">Please enter network name</div>
</div>
<div class="mb-2">
<label class="form-label">Wireless AP Network Password</label>
<input class="form-control bg-light text-dark" type="text" id="wlanap_pass" name="wlanap_pass" value="]] .. utils.html_escape(form_data.wlanap_pass) .. [[" autocapitalize="none" minlength="8" pattern=".{8,64}">
<div class="invalid-feedback">Please enter a password 8 - 64 characters</div>
</div>
</div>
</div>
<input type="hidden" name="timezone" id="timezone" value="">
<input type="hidden" name="timestamp" value="]] .. utils.html_escape(form_data.timestamp) .. [[">
<input type="hidden" name="mode" value="review">
<input type="submit" value="Save Credentials" class="btn btn-primary my-4">
</form>

<script>
document.querySelector("#timezone").value = Intl.DateTimeFormat().resolvedOptions().timeZone.replaceAll('_', ' ')
document.querySelector("#wlanap_enabled").addEventListener("change", ev => {
    document.querySelector('#wlan_pass').required = !ev.target.checked
    document.querySelector('#wlan_ssid').required = !ev.target.checked
    document.querySelector('#wlanap_pass').required = ev.target.checked
    document.querySelector('#wlanap_ssid').required = ev.target.checked
});
(() => {
    const forms = document.querySelectorAll('.needs-validation');
    Array.from(forms).forEach(form => { form.addEventListener('submit', ev => {
        if (!form.checkValidity()) { ev.preventDefault(); ev.stopPropagation(); }
        form.classList.add('was-validated')}, false)
    })
})()
</script>]])

    send_html_footer(system_info)
end

function send_review_page(form_data, system_info, script_name)
    send_http_headers()
    send_html_header()

    print([[
<div class="alert alert-secondary my-3">
<h3>Ready to connect</h3>
<p>Please double-check the entered data and correct it if you see an error!</p>
<dl class="row" id="verify">]])

    if form_data.wlanap_enabled == "true" then
        print([[
<dt>Wireless AP Network SSID</dt>
<dd>]] .. utils.html_escape(form_data.wlanap_ssid) .. [[</dd>
<dt>Wireless AP Network Password</dt>
<dd class="text-break">]] .. utils.html_escape(form_data.wlanap_pass) .. [[</dd>]])
    else
        print([[
<dt>Wireless Network SSID</dt>
<dd>]] .. utils.html_escape(form_data.wlan_ssid) .. [[</dd>
<dt>Wireless Network Password</dt>
<dd class="text-break">]] .. utils.html_escape(form_data.wlan_pass) .. [[</dd>]])
    end

    print([[
<dt>User <b>root</b> Password</dt>
<dd>]] .. utils.html_escape(form_data.rootpass) .. [[</dd>
<dt>Camera Hostname</dt>
<dd>]] .. utils.html_escape(form_data.hostname) .. [[</dd>]])

    if form_data.timezone and form_data.timezone ~= "" then
        print([[
<dt>Time zone</dt>
<dd>]] .. utils.html_escape(form_data.timezone) .. [[</dd>]])
    end

    if form_data.rootpkey and form_data.rootpkey ~= "" then
        print([[
<dt>User <b>root</b> Public SSH Key</dt>
<dd class="small text-break" id="pkey">]] .. utils.html_escape(form_data.rootpkey) .. [[</dd>]])
    end

    print([[
</dl>

<div class="row text-center">
<div class="col my-2">
<form action="]] .. utils.html_escape(script_name) .. [[" method="POST">
<input type="hidden" name="mode" value="edit">
<input type="hidden" name="hostname" value="]] .. utils.html_escape(form_data.hostname) .. [[">
<input type="hidden" name="rootpass" value="]] .. utils.html_escape(form_data.rootpass) .. [[">
<input type="hidden" name="rootpkey" value="]] .. utils.html_escape(form_data.rootpkey) .. [[">
<input type="hidden" name="timestamp" value="]] .. utils.html_escape(form_data.timestamp) .. [[">
<input type="hidden" name="timezone" value="]] .. utils.html_escape(form_data.timezone) .. [[">
<input type="hidden" name="wlanap_enabled" value="]] .. utils.html_escape(form_data.wlanap_enabled) .. [[">
<input type="hidden" name="wlanap_pass" value="]] .. utils.html_escape(form_data.wlanap_pass) .. [[">
<input type="hidden" name="wlanap_ssid" value="]] .. utils.html_escape(form_data.wlanap_ssid) .. [[">
<input type="hidden" name="wlan_pass" value="]] .. utils.html_escape(form_data.wlan_pass) .. [[">
<input type="hidden" name="wlan_ssid" value="]] .. utils.html_escape(form_data.wlan_ssid) .. [[">
<input type="submit" class="btn btn-danger" value="Edit data">
</form>
</div>
<div class="col my-2">
<form action="]] .. utils.html_escape(script_name) .. [[" method="POST">
<input type="hidden" name="mode" value="save">
<input type="hidden" name="hostname" value="]] .. utils.html_escape(form_data.hostname) .. [[">
<input type="hidden" name="rootpass" value="]] .. utils.html_escape(form_data.rootpass) .. [[">
<input type="hidden" name="rootpkey" value="]] .. utils.html_escape(form_data.rootpkey) .. [[">
<input type="hidden" name="timestamp" value="]] .. utils.html_escape(form_data.timestamp) .. [[">
<input type="hidden" name="timezone" value="]] .. utils.html_escape(form_data.timezone) .. [[">
<input type="hidden" name="wlanap_enabled" value="]] .. utils.html_escape(form_data.wlanap_enabled) .. [[">
<input type="hidden" name="wlanap_pass" value="]] .. utils.html_escape(form_data.wlanap_pass) .. [[">
<input type="hidden" name="wlanap_ssid" value="]] .. utils.html_escape(form_data.wlanap_ssid) .. [[">
<input type="hidden" name="wlan_pass" value="]] .. utils.html_escape(form_data.wlan_pass) .. [[">
<input type="hidden" name="wlan_ssid" value="]] .. utils.html_escape(form_data.wlan_ssid) .. [[">
<input type="submit" class="btn btn-success" value="Proceed">
</form>
</div>
</div>
</div>]])

    send_html_footer(system_info)
end

-- uhttpd expects a handle_request() function
function handle_request(env)
    handle_portal_request(env)
end
