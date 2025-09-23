#!/usr/bin/env lua

-- Test template processing with includes and translations
package.path = package.path .. ";/var/www/lua/lib/?.lua"

local utils = require("utils")
local i18n = require("i18n")

print("=== Testing Template Processing with Includes and Translations ===")

-- Initialize i18n
print("\n1. Initializing i18n...")
i18n.init()

print("Current language: " .. i18n.get_language())
print("Available languages: " .. table.concat(i18n.get_available_languages(), ", "))

-- Test simple translation
print("\n2. Testing simple translation:")
print("dashboard.title = '" .. i18n.t("dashboard.title") .. "'")
print("common.save = '" .. i18n.t("common.save") .. "'")

-- Test template translation
print("\n3. Testing template translation:")
local test_content = "Welcome to {{t:dashboard.title}}! Click {{t:common.save}} to continue."
local translated = utils.translate_template(test_content)
print("Original: " .. test_content)
print("Translated: " .. translated)

-- Test include processing
print("\n4. Testing include processing:")
local include_test = "Before include\n{{include:language_selector}}\nAfter include"
local processed = utils.process_includes(include_test)
print("Include processed successfully: " .. (processed:find("dropdown") and "YES" or "NO"))

-- Test full template loading (if we can access the template)
print("\n5. Testing full template processing:")
local template_content = [[
<h1>{{t:dashboard.title}}</h1>
<p>{{t:dashboard.welcome}}</p>
<div>{{include:language_selector}}</div>
]]

-- Simulate template processing
local step1 = utils.process_includes(template_content)
print("After includes: " .. (step1:find("dropdown") and "Include processed" or "Include NOT processed"))

local step2 = utils.translate_template(step1)
print("After translation: " .. (step2:find("Dashboard") and "Translation processed" or "Translation NOT processed"))

print("\n=== Test completed ===")
