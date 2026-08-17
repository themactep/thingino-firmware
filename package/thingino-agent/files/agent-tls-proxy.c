/*
 * TLS proxy for Thingino agent using mbedTLS.
 *
 * This reuses the proven httpd-ssl transport pattern, but forwards
 * decrypted traffic to the native agent listener on loopback instead of
 * BusyBox httpd.
 */

#include "mbedtls/ctr_drbg.h"
#include "mbedtls/debug.h"
#include "mbedtls/entropy.h"
#include "mbedtls/net_sockets.h"
#include "mbedtls/pk.h"
#include "mbedtls/ssl.h"
#include "mbedtls/ssl_cache.h"
#include "mbedtls/ssl_ticket.h"
#include "mbedtls/x509.h"

#include <signal.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

const char *proxy_backend_host = "127.0.0.1";
const char *proxy_backend_port = "2998";
static const char *proxy_listen_host = NULL;
static const char *proxy_listen_port = "1998";
static const char *proxy_cert_file = "/etc/ssl/certs/uhttpd.crt";
static const char *proxy_key_file = "/etc/ssl/private/uhttpd.key";

volatile int keep_running = 1;

static const int preferred_ciphers[] = {
#if defined(MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256)
	MBEDTLS_TLS_ECDHE_ECDSA_WITH_CHACHA20_POLY1305_SHA256,
#endif
#if defined(MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256)
	MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_128_GCM_SHA256,
#endif
#if defined(MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384)
	MBEDTLS_TLS_ECDHE_ECDSA_WITH_AES_256_GCM_SHA384,
#endif
	0
};

static void signal_handler(int signum)
{
	(void)signum;
	keep_running = 0;
}

static int parse_args(int argc, char **argv)
{
	int index;

	for (index = 1; index < argc; index++) {
		if (strcmp(argv[index], "--listen") == 0 && index + 1 < argc) {
			proxy_listen_host = argv[++index];
		} else if (strcmp(argv[index], "--port") == 0 && index + 1 < argc) {
			proxy_listen_port = argv[++index];
		} else if (strcmp(argv[index], "--backend-host") == 0 && index + 1 < argc) {
			proxy_backend_host = argv[++index];
		} else if (strcmp(argv[index], "--backend-port") == 0 && index + 1 < argc) {
			proxy_backend_port = argv[++index];
		} else if (strcmp(argv[index], "--cert") == 0 && index + 1 < argc) {
			proxy_cert_file = argv[++index];
		} else if (strcmp(argv[index], "--key") == 0 && index + 1 < argc) {
			proxy_key_file = argv[++index];
		} else {
			fprintf(stderr,
				"usage: %s [--listen addr] [--port port] [--backend-host host] [--backend-port port] [--cert path] [--key path]\n",
				argv[0]);
			return -1;
		}
	}

	return 0;
}

int run_event_server(mbedtls_net_context *listen_fd, mbedtls_ssl_config *conf);

int main(int argc, char **argv)
{
	int ret;
	mbedtls_net_context listen_fd;
	mbedtls_entropy_context entropy;
	mbedtls_ctr_drbg_context ctr_drbg;
	mbedtls_ssl_config conf;
	mbedtls_ssl_cache_context cache;
	mbedtls_ssl_ticket_context tickets;
	mbedtls_x509_crt srvcert;
	mbedtls_pk_context pkey;
	const char *pers = "thingino_agent_tls_proxy";

	if (parse_args(argc, argv) != 0) {
		return 1;
	}

	signal(SIGINT, signal_handler);
	signal(SIGTERM, signal_handler);

	mbedtls_net_init(&listen_fd);
	mbedtls_ssl_config_init(&conf);
	mbedtls_ssl_cache_init(&cache);
	mbedtls_ssl_ticket_init(&tickets);
	mbedtls_x509_crt_init(&srvcert);
	mbedtls_pk_init(&pkey);
	mbedtls_entropy_init(&entropy);
	mbedtls_ctr_drbg_init(&ctr_drbg);

	ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
		(const unsigned char *)pers, strlen(pers));
	if (ret != 0) {
		fprintf(stderr, "mbedtls_ctr_drbg_seed failed: -0x%x\n", -ret);
		goto exit;
	}

	ret = mbedtls_x509_crt_parse_file(&srvcert, proxy_cert_file);
	if (ret != 0) {
		fprintf(stderr, "mbedtls_x509_crt_parse_file failed for %s: -0x%x\n", proxy_cert_file, -ret);
		goto exit;
	}

	ret = mbedtls_pk_parse_keyfile(&pkey, proxy_key_file, NULL,
		mbedtls_ctr_drbg_random, &ctr_drbg);
	if (ret != 0) {
		fprintf(stderr, "mbedtls_pk_parse_keyfile failed for %s: -0x%x\n", proxy_key_file, -ret);
		goto exit;
	}

	ret = mbedtls_ssl_config_defaults(&conf, MBEDTLS_SSL_IS_SERVER,
		MBEDTLS_SSL_TRANSPORT_STREAM, MBEDTLS_SSL_PRESET_DEFAULT);
	if (ret != 0) {
		fprintf(stderr, "mbedtls_ssl_config_defaults failed: -0x%x\n", -ret);
		goto exit;
	}

	mbedtls_ssl_conf_rng(&conf, mbedtls_ctr_drbg_random, &ctr_drbg);
	mbedtls_ssl_conf_ciphersuites(&conf, preferred_ciphers);
	mbedtls_ssl_conf_renegotiation(&conf, MBEDTLS_SSL_RENEGOTIATION_DISABLED);
#if defined(MBEDTLS_SSL_PROTO_TLS1_2)
	mbedtls_ssl_conf_max_tls_version(&conf, MBEDTLS_SSL_VERSION_TLS1_2);
	mbedtls_ssl_conf_min_tls_version(&conf, MBEDTLS_SSL_VERSION_TLS1_2);
#endif
	if ((ret = mbedtls_ssl_ticket_setup(&tickets, mbedtls_ctr_drbg_random, &ctr_drbg,
		MBEDTLS_CIPHER_AES_128_GCM, 86400)) != 0) {
		fprintf(stderr, "warning: ssl_ticket_setup failed: -0x%x\n", -ret);
	}
	mbedtls_ssl_conf_session_cache(&conf, &cache, mbedtls_ssl_cache_get, mbedtls_ssl_cache_set);
	mbedtls_ssl_conf_session_tickets(&conf, MBEDTLS_SSL_SESSION_TICKETS_ENABLED);
	mbedtls_ssl_conf_session_tickets_cb(&conf, mbedtls_ssl_ticket_write,
		mbedtls_ssl_ticket_parse, &tickets);

	ret = mbedtls_ssl_conf_own_cert(&conf, &srvcert, &pkey);
	if (ret != 0) {
		fprintf(stderr, "mbedtls_ssl_conf_own_cert failed: -0x%x\n", -ret);
		goto exit;
	}

	ret = mbedtls_net_bind(&listen_fd, proxy_listen_host, proxy_listen_port,
		MBEDTLS_NET_PROTO_TCP);
	if (ret != 0) {
		fprintf(stderr, "mbedtls_net_bind failed for %s:%s: -0x%x\n",
			proxy_listen_host ? proxy_listen_host : "0.0.0.0", proxy_listen_port, -ret);
		goto exit;
	}

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
	return ret == 0 ? 0 : 1;
}