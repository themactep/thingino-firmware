/*
 * HTTPS wrapper for BusyBox httpd using mbedTLS
 * Copyright (c) 2025 Thingino
 *
 * This program listens on HTTPS port (443) and forwards decrypted
 * traffic to BusyBox httpd running on localhost HTTP port.
 */

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/debug.h"
#include "mbedtls/ecp.h"
#include "mbedtls/entropy.h"
#include "mbedtls/error.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/ssl_cache.h"
#include "mbedtls/ssl_ticket.h"
#include "mbedtls/x509.h"

#include <errno.h>
#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <strings.h>
#include <unistd.h>

#include <arpa/inet.h>
#include <netinet/in.h>
#include <netinet/tcp.h>
#include <sys/select.h>
#include <sys/socket.h>
#include <sys/time.h>
#include <sys/types.h>

#define HTTP_HOST "127.0.0.1"
#define HTTP_PORT "80"
#define HTTPS_PORT "443"
#define CERT_FILE "/etc/ssl/certs/httpd.crt"
#define KEY_FILE "/etc/ssl/private/httpd.key"
#define BUFFER_SIZE 16384

#include <fcntl.h>

// Prefer faster cipher-suites on CPUs without AES acceleration
static const int preferred_ciphers[] = {
#if defined(MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256)
    MBEDTLS_TLS_ECDHE_RSA_WITH_CHACHA20_POLY1305_SHA256,
#endif
#if defined(MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256)
    MBEDTLS_TLS_ECDHE_RSA_WITH_AES_128_GCM_SHA256,
#endif
#if defined(MBEDTLS_TLS_RSA_WITH_AES_128_GCM_SHA256)
    MBEDTLS_TLS_RSA_WITH_AES_128_GCM_SHA256,
#endif
    0};

#if defined(MBEDTLS_ECP_C)
static const mbedtls_ecp_group_id preferred_curves[] = {
#if defined(MBEDTLS_ECP_DP_SECP256R1_ENABLED)
    MBEDTLS_ECP_DP_SECP256R1,
#endif
#if defined(MBEDTLS_ECP_DP_CURVE25519_ENABLED)
    MBEDTLS_ECP_DP_CURVE25519,
#endif
    MBEDTLS_ECP_DP_NONE};
#endif

volatile int keep_running = 1;

void signal_handler(int signum)
{
    keep_running = 0;
}

void my_debug(void* ctx, int level, const char* file, int line, const char* str)
{
    fprintf(stderr, "%s:%04d: %s", file, line, str);
}

// Server implementation (event-driven)
int run_event_server(mbedtls_net_context* listen_fd, mbedtls_ssl_config* conf);

int main(int argc, char* argv[])
{
    int ret;
    mbedtls_net_context listen_fd, client_fd;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    mbedtls_ssl_context ssl;
    mbedtls_ssl_config conf;
    mbedtls_ssl_cache_context cache;
    mbedtls_ssl_ticket_context tickets;
    mbedtls_x509_crt srvcert;
    mbedtls_pk_context pkey;
    const char* pers = "httpd_ssl_server";

    signal(SIGINT, signal_handler);
    signal(SIGTERM, signal_handler);

    // Initialize structures
    mbedtls_net_init(&listen_fd);
    mbedtls_net_init(&client_fd);
    mbedtls_ssl_init(&ssl);
    mbedtls_ssl_config_init(&conf);
    mbedtls_ssl_cache_init(&cache);
    mbedtls_ssl_ticket_init(&tickets);
    mbedtls_x509_crt_init(&srvcert);
    mbedtls_pk_init(&pkey);
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctr_drbg);

    // Seed the RNG
    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy, (const unsigned char*) pers, strlen(pers));
    if (ret != 0) {
        fprintf(stderr, "mbedtls_ctr_drbg_seed failed: -0x%x\n", -ret);
        goto exit;
    }

    // Load certificates and key
    ret = mbedtls_x509_crt_parse_file(&srvcert, CERT_FILE);
    if (ret != 0) {
        fprintf(stderr, "mbedtls_x509_crt_parse_file failed: -0x%x\n", -ret);
        fprintf(stderr, "Certificate file: %s\n", CERT_FILE);
        goto exit;
    }

    ret = mbedtls_pk_parse_keyfile(&pkey, KEY_FILE, NULL, mbedtls_ctr_drbg_random, &ctr_drbg);
    if (ret != 0) {
        fprintf(stderr, "mbedtls_pk_parse_keyfile failed: -0x%x\n", -ret);
        fprintf(stderr, "Key file: %s\n", KEY_FILE);
        goto exit;
    }

    // Setup SSL/TLS
    ret = mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_SERVER, MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
    if (ret != 0) {
        fprintf(stderr, "mbedtls_ssl_config_defaults failed: -0x%x\n", -ret);
        goto exit;
    }

    mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);

    // Optimize for performance on embedded devices
    mbedtls_ssl_conf_read_timeout(&conf, 0); // Non-blocking reads (DTLS only, safe here)

    // Prefer fast cipher suites and curves
    mbedtls_ssl_conf_ciphersuites(&conf, preferred_ciphers);
