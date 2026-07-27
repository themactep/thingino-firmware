#!/usr/bin/env lua

-- Test script for i18n functionality
package.path = package.path .. ";/var/www/lua/lib/?.lua"

local i18n = require("i18n")
local utils = require("utils")

print("=== Testing Thingino Web UI Localization ===")

-- Initialize i18n system
print("\n1. Initializing i18n system...")
i18n.init()

-- Test available languages
print("\n2. Available languages:")
local available = i18n.get_available_languages()
for _, lang in ipairs(available) do
    print("  - " .. lang)
end

-- Test language names
print("\n3. Language display names:")
local names = i18n.get_language_names()
for lang, name in pairs(names) do
    print("  - " .. lang .. ": " .. name)
end

-- Test translation keys
print("\n4. Testing translation keys:")
local test_keys = {
    "common.save",
    "common.cancel", 
    "dashboard.title",
    "nav.dashboard",
    "language.current",
    "nonexistent.key"
}

for _, key in ipairs(test_keys) do
    local translation = i18n.t(key)
    print("  - " .. key .. " = '" .. translation .. "'")
end

-- Test language switching
print("\n5. Testing language switching:")
print("Current language: " .. i18n.get_language())

if i18n.set_language("es") then
    print("Switched to Spanish")
    print("dashboard.title = '" .. i18n.t("dashboard.title") .. "'")
    print("common.save = '" .. i18n.t("common.save") .. "'")
else
    print("Failed to switch to Spanish")
end

-- Switch back to English
if i18n.set_language("en") then
    print("Switched back to English")
    print("dashboard.title = '" .. i18n.t("dashboard.title") .. "'")
else
    print("Failed to switch back to English")
end

-- Test template translation
print("\n6. Testing template translation:")
local test_template = "Welcome to {{t:dashboard.title}}! Click {{t:common.save}} to continue."
local translated = utils.translate_template(test_template)
print("Template: " .. test_template)
print("Translated: " .. translated)

-- Test variable substitution
print("\n7. Testing variable substitution:")
local test_with_vars = i18n.t("error.template_not_found", {template = "test.html"})
print("With variables: " .. test_with_vars)

print("\n=== Test completed ===")
