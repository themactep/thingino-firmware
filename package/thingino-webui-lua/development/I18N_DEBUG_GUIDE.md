# 🌍 i18n Debug Tools Guide

Visual debugging tools to identify localization coverage and gaps in the thingino webui.

## 🚀 Quick Start

### Method 1: URL Parameter (Easiest)
Add `?debug_i18n=1` to any page URL:
```
http://192.168.1.109/lua/dashboard?debug_i18n=1
http://192.168.1.109/lua/config/system?debug_i18n=1
```

### Method 2: Standalone Debug Page
Visit the dedicated debug page:
```
http://192.168.1.109/debug_i18n_highlighting.html
```

### Method 3: Bookmarklet (Any Page)
1. Copy the content of `i18n_debug_bookmarklet.js`
2. Create a bookmark with URL: `javascript:(paste_code_here)`
3. Click the bookmark on any page

## 🎨 Visual Indicators

| Color | Meaning | Description |
|-------|---------|-------------|
| 🟢 **Green** | `data-i18n` | Properly localized elements |
| 🔵 **Blue** | `data-i18n-placeholder` | Localized placeholders |
| 🟠 **Orange** | `data-i18n-title` | Localized titles/tooltips |
| 🔴 **Red** | Missing i18n | Elements that need localization |

## 🛠️ Features

### Highlighting Controls
- **Enable Highlighting**: Show all localized elements with green outlines
- **Find Missing**: Detect and highlight elements needing localization
- **Next Localized/Missing**: Navigate through highlighted elements

### Statistics Panel
Real-time counts of:
- Localized elements (`data-i18n`)
- Placeholder elements (`data-i18n-placeholder`)
- Title elements (`data-i18n-title`)
- Missing localization elements

### Export Report
Generate detailed JSON reports containing:
- Element statistics
- List of all localized elements with their keys
- List of elements needing localization
- Page URL and timestamp

## 🔍 What Gets Detected as "Missing"

The tool intelligently identifies elements that likely need localization:

### ✅ Detected Elements
- Headers (`h1`, `h2`, `h3`, `h4`, `h5`, `h6`)
- Labels (`label`, `.form-label`)
- Buttons (`button`, `.btn`)
- Form help text (`.form-text`)
- Card titles (`.card-title`)
- Navigation links (`.nav-link`)
- Dropdown items (`.dropdown-item`)
- Alerts (`.alert`)
- Table headers (`th`)
- Badges (`.badge`)

### ❌ Ignored Elements
- Empty or very short text (< 2 characters)
- Numbers only (`123`, `45.67%`)
- Technical terms (`API`, `JSON`, `404`)
- Template variables (`{{variable}}`, `${var}`)
- Function calls (`function()`)
- Already localized elements

## 📊 Usage Examples

### Finding Localization Gaps
1. Navigate to any page
2. Add `?debug_i18n=1` to URL
3. Click "Find Missing" in the debug panel
4. Use "Next Missing" to review each unlocalized element
5. Add appropriate `data-i18n` attributes

### Verifying Localization Coverage
1. Enable highlighting on a page
2. Check the statistics panel
3. Export report for detailed analysis
4. Compare before/after localization work

### Development Workflow
1. Work on localizing a page
2. Use debug tools to verify coverage
3. Export report to track progress
4. Commit changes with statistics

## 🎯 Best Practices

### For Developers
- Always test with debug tools before committing localization
- Aim for 100% coverage on user-facing text
- Use the export feature to document progress
- Check both desktop and mobile layouts

### For Translators
- Use the tools to identify missing translations
- Verify that all text is properly marked for translation
- Test language switching with visual feedback

## 🔧 Technical Details

### CSS Classes Added
- `.i18n-debug-highlight` - Green outline for localized elements
- `.i18n-debug-missing` - Red outline for missing localization
- `.i18n-debug-placeholder` - Blue outline for placeholders
- `.i18n-debug-title` - Orange outline for titles

### JavaScript API
```javascript
// Access debug functions
window.i18nDebug.toggleHighlighting()
window.i18nDebug.toggleMissingDetection()
window.i18nDebug.exportReport()
window.i18nDebug.scrollToNext('localized')
window.i18nDebug.scrollToNext('missing')
```

## 📈 Interpreting Results

### Good Coverage
- High ratio of localized to missing elements
- Most user-facing text has green outlines
- Few or no red outlines on important elements

### Needs Work
- Many red outlines on buttons, labels, headers
- Low localized count relative to page content
- Missing localization on critical UI elements

## 🚨 Troubleshooting

### Debug Panel Not Appearing
- Check browser console for errors
- Ensure JavaScript is enabled
- Try refreshing the page
- Verify the URL parameter is correct

### False Positives in "Missing"
- Some technical elements may be flagged incorrectly
- Use judgment to determine if localization is needed
- The tool errs on the side of flagging more rather than less

### Performance Impact
- Debug tools add visual overlays and DOM scanning
- Disable when not needed for better performance
- Only use during development/testing

## 📝 Example Report Output

```json
{
  "timestamp": "2024-01-15T10:30:00.000Z",
  "url": "http://192.168.1.109/lua/config/system",
  "stats": {
    "localized": 45,
    "missing": 3,
    "placeholders": 8,
    "titles": 2
  },
  "localized": [
    {
      "tag": "h1",
      "key": "config.system.title",
      "text": "System Overview"
    }
  ],
  "missing": [
    {
      "tag": "button",
      "text": "Save Changes"
    }
  ]
}
```

This comprehensive debugging system helps ensure complete localization coverage across the thingino webui! 🌍
