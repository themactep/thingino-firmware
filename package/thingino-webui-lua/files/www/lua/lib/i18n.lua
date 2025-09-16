local i18n = {}

-- Simple language system: one translation file or hardcoded English
local lang_file = "/opt/webui/lang.json"  -- Single language file

-- Valid language codes (for validation)
local valid_languages = {
  "en", "es", "fr", "de", "it", "pt", "ru", "zh", "ja", "ko"
}

-- Validate language code against known valid languages
function i18n.is_valid_language(lang)
  if not lang or lang == "" then
    return false
  end

  for _, valid_lang in ipairs(valid_languages) do
    if valid_lang == lang then
      return true
    end
  end

  return false
end

-- Initialize i18n system
function i18n.init()
  -- Create /opt/webui directory if it doesn't exist
  os.execute("mkdir -p /opt/webui 2>/dev/null")
end

-- Get available languages (all valid languages from built-in packs)
function i18n.get_available_languages()
  -- Return all valid languages that we have built-in support for
  -- This allows users to select any language and download it from GitHub
  return valid_languages
end

-- Set language (download and save to /opt/webui/lang.json)
function i18n.set_language(lang)
  -- Validate language code first
  if not i18n.is_valid_language(lang) then
    return false, "Invalid language code"
  end

  -- For English, remove the language file (use hardcoded text)
  if lang == "en" then
    os.remove(lang_file)
    return true
  end

  -- For other languages, download and save to lang.json
  return i18n.download_language_pack_from_github(lang)
end

-- Get current language (detect from existing file or default to English)
function i18n.get_current_language()
  local file = io.open(lang_file, "r")
  if file then
    local content = file:read("*all")
    file:close()

    -- Try to detect language from content using unique dashboard translations
    -- Check for unique dashboard translations first (most reliable)
    if content:match('"dashboard.title"%s*:%s*"Панель управления"') then
      return "ru"
    elseif content:match('"dashboard.title"%s*:%s*"仪表板"') then
      return "zh"
    elseif content:match('"dashboard.title"%s*:%s*"ダッシュボード"') then
      return "ja"
    elseif content:match('"dashboard.title"%s*:%s*"대시보드"') then
      return "ko"
    elseif content:match('"dashboard.title"%s*:%s*"Tableau de bord"') then
      return "fr"
    elseif content:match('"dashboard.title"%s*:%s*"Painel"') then
      return "pt"
    elseif content:match('"dashboard.title"%s*:%s*"Dashboard"') and content:match('"language.german"') then
      return "de"
    elseif content:match('"dashboard.title"%s*:%s*"Dashboard"') and content:match('"language.italian"') then
      return "it"
    elseif content:match('"dashboard.title"%s*:%s*"Panel"') then
      return "es"
    -- Add more language detection patterns as needed
    else
      return "unknown"  -- File exists but language unknown
    end
  end

  return "en"  -- No file = English
end

-- Alias for compatibility
function i18n.get_language()
  return i18n.get_current_language()
end

-- Get language pack content (only from /opt/webui/lang.json)
function i18n.get_language_pack()
  local file = io.open(lang_file, "r")
  if file then
    local content = file:read("*all")
    file:close()
    return content
  end
  return nil  -- No language file = use English
end

-- Download language pack from GitHub and save to /opt/webui/lang.json
function i18n.download_language_pack_from_github(lang)
  -- Validate language code (security check)
  if not lang or lang == "" or lang:match("[^%w_%-]") then
    return false, "Invalid language code"
  end

  -- GitHub URL for thingino language packs
  local github_base = "https://raw.githubusercontent.com/themactep/thingino-firmware/master/package/thingino-webui-lua/files/lang_packs"
  local url = github_base .. "/" .. lang .. ".json"

  -- Ensure directory exists
  os.execute("mkdir -p /opt/webui 2>/dev/null")

  -- Download directly to /opt/webui/lang.json (overwrites any existing language)
  local cmd = "curl -s -o " .. lang_file .. " '" .. url .. "'"
  local exit_code = os.execute(cmd)

  -- Debug: Log the command and result
  local debug_file = io.open("/tmp/i18n_debug.log", "a")
  if debug_file then
    debug_file:write(os.date() .. " - Download command: " .. cmd .. "\n")
    debug_file:write(os.date() .. " - Exit code: " .. tostring(exit_code) .. "\n")
    debug_file:close()
  end

  -- In Lua, os.execute() returns true for success, not 0
  if not exit_code then
    return false, "Failed to download language pack from GitHub"
  end

  -- Basic validation - check if it's a JSON file
  local file = io.open(lang_file, "r")
  if file then
    local content = file:read("*all")
    file:close()

    -- Simple JSON validation
    if content:match("^%s*{.*}%s*$") then
      return true, "Language pack downloaded successfully from GitHub"
    else
      os.remove(lang_file)
      return false, "Invalid language pack format"
    end
  end

  return false, "Failed to validate downloaded language pack"
end

-- Simple translation function: use lang.json if exists, otherwise return key
function i18n.t(key, vars)
  local content = i18n.get_language_pack()
  if not content then
    -- No language file = return English key as-is
    local text = key

    -- Variable substitution for English
    if vars and type(vars) == "table" then
      for var_key, var_value in pairs(vars) do
        text = text:gsub("{{" .. var_key .. "}}", tostring(var_value))
      end
    end

    return text
  end

  -- Parse JSON and get translation
  local translations = {}
  for json_key, value in content:gmatch('"([^"]+)"%s*:%s*"([^"]*)"') do
    value = value:gsub('\\"', '"')  -- Handle escaped quotes
    translations[json_key] = value
  end

  local text = translations[key] or key  -- Fallback to key if not found

  -- Variable substitution
  if vars and type(vars) == "table" then
    for var_key, var_value in pairs(vars) do
      text = text:gsub("{{" .. var_key .. "}}", tostring(var_value))
    end
  end

  return text
end

-- Get language display names
function i18n.get_language_names()
  local names = {
    en = "English",
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

  return names
end

return i18n