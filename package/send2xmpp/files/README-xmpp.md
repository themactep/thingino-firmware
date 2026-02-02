# send2xmpp - Pure Shell XMPP Client

Send messages and notifications to XMPP (Jabber) servers using only shell scripting and curl.

## Features

- ✅ Pure shell script (no Python, Perl, or other dependencies)
- ✅ Uses XMPP over BOSH (HTTP) - works with curl
- ✅ SASL PLAIN authentication
- ✅ Send text messages
- ✅ TLS 1.2 support for mbedTLS compatibility
- ✅ Image upload via XEP-0363 HTTP Upload
- ✅ Automatic upload component discovery

## Requirements

- `curl` with TLS support
- XMPP server with BOSH enabled (Prosody, ejabberd, Openfire, etc.)

## Installation

1. Copy `send2xmpp` to your device:
```bash
cp send2xmpp /usr/bin/
chmod +x /usr/bin/send2xmpp
```

2. Create configuration file:
```bash
cp send2xmpp.conf.example /etc/send2xmpp.conf
vi /etc/send2xmpp.conf
```

3. Edit configuration with your XMPP credentials:
```bash
XMPP_JID="camera@xmpp.example.com"
XMPP_PASSWORD="your-password"
XMPP_RECIPIENT="you@xmpp.example.com"
XMPP_BOSH_URL="https://xmpp.example.com:5281/http-bind"
```

## Usage

### Send a simple message
```bash
send2xmpp -m "Motion detected!"
```

### Send from stdin
```bash
echo "Camera started" | send2xmpp
```

### Send with verbose output
```bash
send2xmpp -v -m "Test message"
```

### Send an image with caption
```bash
send2xmpp -i /tmp/motion.jpg -m "Motion detected at $(date)"
```

### Send an image without caption
```bash
send2xmpp -i /tmp/snapshot.jpg
```

### Integration with motion detection
```bash
# In your motion script:
MOTION_PHOTO_FILE=/tmp/motion.jpg
send2xmpp -i "$MOTION_PHOTO_FILE" -m "Motion detected at $(date)"
```

## XMPP Server Setup

### Prosody (Recommended)

1. Enable BOSH and HTTP Upload modules in `/etc/prosody/prosody.cfg.lua`:
```lua
modules_enabled = {
    -- ... other modules
    "bosh";
    "http_upload";  -- For image upload support
}

-- BOSH configuration
consider_bosh_secure = true
cross_domain_bosh = true

-- HTTP Upload configuration
http_upload_file_size_limit = 10485760  -- 10MB
http_upload_expire_after = 60 * 60 * 24 * 7  -- 1 week
```

2. Configure HTTPS:
```lua
https_ports = { 5281 }
https_certificate = "/etc/prosody/certs/xmpp.example.com.crt"
https_key = "/etc/prosody/certs/xmpp.example.com.key"
```

3. Restart Prosody:
```bash
systemctl restart prosody
```

4. Test BOSH endpoint:
```bash
curl https://xmpp.example.com:5281/http-bind
# Should return: <body>BOSH endpoint</body> or similar
```

### ejabberd

Add to `/etc/ejabberd/ejabberd.yml`:
```yaml
listen:
  -
    port: 5443
    module: ejabberd_http
    request_handlers:
      "/http-bind": mod_bosh
```

### Openfire

1. Go to Server Settings → HTTP Binding
2. Enable HTTP Binding (BOSH)
3. Note the URL (usually `https://server:7443/http-bind`)

## Common BOSH Endpoints

| Server | Default BOSH URL |
|--------|------------------|
| Prosody | `https://xmpp.example.com:5281/http-bind` |
| ejabberd | `https://xmpp.example.com:5443/http-bind` |
| Openfire | `https://xmpp.example.com:7443/http-bind` |
| Conversations (xmpp.conversations.im) | `https://xmpp.conversations.im:5281/http-bind` |

## Troubleshooting

### Testing your setup
Use the included test script:
```bash
./test-send2xmpp
```

