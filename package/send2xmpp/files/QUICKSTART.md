# send2xmpp - Quick Start Guide

Complete XMPP messaging solution using only shell + curl!

## What You Get

✅ **Full XMPP client** - Connect to any XMPP/Jabber server  
✅ **Image upload** - Send photos via XEP-0363 HTTP Upload  
✅ **Text messages** - Standard XMPP chat messages  
✅ **Pure shell** - No Python, Perl, or other dependencies  
✅ **mbedTLS ready** - Works with TLS 1.2 on embedded devices  

## Installation (3 Steps)

```bash
# 1. Install script
cp send2xmpp /usr/bin/
chmod +x /usr/bin/send2xmpp

# 2. Configure
cp send2xmpp.conf.example /etc/send2xmpp.conf
vi /etc/send2xmpp.conf

# 3. Test
./test-send2xmpp
```

## Configuration Example

Edit `/etc/send2xmpp.conf`:

```bash
XMPP_JID="mycamera@xmpp.myserver.com"
XMPP_PASSWORD="secret123"
XMPP_RECIPIENT="myphone@xmpp.myserver.com"
XMPP_BOSH_URL="https://xmpp.myserver.com:5281/http-bind"
```

## Usage Examples

```bash
# Send text message
send2xmpp -m "Motion detected!"

# Send image with caption
send2xmpp -i /tmp/motion.jpg -m "Motion at 14:30"

# From stdin
echo "Camera online" | send2xmpp

# Verbose mode
send2xmpp -v -i /tmp/snapshot.jpg
```

## Server Requirements

Your XMPP server needs:
- **BOSH support** (HTTP binding) - for curl compatibility
- **HTTP Upload (XEP-0363)** - for image uploads

### Popular XMPP Servers

| Server | Setup Difficulty | BOSH | HTTP Upload |
|--------|-----------------|------|-------------|
| **Prosody** | Easy | ✅ Built-in | ✅ Module |
| ejabberd | Medium | ✅ Built-in | ✅ Built-in |
| Openfire | Easy | ✅ Plugin | ✅ Plugin |

### Prosody Quick Setup (Recommended)

```bash
# Install
apt install prosody

# Edit /etc/prosody/prosody.cfg.lua
modules_enabled = {
    "bosh";
    "http_upload";
}

# Restart
systemctl restart prosody

# Create user
prosodyctl adduser camera@yourdomain.com
```

## Integration with Motion Detection

```bash
#!/bin/sh
# /usr/sbin/send2motion

if [ -n "$MOTION_PHOTO_FILE" ]; then
    send2xmpp -i "$MOTION_PHOTO_FILE" \
              -m "Motion detected on $(hostname) at $(date)"
fi
```

## Troubleshooting

**Can't connect?**
```bash
curl https://xmpp.example.com:5281/http-bind
# Should return BOSH endpoint info
```

**Auth fails?**
- Check username/password
- View server logs: `journalctl -u prosody`

**Image upload fails?**
- Server may not support XEP-0363
- Check Prosody modules: `prosodyctl about`
- Enable http_upload module

**TLS errors?**
- Script uses TLS 1.2 by default (mbedTLS compatible)
- For OpenSSL, set: `XMPP_TLS_VERSION=""`

## File Sizes

- **send2xmpp**: 12KB
- **Config**: 1KB
- **Total**: ~13KB

Perfect for embedded devices!

## Public XMPP Servers (for testing)

Don't have your own server? Try these:

1. **conversations.im**
   - Free accounts
   - BOSH: `https://xmpp.conversations.im:5281/http-bind`
   - HTTP Upload: ✅ Supported

2. **jabber.org**
   - Free accounts
   - BOSH: Check server documentation
   - HTTP Upload: May vary

## Security Notes

⚠️ **Configuration file** contains password in plain text  
🔒 **Solution**: `chmod 600 /etc/send2xmpp.conf`

⚠️ **SASL PLAIN** sends password base64-encoded  
🔒 **Solution**: Always use HTTPS BOSH endpoint

## Performance

Typical execution time:
- Text message: **~1-2 seconds**
- Image upload (500KB): **~3-5 seconds**

Memory usage: **<1MB**

## Need Help?

1. Run test script: `./test-send2xmpp`
2. Enable verbose: `send2xmpp -v -m "test"`
3. Check server logs
4. Read full documentation: `README-xmpp.md`

## What's Next?

- Set up motion detection integration
- Configure cron jobs for status reports
- Test with different image sizes
- Experiment with server settings

Enjoy secure, private notifications from your camera! 📸