#if defined(MBEDTLS_ECP_C)
    mbedtls_ssl_conf_curves(&conf, preferred_curves);
#endif

    // Disable renegotiation
    mbedtls_ssl_conf_renegotiation(&conf, MBEDTLS_SSL_RENEGOTIATION_DISABLED);

    // Force TLS 1.2 for better performance (TLS 1.3 is more CPU intensive on this SoC)
    mbedtls_ssl_conf_max_version(&conf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
    mbedtls_ssl_conf_min_version(&conf, MBEDTLS_SSL_MAJOR_VERSION_3, MBEDTLS_SSL_MINOR_VERSION_3);
    // Setup stateless session tickets (improves repeat handshakes)
    if ((ret = mbedtls_ssl_ticket_setup(&tickets, mbedtls_ctr_drbg_random, &ctr_drbg, MBEDTLS_CIPHER_AES_128_GCM, 86400)) != 0) {
        fprintf(stderr, "Warning: ssl_ticket_setup failed: -0x%x\n", -ret);
    }

    // Enable session resumption to reduce handshake overhead (ID + tickets)
    mbedtls_ssl_conf_session_cache(&conf, &cache, mbedtls_ssl_cache_get, mbedtls_ssl_cache_set);

    // Session tickets (stateless resumption)
    mbedtls_ssl_conf_session_tickets(&conf, MBEDTLS_SSL_SESSION_TICKETS_ENABLED);
    mbedtls_ssl_conf_session_tickets_cb(&conf, mbedtls_ssl_ticket_write, mbedtls_ssl_ticket_parse, &tickets);

    ret = mbedtls_ssl_conf_own_cert(&conf, &srvcert, &pkey);
    if (ret != 0) {
        fprintf(stderr, "mbedtls_ssl_conf_own_cert failed: -0x%x\n", -ret);
        goto exit;
    }

    // Bind to HTTPS port
    ret = mbedtls_net_bind(&listen_fd, NULL, HTTPS_PORT, MBEDTLS_NET_PROTO_TCP);
    if (ret != 0) {
        fprintf(stderr, "mbedtls_net_bind failed: -0x%x\n", -ret);
        goto exit;
    }

    printf("HTTPS wrapper listening on port %s\n", HTTPS_PORT);
    printf("Forwarding to HTTP server at %s:%s\n", HTTP_HOST, HTTP_PORT);
    // Prefork workers to allow concurrent connections (e.g., MJPEG + assets)
    int workers = 5;
    const char* wenv = getenv("HTTPD_SSL_WORKERS");
    if (wenv) {
        int w = atoi(wenv);
        if (w > 0 && w < 16)
            workers = w;
    }
    for (int i = 1; i < workers; i++) {
        pid_t pid = fork();
        if (pid < 0) {
            // ignore fork failure and continue
            continue;
        }
        if (pid == 0) {
            // child becomes a worker
            break;
        }
    }

    // Run event-driven server (legacy removed)
    ret = run_event_server(&listen_fd, &conf);

exit:
    mbedtls_net_free(&listen_fd);
    mbedtls_x509_crt_free(&srvcert);
    mbedtls_pk_free(&pkey);
    mbedtls_ssl_config_free(&conf);
    mbedtls_ssl_cache_free(&cache);
    mbedtls_ssl_ticket_free(&tickets);
    mbedtls_ctr_drbg_free(&ctr_drbg);
    mbedtls_entropy_free(&entropy);

    return ret;
}
