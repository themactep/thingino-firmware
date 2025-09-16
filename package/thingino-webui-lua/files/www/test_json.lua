#!/usr/bin/env lua

-- Test the JSON parser
package.path = package.path .. ";/var/www/lua/lib/?.lua"

-- Simple JSON decoder for language packs
local function decode_json(content)
  -- Remove comments and normalize whitespace
  content = content:gsub("//.-\n", ""):gsub("%s+", " "):gsub("^%s+", ""):gsub("%s+$", "")
  
  -- Check if it's a JSON object
  if not content:match("^{.*}$") then return nil end
  
  local result = {}
  
  -- Extract content between braces
  local inner = content:match("^{(.*)}$")
  if not inner then return nil end
  
  -- Split by commas, but be careful about commas inside strings
  local items = {}
  local current = ""
  local in_string = false
  local escape_next = false
  
  for i = 1, #inner do
    local char = inner:sub(i, i)
    
    if escape_next then
      current = current .. char
      escape_next = false
    elseif char == "\\" then
      current = current .. char
      escape_next = true
    elseif char == '"' then
      current = current .. char
      in_string = not in_string
    elseif char == ',' and not in_string then
      table.insert(items, current:gsub("^%s+", ""):gsub("%s+$", ""))
      current = ""
    else
      current = current .. char
    end
  end
  
  -- Add the last item
  if current:gsub("^%s+", ""):gsub("%s+$", "") ~= "" then
    table.insert(items, current:gsub("^%s+", ""):gsub("%s+$", ""))
  end
  
  -- Parse each key-value pair
  for _, item in ipairs(items) do
    local key, value = item:match('^"([^"]+)"%s*:%s*"([^"]*)"')
    if key and value then
      -- Unescape common JSON escape sequences
      value = value:gsub('\\"', '"'):gsub('\\\\', '\\'):gsub('\\/', '/'):gsub('\\n', '\n'):gsub('\\t', '\t')
      result[key] = value
    end
  end
  
  return result
end

print("Testing JSON parser...")

-- Test with a simple JSON
local test_json = '{"test.key": "Test Value", "another.key": "Another Value"}'
local result = decode_json(test_json)

if result then
  print("Success! Parsed keys:")
  for k, v in pairs(result) do
    print("  " .. k .. " = " .. v)
  end
else
  print("Failed to parse JSON")
end

-- Test with the actual language file
print("\nTesting with language file...")
local file = io.open("/var/www/lang_packs/en.json", "r")
if file then
  local content = file:read("*all")
  file:close()
  
  local lang_data = decode_json(content)
  if lang_data then
    print("Successfully parsed language file!")
    print("Found " .. table.getn(lang_data) .. " translation keys")
    print("Sample keys:")
    local count = 0
    for k, v in pairs(lang_data) do
      if count < 5 then
        print("  " .. k .. " = " .. v)
        count = count + 1
      end
    end
  else
    print("Failed to parse language file")
  end
else
  print("Could not open language file")
end
