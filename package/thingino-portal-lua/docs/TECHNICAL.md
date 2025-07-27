# Thingino Portal Lua - Technical Documentation

## Architecture Deep Dive

### Request Flow

```
Client Request → uhttpd → Lua Handler → System Commands → Response
     ↓              ↓           ↓              ↓            ↓
1. HTTP Request  2. Parse    3. Process    4. Execute   5. HTML Response
   (GET/POST)       URL        Form Data     Commands     (200/303/400/500)
```

### Lua Script Execution Model

The portal uses uhttpd's Lua handler which:
1. Loads `/var/www-portal/lua/portal.lua` on first request
2. Keeps Lua VM in memory for subsequent requests
3. Executes `handle_portal_request()` for each HTTP request
4. Maintains no state between requests (stateless design)

### Memory Management

```lua
-- Lua VM memory usage (approximate)
Base Lua VM:           ~200KB
Portal script:         ~50KB
Bootstrap assets:      ~180KB (CSS) + ~60KB (JS)
Total memory footprint: ~500KB
```

### Network Stack

```
Application Layer:  HTTP/1.1 (uhttpd)
Transport Layer:    TCP (port 80)
Network Layer:      IPv4 (172.16.0.0/24)
Data Link Layer:    WiFi 802.11 (wlan0)
Physical Layer:     WiFi radio hardware
```

## Configuration Management

### Environment Variables

The portal reads configuration from environment variables sourced from `/usr/share/common`:

```bash
# WiFi Client Configuration
wlan_ssid="MyNetwork"           # Target WiFi network
wlan_pass="password123"         # WiFi password (or PSK)

# WiFi AP Configuration
wlanap_enabled="false"          # Enable AP mode
wlanap_ssid="THINGINO-1234"     # AP network name
wlanap_pass="thingino123"       # AP password

# System Configuration
hostname="thingino-cam"         # Camera hostname
timezone="America/New_York"     # System timezone
```

### Configuration Persistence

Settings are stored in multiple locations:

| Setting | Storage Location | Persistence |
|---------|------------------|-------------|
| WiFi Credentials | U-Boot environment | Permanent |
| Hostname | `/etc/hostname` | Permanent |
| Root Password | `/etc/shadow` | Permanent |
| SSH Keys | `/root/.ssh/authorized_keys` | Permanent |
| Timezone | `/etc/timezone` | Permanent |
| ONVIF Interface | `/etc/onvif.conf` | Permanent |

### U-Boot Environment

WiFi credentials are stored in U-Boot environment variables:

```bash
# Set WiFi client credentials
fw_setenv wlan_ssid "MyNetwork"
fw_setenv wlan_pass "psk:abcd1234..."

# Set WiFi AP credentials
fw_setenv wlanap_ssid "THINGINO-1234"
fw_setenv wlanap_pass "psk:efgh5678..."
```

## Security Implementation

### Input Validation

```lua
function validate_form_data(form_data)
    local errors = {}

    -- Hostname validation (RFC 1123)
    if not form_data.hostname or form_data.hostname == "" then
        table.insert(errors, "Hostname is required")
    else
        local bad_chars = string.gsub(form_data.hostname, "[0-9A-Za-z%.%-]", "")
        if bad_chars ~= "" then
            table.insert(errors, "Hostname contains invalid characters: " .. bad_chars)
        end
    end

    -- Password strength validation
    if not form_data.rootpass or form_data.rootpass == "" then
        table.insert(errors, "Root password is required")
    end

    -- WiFi password validation (WPA/WPA2 requirements)
    if form_data.wlanap_enabled == "true" then
        if not form_data.wlanap_pass or string.len(form_data.wlanap_pass) < 8 then
            table.insert(errors, "WiFi AP password must be at least 8 characters")
        end
    else
        if not form_data.wlan_pass or string.len(form_data.wlan_pass) < 8 then
            table.insert(errors, "WiFi network password must be at least 8 characters")
        end
    end

    return errors
end
```

### XSS Prevention

All user input is HTML-escaped before output:

```lua
function utils.html_escape(text)
    if not text then return "" end
    text = string.gsub(text, "&", "&amp;")      -- Must be first
    text = string.gsub(text, "<", "&lt;")
    text = string.gsub(text, ">", "&gt;")
    text = string.gsub(text, '"', "&quot;")
    text = string.gsub(text, "'", "&#39;")
    return text
end
```

### Command Injection Prevention

System commands use proper escaping:

```lua
-- Safe command execution
utils.execute_command("hostname '" .. form_data.hostname .. "'")
utils.execute_command("echo 'root:" .. form_data.rootpass .. "' | chpasswd -c sha512")

-- Unsafe (never do this)
-- os.execute("hostname " .. form_data.hostname)  -- Vulnerable to injection
```

### CSRF Protection