This will verify:
- ✅ Configuration is valid
- ✅ BOSH endpoint is reachable
- ✅ Authentication works
- ✅ Text messages can be sent
- ✅ Image upload works (if supported)

### Connection fails
```bash
# Test BOSH endpoint directly
curl -v https://xmpp.example.com:5281/http-bind

# Check TLS version
send2xmpp -v -m "test"  # Look for TLS errors
```

### Authentication fails
```bash
# Verify credentials
xmpppy-cli -j camera@example.com -p password -t you@example.com -m "test"

# Check server logs
journalctl -u prosody -f  # for Prosody
```

### Image upload fails

**Error: "Could not find HTTP Upload component"**
- Server may not support XEP-0363
- Enable `http_upload` module on your XMPP server
- Set `XMPP_UPLOAD_COMPONENT` in config if auto-discovery fails

**Error: "Failed to request upload slot"**
- Check file size limits on server
- Verify upload component is running: `curl https://upload.example.com/`
- Check server logs for errors

**Error: "Failed to upload file"**
- Network connectivity issue
- Server upload URL may be incorrect
- Check firewall rules

### Enable verbose logging
```bash
# See detailed BOSH communication
send2xmpp -v -i /tmp/test.jpg -m "debug test"
```

### TLS errors with mbedTLS
The script uses TLS 1.2 by default for mbedTLS compatibility. If you have OpenSSL, you can use:
```bash
XMPP_TLS_VERSION="" send2xmpp -m "test"  # Use default TLS
```

## Limitations

1. **Image Upload**: 
   - Requires XEP-0363 HTTP Upload support on server
   - Auto-discovers upload component
   - Falls back to text notification if upload fails
   - Supports: JPEG, PNG, GIF, WebP

2. **Authentication**: Only SASL PLAIN supported
   - For better security, use TLS
   - Consider SCRAM-SHA-1 support in future

3. **Message Carbons**: Not supported
   - Messages won't appear in your sent folder

## Security Notes

- Credentials are stored in `/etc/send2xmpp.conf` in plain text
- Secure the config file: `chmod 600 /etc/send2xmpp.conf`
- Always use HTTPS (TLS) for BOSH endpoint
- SASL PLAIN sends password in base64 (not encrypted, only encoded)

## Testing with Public XMPP Servers

For testing, you can use public XMPP servers:

1. Create account at https://conversations.im or https://jabber.org
2. Use BOSH endpoint from your provider
3. Test:
```bash
export XMPP_JID="user@conversations.im"
export XMPP_PASSWORD="yourpassword"
export XMPP_RECIPIENT="friend@conversations.im"
export XMPP_BOSH_URL="https://xmpp.conversations.im:5281/http-bind"

send2xmpp -v -m "Test from embedded device"
```

## Integration Examples

### With Motion Detection
```bash
#!/bin/sh
# /usr/sbin/send2motion

if [ -n "$MOTION_PHOTO_FILE" ]; then
    HOSTNAME=$(hostname)
    TIMESTAMP=$(date '+%Y-%m-%d %H:%M:%S')
    send2xmpp -i "$MOTION_PHOTO_FILE" -m "Motion detected on $HOSTNAME at $TIMESTAMP"
fi
```

### Scheduled Status Report
```bash
#!/bin/sh
# Add to cron: 0 * * * * /usr/bin/camera-status

UPTIME=$(uptime)
TEMP=$(cat /sys/class/thermal/thermal_zone0/temp 2>/dev/null || echo "N/A")

send2xmpp -m "Camera status:
Uptime: $UPTIME
Temperature: $TEMP
Time: $(date)"
```

## Future Enhancements

- [x] Full XEP-0363 HTTP Upload support
- [ ] SCRAM-SHA-1 authentication
- [ ] Message delivery receipts (XEP-0184)
- [ ] MUC (group chat) support
- [ ] Presence management

## License

MIT License - feel free to modify and distribute

## Author

Created for Thingino embedded camera systems
