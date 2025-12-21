# Thingino Web UI Localization

This document describes the internationalization (i18n) system implemented in the Thingino Web UI.

## Overview

The localization system provides:
- Multi-language support with JSON-based language packs
- Template-based translation with `{{t:key}}` syntax
- Language persistence across sessions
- Dynamic language pack downloading
- Built-in language packs and user-downloadable packs

## Architecture

### Core Components

1. **i18n Module** (`/var/www/lua/lib/i18n.lua`)
   - Translation key resolution
   - Language pack loading
   - Language switching
   - Variable substitution

2. **Template Integration** (`/var/www/lua/lib/utils.lua`)
   - `{{t:key}}` syntax processing
   - Variable substitution in translations
   - Integration with existing template system

3. **Language Selector** (`/var/www/lua/templates/common/language_selector.html`)
   - Dropdown language switcher
   - Language pack download modal
   - Dynamic language menu population

4. **API Endpoints**
   - `GET /lua/api/language/list` - List available languages
   - `POST /lua/api/language/set` - Switch language
   - `POST /lua/api/language/download` - Download language pack

## Usage

### In Templates

Use translation keys in HTML templates:

```html
<!-- Simple translation -->
<h1>{{t:dashboard.title}}</h1>

<!-- Translation with variables -->
<p>{{t:error.template_not_found:template=config.html}}</p>

<!-- Common UI elements -->
<button>{{t:common.save}}</button>
<button>{{t:common.cancel}}</button>
```

### In Lua Code

```lua
local i18n = require("lib.i18n")

-- Get translation
local text = i18n.t("common.save")

-- Translation with variables
local error_msg = i18n.t("error.template_not_found", {template = "test.html"})

-- Switch language
i18n.set_language("es")
```

## Language Packs

### Structure

Language packs are JSON files with key-value pairs:

```json
{
  "common.save": "Save",
  "common.cancel": "Cancel",
  "dashboard.title": "Dashboard",
  "nav.dashboard": "Dashboard",
  "error.template_not_found": "Template not found: {{template}}"
}
```

### Key Naming Convention

Use hierarchical dot notation:
- `common.*` - Common UI elements (buttons, labels)
- `nav.*` - Navigation items
- `dashboard.*` - Dashboard-specific strings
- `config.*` - Configuration pages
- `error.*` - Error messages
- `success.*` - Success messages
- `language.*` - Language selector strings

### Built-in Languages

Built-in language packs are stored in `/var/www/lang_packs/`:
- `en.json` - English (default)
- `es.json` - Spanish (example)

### User Language Packs

Downloaded language packs are stored in `/tmp/lang_packs/` and loaded dynamically.

## Language Persistence

The current language preference is saved to `/etc/webui_language` and restored on system restart.

## Adding New Languages

### Method 1: Built-in Language Pack

1. Create a new JSON file in `/var/www/lang_packs/`
2. Follow the key naming convention
3. Add language display name to `i18n.get_language_names()`

### Method 2: Downloadable Language Pack

1. Create JSON language pack file
2. Host it on a web server
3. Use the language selector's "Download new language" feature
4. Provide language code and URL

## Translation Key Guidelines

### Key Structure
- Use lowercase with dots as separators
- Group related keys under common prefixes
- Keep keys descriptive but concise

### Value Guidelines
- Use proper capitalization for the target language
- Include punctuation as appropriate
- Use `{{variable}}` syntax for dynamic content
- Keep translations concise for UI space constraints

### Variable Substitution

Variables in translations use `{{variable}}` syntax:

```json
{
  "welcome.message": "Welcome, {{username}}!",
  "file.size": "File size: {{size}} bytes",
  "error.template_not_found": "Template not found: {{template}}"
}
```

## Testing

Run the test script to verify localization functionality:

```bash
lua /var/www/test_i18n.lua
```

## Integration with Existing Code

The localization system integrates seamlessly with the existing template system:

1. Templates are processed for includes first
2. Variable substitution happens next
3. Translation processing occurs last
4. All `{{t:key}}` patterns are replaced with translated text

## Performance Considerations

- Language packs are loaded once at startup
- Translations are cached in memory
- Template translation happens during template processing
- No runtime file I/O for translations

## Security

- Language codes are validated to prevent path traversal
- Downloaded URLs are properly escaped
- Language pack JSON is validated before loading
- File operations use safe paths

## Future Enhancements

Potential improvements:
- Pluralization support
- Date/time localization
- Number formatting
- RTL language support
- Language pack validation tools
- Translation management interface
