# TLS Initialization Fix for mbedTLS Backend

## Problem
The mbedTLS implementation was unconditionally calling `mosquitto__mbedtls_connect()` for **every** connection in `net__socket_connect_step3()`, even when connecting to non-SSL hosts. This caused TLS handshake attempts on plain MQTT connections, leading to connection failures.

## Root Cause
In `lib/net_mosq.c`, the mbedTLS code path (added as a modification to support mbedTLS alongside OpenSSL) was missing a conditional check that exists in the OpenSSL implementation.

**OpenSSL implementation** (line 872):
```c
if(mosq->ssl_ctx){
    // Only setup TLS if ssl_ctx exists
    mosq->ssl = SSL_new(mosq->ssl_ctx);
    // ... TLS setup code ...
}
```

**Original mbedTLS implementation** (line 917-922, BROKEN):
```c
#elif defined(WITH_TLS_MBEDTLS)
	int rc = mosquitto__mbedtls_connect(mosq, host);  // ← ALWAYS called!
	if(rc){
		net__socket_close(mosq);
		return rc;
	}
```

## Solution
Added the same conditional check used in `net__init_ssl_ctx()` (line 678) to only initialize TLS when it's actually configured:

**Fixed mbedTLS implementation** (line 917-924):
```c
#elif defined(WITH_TLS_MBEDTLS)
	if(mosq->tls_cafile || mosq->tls_capath || mosq->tls_psk || mosq->tls_use_os_certs){
		int rc = mosquitto__mbedtls_connect(mosq, host);
		if(rc){
			net__socket_close(mosq);
			return rc;
		}
	}
```

## Verification
TLS should now only be initialized when one of these is configured:
- `mosq->tls_cafile` - CA certificate file path
- `mosq->tls_capath` - CA certificate directory path  
- `mosq->tls_psk` - Pre-shared key for PSK authentication
- `mosq->tls_use_os_certs` - Use OS certificate store

When connecting to a non-SSL MQTT broker (e.g., `mqtt://broker:1883`), TLS initialization will be skipped entirely, allowing plain MQTT connections to work correctly.

## Files Modified
- `lib/net_mosq.c` - Added conditional check before `mosquitto__mbedtls_connect()`
