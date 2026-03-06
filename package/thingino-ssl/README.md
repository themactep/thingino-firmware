# Thingino SSL/TLS Abstraction

This package provides a virtual package abstraction for selecting an SSL/TLS library for thingino.

## Supported SSL/TLS Libraries

The following SSL/TLS libraries are supported:

### mbedTLS (default)
- Lightweight, designed for embedded systems
- HTTP/2 support with ALPN, SNI, Session Tickets
- TLS 1.3 cipher support
- Small footprint
- Website: https://tls.mbed.org/

### wolfSSL
- Fast, portable SSL/TLS library
- Targeted at IoT and embedded environments
- Extensive configuration options
- OpenSSL compatibility layer available
- Requires thread support
- Website: https://www.wolfssl.com/

### OpenSSL
- Full-featured SSL/TLS library
- Widely compatible
- Larger footprint than alternatives
- Industry standard
- Website: https://www.openssl.org/

## Usage

When building thingino firmware, select one SSL/TLS library from the configuration menu:

```
Thingino Firmware → System Packages → SSL/TLS Library
```

Only one SSL/TLS library should be selected at a time to avoid conflicts and minimize flash usage.

## Requirements

### wolfSSL
- Toolchain with thread support (BR2_TOOLCHAIN_HAS_THREADS)

## Package Dependencies

Various thingino packages will automatically use the selected SSL library:

- **thingino-libcurl**: Auto-selects SSL backend based on available library
- **thingino-uhttpd**: Provides TLS support using selected library
- **thingino-httpd-ssl**: Requires mbedTLS
- **thingino-mosquitto**: Can use OpenSSL or other libraries
- **thingino-streamer**: Supports OpenSSL or mbedTLS for RTMPS

## Notes

- Some packages may have specific SSL library requirements or preferences
- The choice affects flash size - mbedTLS is typically smallest, OpenSSL largest
- Consider your specific needs (compatibility vs. size vs. features) when choosing