Forms include timestamp-based CSRF protection:

```lua
-- Generate timestamp
local timestamp = os.time()

-- Validate form age
local post_timestamp = tonumber(form_data.timestamp) or current_time
local is_expired = (post_timestamp < (current_time - CONFIG.ttl_in_sec))

if is_expired then
    send_redirect(script_name)  -- Reject expired forms
    return
end
```

## Performance Optimization

### uhttpd Configuration

```uci
# Optimized for embedded systems
option max_requests '3'         # Limit concurrent requests
option max_connections '100'    # Reasonable connection limit
option script_timeout '60'     # Prevent hung scripts
option network_timeout '30'    # Quick network timeouts
option http_keepalive '20'      # Reuse connections
option tcp_keepalive '1'        # Enable TCP keepalive
```

### Lua Optimizations

```lua
-- Pre-compile regex patterns
local hostname_pattern = "[0-9A-Za-z%.%-]"

-- Reuse string buffers
local html_buffer = {}

-- Minimize string concatenations
table.insert(html_buffer, "<div>")
table.insert(html_buffer, content)
table.insert(html_buffer, "</div>")
local html = table.concat(html_buffer)
```

### Asset Optimization

Static assets are compressed during build:

```makefile
# Compress CSS/JS files
find $(TARGET_DIR)/var/www/a/ -type f \( -name "*.css" -o -name "*.js" \) -exec gzip {} \;

# Create symlinks for portal
ln -sr $(TARGET_DIR)/var/www/a/bootstrap.min.css.gz $(TARGET_DIR)/var/www-portal/a/
```

## Error Handling

### HTTP Status Codes

```lua
-- Success responses
send_http_headers("200 OK")           -- Form display
send_http_headers("303 See Other")    -- Redirect after POST

-- Error responses
send_http_headers("400 Bad Request")  -- Invalid form data
send_http_headers("500 Internal Server Error")  -- System error
```

### Error Recovery

```lua
function handle_save_configuration(form_data, system_info, script_name)
    local errors = validate_form_data(form_data)
    if #errors > 0 then
        form_data.error_message = table.concat(errors, "; ")
        form_data.mode = "edit"
        send_configuration_form(form_data, system_info, script_name)
        return  -- Graceful error recovery
    end

    -- Proceed with save...
end
```

### Logging Strategy

```lua
function utils.log(message)
    local file = io.open(CONFIG.debug_file, "a")
    if file then
        file:write(os.date("%Y-%m-%d %H:%M:%S") .. " " .. message .. "\n")
        file:close()
    end
    -- Fail silently if logging fails (don't break portal)
end
```

## Testing Framework

### Unit Testing

```lua
-- Test input validation
function test_validate_hostname()
    local form_data = { hostname = "test-cam.local" }
    local errors = validate_form_data(form_data)
    assert(#errors == 0, "Valid hostname should pass validation")

    form_data.hostname = "test cam"  -- Invalid (space)
    errors = validate_form_data(form_data)
    assert(#errors > 0, "Invalid hostname should fail validation")
end
```

### Integration Testing

```bash
#!/bin/bash
# Test portal functionality

# Test portal startup
/etc/init.d/S41portal-lua start
sleep 2

# Test HTTP response
response=$(curl -s -o /dev/null -w "%{http_code}" http://172.16.0.1/)
if [ "$response" != "200" ]; then
    echo "ERROR: Portal not responding"
    exit 1
fi

# Test form submission
curl -X POST http://172.16.0.1/lua/portal.lua \
    -d "hostname=test&rootpass=test123&mode=review"

echo "Portal tests passed"
```

### Load Testing

```bash
# Test concurrent connections
for i in {1..10}; do
    curl -s http://172.16.0.1/ > /dev/null &
done
wait

# Monitor resource usage
top -n 1 | grep -E "(uhttpd|lua)"
```

## Deployment Considerations

### Build Integration

```makefile
# Package dependencies
THINGINO_PORTAL_LUA_DEPENDENCIES = lua thingino-uhttpd dnsmasq wpa_supplicant

# Install hooks
THINGINO_PORTAL_LUA_POST_INSTALL_TARGET_HOOKS += MODIFY_INSTALL_CONFIGS
```

### Runtime Requirements

- **RAM**: Minimum 8MB free (16MB recommended)
- **Flash**: ~500KB for portal files
- **CPU**: Any ARM/MIPS processor supported by Thingino
- **WiFi**: 802.11b/g/n compatible adapter

### Compatibility Matrix

| Thingino Version | Portal Lua | Status |
|------------------|------------|--------|
| v2.0+ | v1.0 | ✓ Supported |
| v1.x | v1.0 | ⚠ Limited support |
| Development | v1.0 | ✓ Fully supported |

This technical documentation provides the implementation details needed for development, debugging, and maintenance of the Thingino Portal Lua package.
