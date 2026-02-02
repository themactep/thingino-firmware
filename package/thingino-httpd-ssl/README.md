# thingino-httpd-ssl

HTTPS wrapper for BusyBox httpd using mbedTLS.

## Overview

This package provides a lightweight SSL/TLS wrapper that enables HTTPS support for BusyBox httpd. It uses mbedTLS for encryption, making it suitable for embedded systems with limited resources.

## How it works

1. **httpd-ssl** listens on port 443 (HTTPS)
2. BusyBox **httpd** runs on localhost port 80 (HTTP)
3. httpd-ssl decrypts incoming HTTPS traffic and forwards it to httpd
4. Responses from httpd are encrypted and sent back to the client

```
Client (HTTPS:443) <--[SSL/TLS]--> httpd-ssl <--[HTTP]--> BusyBox httpd (localhost:80)
```

## Features

- **Small footprint**: Uses mbedTLS instead of OpenSSL
- **Automatic certificate generation**: Self-signed certificates are generated on first run
- **Simple configuration**: Works out of the box with BusyBox httpd
- **Init script included**: Automatic startup on boot

## Installation

1. Enable the package in menuconfig:
   ```
   make menuconfig
   # Navigate to: Target packages -> Thingino packages -> thingino-httpd-ssl
   ```

2. Build the firmware:
   ```
   make
   ```

## Usage

### Automatic startup

The service starts automatically on boot via `/etc/init.d/S50httpd-ssl`.

### Manual control

```bash
# Start HTTPS service
/etc/init.d/S50httpd-ssl start

# Stop HTTPS service
/etc/init.d/S50httpd-ssl stop

# Restart HTTPS service
/etc/init.d/S50httpd-ssl restart
```

### Generate new certificate

```bash
# Using mbedtls-certgen (automatically installed with this package)
HOSTNAME=$(hostname)
# RSA 2048 for better browser compatibility (matches init script)
mbedtls-certgen -h "$HOSTNAME" -c /etc/ssl/certs/httpd.crt -k /etc/ssl/private/httpd.key -d 3650 -s 2048 -t rsa
```

## Configuration

### Certificate files

- Certificate: `/etc/ssl/certs/httpd.crt`
- Private key: `/etc/ssl/private/httpd.key`

### Ports

- HTTPS: 443 (external)
- HTTP: 80 (localhost only)


## Event-driven server (default) and environment variables

The HTTPS wrapper uses an event-driven server optimized for MJPEG and concurrent asset requests by default.

Environment variables:
- HTTPD_SSL_WORKERS
  - Number of worker processes (default: 5). Exported by `/etc/init.d/S50httpd-ssl`.
- HTTPD_SSL_TRACE
  - `0`/`1` (default: 0). When `1`, enables lightweight tracing to `/tmp/httpd-ssl.log`.
- HTTPD_SSL_PASSTHRU
  - `0`/`1` (default: 0). When `1`, attempts direct HTTP→TLS writes first; stashes leftovers into the ring when TLS would block. Useful for debugging.

Examples:
```sh
# Single traced worker (foreground) for debugging
HTTPD_SSL_WORKERS=1 HTTPD_SSL_TRACE=1 /usr/sbin/httpd-ssl >/tmp/httpd-ssl.log 2>&1 &

# Passthrough mode to isolate ring-buffer effects
HTTPD_SSL_WORKERS=1 HTTPD_SSL_TRACE=1 HTTPD_SSL_PASSTHRU=1 /usr/sbin/httpd-ssl >/tmp/httpd-ssl.log 2>&1 &
```

To change ports, edit `/etc/init.d/S50httpd-ssl` and modify the httpd-ssl source code.


## Concurrency and worker processes

By default, the wrapper preforks multiple worker processes so long‑lived requests (e.g., MJPEG stream) don’t block other requests (e.g., PTZ/API, CSS/JS).

- Default workers: 5
- Tunable via environment variable: `HTTPD_SSL_WORKERS`

Override at runtime without editing files:

```bash
# Example: run with 6 workers until next reboot
HTTPD_SSL_WORKERS=6 /etc/init.d/S50httpd-ssl restart

# Verify the number of workers
pidof httpd-ssl | wc -w
```

Make 5 the persistent default (already set):
- See `/etc/init.d/S50httpd-ssl`, it exports `HTTPD_SSL_WORKERS` with a default.

Notes on impact:
- Each idle worker uses a small amount of RAM (roughly ~0.5–1.0 MB RSS). Under active load (streams/handshakes), memory and CPU increase per active worker.
- More workers improve responsiveness under concurrent use (e.g., 1×MJPEG + PTZ/API + assets). Typical sweet spot is 4–6. Use higher values if multiple clients/tabs are expected and memory allows.
- Session resumption is enabled (tickets), so TLS handshakes are faster even across workers.

## Security Notes

1. **Self-signed certificates**: By default, a self-signed certificate is generated. Browsers will show a security warning. For production use, replace with a proper certificate.

2. **Certificate replacement**: To use your own certificate:
   ```bash
   # Copy your certificate and key
   cp your-cert.crt /etc/ssl/certs/httpd.crt
   cp your-key.key /etc/ssl/private/httpd.key
   chmod 600 /etc/ssl/private/httpd.key

   # Restart the service
   /etc/init.d/S50httpd-ssl restart
   ```

3. **Let's Encrypt**: For automatic certificate management, consider using acme.sh or certbot (if available).

## Troubleshooting

### Check if services are running

```bash
# Check httpd-ssl
ps | grep httpd-ssl

# Check httpd
ps | grep httpd

# Check listening ports
netstat -tlnp | grep -E ':(80|443)'
```

### View logs

```bash
# System log
logread | grep httpd

# Run httpd-ssl in foreground for debugging
killall httpd-ssl
/usr/sbin/httpd-ssl
```

### Common issues

1. **Port 443 already in use**: Another service might be using port 443
   ```bash
   netstat -tlnp | grep :443
   ```

2. **Certificate errors**: Regenerate the certificate
   ```bash
   rm /etc/ssl/certs/httpd.crt /etc/ssl/private/httpd.key
   httpd-generate-cert
   /etc/init.d/S50httpd-ssl restart
   ```

3. **Connection refused**: Ensure httpd is running on localhost:80
   ```bash
   netstat -tlnp | grep :80
   ```

## Size comparison

- **thingino-httpd-ssl**: ~50KB (with mbedTLS)
- **stunnel**: ~200KB (with OpenSSL)
- **thingino-uhttpd**: ~100KB (native HTTPS support)

## License

GPL-2.0

## See also

- [BusyBox httpd documentation](https://busybox.net/downloads/BusyBox.html#httpd)
- [mbedTLS](https://www.trustedfirmware.org/projects/mbed-tls/)
- [thingino-uhttpd](../thingino-uhttpd/) - Alternative web server with native HTTPS support

