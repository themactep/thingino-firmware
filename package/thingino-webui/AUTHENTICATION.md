# Thingino Web UI Authentication System

## Overview

The Thingino web UI uses a hybrid authentication system that provides:
- **Session-based authentication** for web browsers (login page, cookies)
- **API key authentication** for automation and integrations
- **Default password detection** and enforcement
- **Secure session management** with automatic timeouts

## Table of Contents

1. [Architecture](#architecture)
2. [Session-Based Authentication](#session-based-authentication)
3. [API Key Authentication](#api-key-authentication)
4. [Default Password Protection](#default-password-protection)
5. [Security Features](#security-features)
6. [API Reference](#api-reference)
7. [Integration Examples](#integration-examples)
8. [Troubleshooting](#troubleshooting)

---

## Architecture

### Components

```
┌─────────────────────────────────────────────────────────────┐
│                     Thingino Web UI                         │
├─────────────────────────────────────────────────────────────┤
│  Browser Access          │  Automation Access               │
│  ├─ Login Page           │  ├─ API Key Header               │
│  ├─ Session Cookies      │  ├─ Direct Endpoint Access       │
│  └─ Logout               │  └─ No Browser Required          │
├─────────────────────────────────────────────────────────────┤
│              Authentication Middleware (auth.sh)             │
│  ├─ Session Validation                                       │
│  ├─ API Key Verification                                     │
│  └─ Request Routing                                          │
├─────────────────────────────────────────────────────────────┤
│              Session Management (session.sh)                 │
│  ├─ Session Creation                                         │
│  ├─ Session Validation                                       │
│  ├─ Session Cleanup                                          │
│  └─ Cookie Management                                        │
└─────────────────────────────────────────────────────────────┘
```

### Key Files

| File | Purpose |
|------|---------|
| `/var/www/x/session.sh` | Session management library |
| `/var/www/x/auth.sh` | Authentication middleware |
| `/var/www/x/login.cgi` | Login endpoint |
| `/var/www/x/logout.cgi` | Logout endpoint |
| `/var/www/x/session-status.cgi` | Session status check |
| `/var/www/x/api-key.cgi` | API key management |
| `/var/www/login.html` | Login page UI |
| `/var/www/index.cgi` | Entry point (redirects to login or app) |
| `/tmp/sessions/*` | Active session files |
| `/etc/thingino-api.key` | API key storage |

---

## Session-Based Authentication

### How It Works

1. **User visits camera** → Redirected to `/login.html`
2. **User enters credentials** → POST to `/x/login.cgi`
3. **Server validates password** → Creates session, sets cookie
4. **Session cookie stored** → Automatic auth for future requests
5. **User logs out** → Session deleted, cookie cleared

### Session Properties

- **Storage**: `/tmp/sessions/{session_id}`
- **Timeout**: 1 hour (3600 seconds)
- **Cookie**: `thingino_session` (HttpOnly, SameSite=Strict)
- **Security**: Session files mode 600 (root only)

### Session Data Structure

```bash
# /tmp/sessions/{session_id}
username=root
created=1706441234
last_access=1706441834
is_default_password=false
```

### Login Process

**Frontend (login.html)**:
```javascript
fetch('/x/login.cgi', {
  method: 'POST',
  headers: { 'Content-Type': 'application/json' },
  body: JSON.stringify({ username: 'root', password: 'your_password' })
});
```

**Backend (login.cgi)**:
```bash
# Verify password against /etc/shadow
# Create session
session_id=$(create_session "$username" "$is_default")
# Set cookie
printf "Set-Cookie: thingino_session=%s; Path=/; HttpOnly; SameSite=Strict; Max-Age=3600\r\n" "$session_id"
```

### Logout Process

**Request**:
```bash
GET /x/logout.cgi
```

**Response**:
- Deletes session file
- Clears cookie
- Redirects to login page

---

## API Key Authentication

### Overview

API keys provide stateless authentication for automation tools, scripts, and integrations without requiring a browser session.

### Generating an API Key

**Via Web UI**:
1. Log in to camera
2. Navigate to **Settings → Web Interface**
3. Scroll to **API Access** section
4. Click **Generate New Key**
5. Copy the generated key

**Via API** (requires valid session):
```bash
curl -X POST http://CAMERA_IP/x/api-key.cgi \
  -b "thingino_session=YOUR_SESSION_ID"
```

Response:
```json
{
  "api_key": "5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff",
  "generated": true
}
```

### Using an API Key

**Header Method** (recommended):
```bash
curl -H "X-API-Key: YOUR_API_KEY" http://CAMERA_IP/x/ch0.jpg -o snapshot.jpg
```

**All Protected Endpoints**:
```bash
# Snapshot
curl -H "X-API-Key: KEY" http://CAMERA_IP/x/ch0.jpg -o snapshot.jpg

# MJPEG stream
curl -H "X-API-Key: KEY" http://CAMERA_IP/x/ch0.mjpg

# JSON endpoints
curl -H "X-API-Key: KEY" http://CAMERA_IP/x/json-heartbeat.cgi

# Configuration
curl -H "X-API-Key: KEY" http://CAMERA_IP/x/json-config-webui.cgi
```

### Managing API Keys

**View Current Key**:
```bash
GET /x/api-key.cgi
```

**Delete Key**:
```bash
DELETE /x/api-key.cgi
```

### API Key Security

- **Storage**: `/etc/thingino-api.key` (mode 600)
- **Format**: 64-character hexadecimal string (256 bits)
- **Generation**: Cryptographically secure random (`/dev/urandom`)
- **Validation**: Constant-time string comparison
- **Scope**: Full access (equivalent to root user)

---

## Default Password Protection

### Detection

The system automatically detects if the camera is using the default "root:root" credentials and enforces a password change.

### Workflow

1. **User logs in with default password**
2. **Session created with flag**: `is_default_password=true`
3. **JavaScript checks session status**: `GET /x/session-status.cgi`
4. **Modal displayed**: Non-dismissible password change dialog
5. **Heartbeat disabled**: SSE stream won't start until password changed
6. **User changes password**: Inline form in modal
7. **Session updated**: `is_default_password=false`
8. **Modal closes**: Normal operation resumes

### Password Change Flow

**Frontend**:
```javascript
// Modal shows automatically
// User enters new password
fetch('/x/json-config-webui.cgi', {
  method: 'POST',
  body: JSON.stringify({ password: 'new_secure_password' })
});
```

**Backend**:
```bash
# Update system password
echo "root:$new_password" | chpasswd -c sha512

# Update session flag
sed -i "s/^is_default_password=.*/is_default_password=false/" "$session_file"
```

### Heartbeat Protection

The SSE heartbeat endpoint (`/x/json-heartbeat.cgi`) will not start if:
- Password check not complete (`passwordCheckComplete=false`)
- Using default password (`isDefaultPassword=true`)

```javascript
function heartbeat() {
  if (!passwordCheckComplete) return;
  if (isDefaultPassword) return;
  startHeartbeatSse();
}
```

---

## Security Features

### Password Verification

**Method**: SHA-512 with salt
```bash
# Extract salt from stored hash
salt=$(echo "$stored_hash" | cut -d'$' -f3)

# Generate hash with same salt
test_hash=$(mkpasswd "$password" -S "$salt")

# Compare hashes
[ "$test_hash" = "$stored_hash" ]
```

### Session Security

- **HttpOnly cookies**: Not accessible via JavaScript
- **SameSite=Strict**: CSRF protection
- **Secure storage**: Files mode 600 in `/tmp/sessions/`
- **Automatic cleanup**: Expired sessions removed
- **Session timeout**: 1 hour of inactivity

### Protected Endpoints

All CGI scripts include authentication check:
```bash
. /var/www/x/auth.sh
require_auth
```

**51 Protected Endpoints**:
- All `/x/json-*.cgi` (configuration, status)
- All `/x/tool-*.cgi` (tools)
- All `/x/ch*.jpg` and `/x/ch*.mjpg` (streams)
- All `/x/config-*.cgi` (settings)
- All `/x/info*.cgi` (information)
- Reboot, restart, and system control endpoints

**Public Endpoints** (no auth required):
- `/x/login.cgi` - Login
- `/x/logout.cgi` - Logout
- `/x/session-status.cgi` - Session check

### Authentication Priority

```
1. Session cookie check → Valid? → Allow
2. API key header check → Valid? → Allow
3. Request type check:
   - Browser (Accept: text/html) → Redirect to /login.html
   - API/Automation → Return 401 Unauthorized
```

### Password Requirements

- **Minimum length**: 4 characters
- **Cannot be**: "root" (enforced in UI)
- **Format**: SHA-512 hash in `/etc/shadow`

---

## API Reference

### Authentication Endpoints

#### POST /x/login.cgi

Login with username and password.

**Request**:
```json
{
  "username": "root",
  "password": "your_password"
}
```

**Response** (Success):
```json
{
  "success": true,
  "is_default_password": false
}
```
**Headers**: Sets `thingino_session` cookie

**Response** (Failure):
```json
{
  "error": {
    "code": 401,
    "message": "Invalid credentials"
  }
}
```

---

#### GET /x/logout.cgi

Logout and destroy session.

**Response**: Redirects to `/login.html`

---

#### GET /x/session-status.cgi

Check current session status.

**Response** (Authenticated):
```json
{
  "authenticated": true,
  "username": "root",
  "is_default_password": false
}
```

**Response** (Not Authenticated):
```json
{
  "authenticated": false
}
```

---

### API Key Endpoints

#### GET /x/api-key.cgi

Get current API key (requires session auth).

**Response** (Key exists):
```json
{
  "api_key": "5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff",
  "exists": true
}
```

**Response** (No key):
```json
{
  "exists": false
}
```

---

#### POST /x/api-key.cgi

Generate new API key (requires session auth).

**Response**:
```json
{
  "api_key": "5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff",
  "generated": true
}
```

---

#### DELETE /x/api-key.cgi

Delete API key (requires session auth).

**Response**:
```json
{
  "deleted": true
}
```

---

## Integration Examples

### Home Assistant

**Configuration.yaml**:
```yaml
camera:
  - platform: generic
    name: Thingino Camera
    still_image_url: http://192.168.1.100/x/ch0.jpg
    stream_source: http://192.168.1.100/x/ch0.mjpg
    authentication: header
    headers:
      X-API-Key: "YOUR_API_KEY_HERE"
```

---

### Python Script

```python
import requests

API_KEY = "5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff"
CAMERA_IP = "192.168.1.100"

headers = {"X-API-Key": API_KEY}

# Get snapshot
response = requests.get(f"http://{CAMERA_IP}/x/ch0.jpg", headers=headers)
with open("snapshot.jpg", "wb") as f:
    f.write(response.content)

# Get camera status
response = requests.get(f"http://{CAMERA_IP}/x/json-heartbeat.cgi", headers=headers)
data = response.json()
print(f"CPU: {data['cpu']}%, Memory: {data['mem']}%")
```

---

### Shell Script

```bash
#!/bin/bash

API_KEY="5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff"
CAMERA_IP="192.168.1.100"

# Take snapshot every 5 minutes
while true; do
    timestamp=$(date +%Y%m%d_%H%M%S)
    curl -H "X-API-Key: $API_KEY" \
         "http://${CAMERA_IP}/x/ch0.jpg" \
         -o "snapshots/${timestamp}.jpg"
    sleep 300
done
```

---

### Node.js / JavaScript

```javascript
const axios = require('axios');

const API_KEY = '5a34a6104e3fc919a7d925f2fcf1230c811d2845222657e193496776310b68ff';
const CAMERA_IP = '192.168.1.100';

const headers = { 'X-API-Key': API_KEY };

// Get snapshot
async function getSnapshot() {
  const response = await axios.get(
    `http://${CAMERA_IP}/x/ch0.jpg`,
    { headers, responseType: 'arraybuffer' }
  );
  
  return Buffer.from(response.data);
}

// Get camera info
async function getCameraInfo() {
  const response = await axios.get(
    `http://${CAMERA_IP}/x/json-heartbeat.cgi`,
    { headers }
  );
  
  return response.data;
}
```

---

### cURL Examples

```bash
# Download snapshot
curl -H "X-API-Key: YOUR_KEY" \
     http://CAMERA_IP/x/ch0.jpg \
     -o snapshot.jpg

# Stream MJPEG
curl -H "X-API-Key: YOUR_KEY" \
     http://CAMERA_IP/x/ch0.mjpg \
     | mpv -

# Get JSON data
curl -H "X-API-Key: YOUR_KEY" \
     http://CAMERA_IP/x/json-heartbeat.cgi \
     | jq .

# Change configuration
curl -H "X-API-Key: YOUR_KEY" \
     -H "Content-Type: application/json" \
     -X POST \
     -d '{"theme":"dark"}' \
     http://CAMERA_IP/x/json-config-webui.cgi
```

---

## Troubleshooting

### Session Issues

**Problem**: "Redirected to login page repeatedly"

**Solution**:
- Clear browser cookies
- Check browser console for errors
- Verify `/tmp/sessions/` directory exists and is writable
- Check camera time is correct

---

**Problem**: "Session expired too quickly"

**Solution**:
- Check `SESSION_TIMEOUT` in `/var/www/x/session.sh` (default: 3600s)
- Verify session file exists in `/tmp/sessions/`
- Check system load (session cleanup may be failing)

---

### API Key Issues

**Problem**: "401 Unauthorized with API key"

**Solution**:
- Verify API key is correct: `ssh root@CAMERA_IP "cat /etc/thingino-api.key"`
- Check header name is exact: `X-API-Key` (case sensitive)
- Ensure no extra spaces or newlines in key
- Test with: `curl -H "X-API-Key: $(cat key.txt)" http://CAMERA_IP/x/ch0.jpg`

---

**Problem**: "Cannot generate API key"

**Solution**:
- Ensure logged in with valid session
- Check `/etc/` is writable
- Verify `/dev/urandom` exists
- Check browser console for JavaScript errors

---

### Password Issues

**Problem**: "Password change modal won't close"

**Solution**:
- Hard refresh page (Ctrl+Shift+R)
- Check password meets requirements (≥4 chars, not "root")
- Verify session status: `GET /x/session-status.cgi`
- Check browser console for errors

---

**Problem**: "Cannot login after password change"

**Solution**:
- Verify new password was saved: `ssh root@CAMERA_IP "grep root /etc/shadow"`
- Try default credentials if recently reset
- Check for typos in password
- Clear browser cache and cookies

---

### Heartbeat Issues

**Problem**: "Heartbeat stream not starting"

**Solution**:
- Check browser console logs
- Verify `passwordCheckComplete=true`
- Verify `isDefaultPassword=false`
- Check SSE endpoint: `curl http://CAMERA_IP/x/json-heartbeat.cgi`

---

### General Debugging

**Enable Debug Logging**:
```bash
# In CGI scripts, add at top:
set -x  # Enable bash tracing

# Check logs:
logread | grep -E "login|session|auth"
```

**Test Authentication**:
```bash
# Test session
curl -v -b "thingino_session=YOUR_SESSION_ID" http://CAMERA_IP/x/ch0.jpg

# Test API key
curl -v -H "X-API-Key: YOUR_KEY" http://CAMERA_IP/x/ch0.jpg

# Should return 401:
curl -v http://CAMERA_IP/x/ch0.jpg
```

**Check Session Files**:
```bash
ssh root@CAMERA_IP "ls -la /tmp/sessions/"
ssh root@CAMERA_IP "cat /tmp/sessions/*"
```

**Check API Key**:
```bash
ssh root@CAMERA_IP "cat /etc/thingino-api.key"
```

---

## Migration from Basic Auth

### Changes from Previous System

| Old System | New System |
|------------|------------|
| Browser prompts for credentials | Login page |
| Credentials cached by browser | Session cookies |
| No clean logout | Proper logout |
| Basic Auth in httpd | No httpd auth |
| Password in every request | Session token |
| No API support | API key support |

### Upgrade Steps

1. **Remove Basic Auth from httpd**:
   - Edit `/etc/init.d/S90httpd`
   - Remove `-r Authentication` flag
   - Restart httpd: `/etc/init.d/S90httpd restart`

2. **Deploy new files**:
   - All files in `package/thingino-webui/files/www/`
   - Session management scripts
   - Login page

3. **First Login**:
   - Navigate to camera IP
   - Enter credentials on login page
   - Change default password if prompted

4. **Generate API Key**:
   - Settings → Web Interface → API Access
   - Click "Generate New Key"
   - Update automation scripts with API key

### Backward Compatibility

**Not Compatible**:
- URL-embedded credentials (`http://user:pass@camera/`)
- Basic Auth headers
- Old browser password storage

**Compatible**:
- All endpoints (same URLs)
- JSON API responses
- MJPEG/JPEG formats
- Configuration structure

---

## Performance Impact

### Session Management

- **Session creation**: ~5ms
- **Session validation**: ~2ms
- **Session file I/O**: ~1ms (tmpfs)
- **Overhead per request**: ~3-5ms

### API Key Validation

- **File read**: ~1ms (cached by OS)
- **String comparison**: <1ms
- **Overhead per request**: ~1-2ms

### Memory Usage

- **Per session**: ~200 bytes
- **100 concurrent sessions**: ~20KB
- **Session script**: ~4KB (loaded once)

---

## Security Audit Checklist

- [x] Passwords hashed with SHA-512
- [x] Session IDs cryptographically random (32 bytes)
- [x] HttpOnly cookies (no JS access)
- [x] SameSite=Strict (CSRF protection)
- [x] Session timeout (1 hour)
- [x] Secure file permissions (600)
- [x] API keys 256-bit random
- [x] Constant-time string comparison
- [x] No credentials in URLs
- [x] No credentials in logs
- [x] Default password detection
- [x] Forced password change
- [x] All endpoints protected
- [x] Session cleanup on logout
- [x] Expired session cleanup

---

## Credits

**Developed for**: Thingino Firmware  
**License**: MIT  
**Documentation Version**: 1.0  
**Last Updated**: 2026-01-28

---

## Additional Resources

- **Thingino Wiki**: https://github.com/themactep/thingino-firmware/wiki
- **Issue Tracker**: https://github.com/themactep/thingino-firmware/issues
- **Community Forum**: https://t.me/thingino

---

*End of Documentation*
