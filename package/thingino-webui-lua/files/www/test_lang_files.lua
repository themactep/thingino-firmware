#!/usr/bin/env lua

-- Test language file access
package.path = package.path .. ";/var/www/lua/lib/?.lua"

local i18n = require("i18n")

print("=== Testing Language File Access ===")

-- Test paths
local builtin_lang_dir = "/var/www/lang_packs"
local lang_packs_dir = "/tmp/lang_packs"

print("\n1. Testing directory access:")
print("Built-in dir: " .. builtin_lang_dir)
print("Downloaded dir: " .. lang_packs_dir)

-- Check if directories exist
local function dir_exists(path)
    local handle = io.popen("ls -la " .. path .. " 2>/dev/null")
    if handle then
        local result = handle:read("*a")
        handle:close()
        return result ~= ""
    end
    return false
end

print("Built-in dir exists: " .. (dir_exists(builtin_lang_dir) and "YES" or "NO"))
print("Downloaded dir exists: " .. (dir_exists(lang_packs_dir) and "YES" or "NO"))

-- List files in directories
print("\n2. Files in built-in directory:")
local handle = io.popen("ls -la " .. builtin_lang_dir .. " 2>/dev/null")
if handle then
    local result = handle:read("*a")
    handle:close()
    print(result ~= "" and result or "Directory empty or not accessible")
else
    print("Cannot access directory")
end

print("\n3. Files in downloaded directory:")
handle = io.popen("ls -la " .. lang_packs_dir .. " 2>/dev/null")
if handle then
    local result = handle:read("*a")
    handle:close()
    print(result ~= "" and result or "Directory empty or not accessible")
else
    print("Cannot access directory")
end

-- Test specific file access
print("\n4. Testing specific file access:")
local test_files = {
    builtin_lang_dir .. "/en.json",
    builtin_lang_dir .. "/es.json",
    lang_packs_dir .. "/en.json"
}

for _, file_path in ipairs(test_files) do
    local file = io.open(file_path, "r")
    if file then
        local content = file:read("*all")
        file:close()
        print(file_path .. ": EXISTS (" .. #content .. " bytes)")
        -- Show first 100 characters
        print("  Preview: " .. content:sub(1, 100) .. (#content > 100 and "..." or ""))
    else
        print(file_path .. ": NOT FOUND")
    end
end

-- Test i18n functions
print("\n5. Testing i18n functions:")
i18n.init()

print("Available languages: " .. table.concat(i18n.get_available_languages(), ", "))

local en_pack = i18n.get_language_pack("en")
if en_pack then
    print("English pack loaded: " .. #en_pack .. " bytes")
else
    print("English pack: NOT FOUND")
end

local es_pack = i18n.get_language_pack("es")
if es_pack then
    print("Spanish pack loaded: " .. #es_pack .. " bytes")
else
    print("Spanish pack: NOT FOUND")
end

print("\n=== Test completed ===")
