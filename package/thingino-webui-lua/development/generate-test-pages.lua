#!/usr/bin/env lua

-- Simple script to generate static HTML pages for testing
-- This bypasses the complex development server issues

package.path = "../files/www/lua/lib/?.lua;" .. package.path

-- Mock uhttpd global
uhttpd = {
    send = function(data)
        io.write(data)
    end
}

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

-- Fix template loading for development
dev_utils.load_template = function(template_name, vars)
    local template_path = "package/thingino-webui-lua/files/www/lua/templates/" .. template_name .. ".html"
    local file = io.open(template_path, "r")

    if not file then
        return "<h1>Template not found: " .. template_name .. " at " .. template_path .. "</h1>"
    end

    local content = file:read("*all")
    file:close()

    -- Simple template variable replacement
    if vars then
        for key, value in pairs(vars) do
            local pattern = "{{%s*" .. key .. "%s*}}"
            content = content:gsub(pattern, tostring(value))
        end
    end

    return content
end

-- Replace utils in package.loaded
package.loaded["utils"] = dev_utils

-- Load required modules
local session = require("session")
local auth = require("auth")
local config = require("config")

-- Create test output directory and copy CSS
os.execute("mkdir -p test-output/static/css")
os.execute("cp package/thingino-webui-lua/files/www/static/css/thingino.css test-output/static/css/")

-- Function to generate a page
local function generate_page(page_name, request_uri, authenticated)
    print("Generating " .. page_name .. "...")
    
    -- Capture output
    local output = {}
    local original_send = uhttpd.send
    uhttpd.send = function(data)
        table.insert(output, data)
    end
    
    -- Load main handler
    dofile("../files/www/lua/main.lua")
    
    -- Create mock session if authenticated
    local mock_session = nil
    if authenticated then
        mock_session = {
            id = "test_session",
            user = "root",
            created = os.time(),
            last_activity = os.time(),
            remote_addr = "127.0.0.1"
        }
    end
    
    -- Mock session.get function
    local original_session_get = session.get
    session.get = function(env)
        return mock_session
    end
    
    -- Parse query string from URI
    local path = request_uri
    local query = ""
    if request_uri:find("?") then
        path = request_uri:match("([^?]+)")
        query = request_uri:match("?(.+)") or ""
    end

    -- Create environment
    local env = {
        REQUEST_URI = request_uri,
        REQUEST_METHOD = "GET",
        QUERY_STRING = query,
        REMOTE_ADDR = "127.0.0.1",
        HTTP_HOST = "localhost"
    }
    
    -- Handle the request
    local success, error_msg = pcall(function()
        handle_request(env)
    end)
    
    -- Restore original functions
    uhttpd.send = original_send
    session.get = original_session_get
    
    if success then
        local response_data = table.concat(output)
        
        -- Extract HTML content (skip headers)
        local html_start = response_data:find("<!DOCTYPE")
        if html_start then
            local html_content = response_data:sub(html_start)
            
            -- Write to file
            local filename = "test-output/" .. page_name .. ".html"
            local file = io.open(filename, "w")
            if file then
                file:write(html_content)
                file:close()
                print("✅ Generated: " .. filename)
            else
                print("❌ Failed to write: " .. filename)
            end
        else
            print("❌ No HTML content found for " .. page_name)
            print("Response:", response_data:sub(1, 200))
        end
    else
        print("❌ Error generating " .. page_name .. ": " .. (error_msg or "unknown"))
    end
end

-- Generate test pages
print("🚀 Generating test pages...")
print()

-- Generate login page (no auth required)
generate_page("login", "/lua/login", false)

-- Generate authenticated pages
generate_page("dashboard", "/lua/dashboard", true)
generate_page("config-camera", "/lua/config-camera", true)
generate_page("config-network", "/lua/config-network", true)
generate_page("config-system", "/lua/config-system", true)
generate_page("info", "/lua/info", true)
generate_page("info-network", "/lua/info?network", true)
generate_page("info-camera", "/lua/info?camera", true)
generate_page("info-logs", "/lua/info?logs", true)
generate_page("preview", "/lua/preview", true)

print()
print("🎉 Test pages generated in test-output/ directory")
print("📁 Open test-output/login.html in your browser to test")
print("💡 These are static files for testing the UI and templates")
