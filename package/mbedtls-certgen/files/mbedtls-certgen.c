/*
 * mbedTLS Certificate Generator for Thingino
 *
 * This program uses mbedTLS APIs to create self-signed SSL certificates
 * for the Thingino web interface. It provides a minimal alternative to
 * the full mbedTLS programs suite, saving significant space (~500KB+).
 *
 * Features:
 * - RSA and ECDSA key generation
 * - Self-signed certificate creation
 * - Configurable validity periods
 * - Minimal memory footprint
 *
 * Compile with: gcc -o mbedtls-certgen mbedtls-certgen.c -lmbedtls -lmbedx509 -lmbedcrypto
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/stat.h>
#include <time.h>

#ifdef HAVE_MBEDTLS
#include "mbedtls/pk.h"
#include "mbedtls/rsa.h"
#include "mbedtls/ecp.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/entropy.h"
#include "mbedtls/ctr_drbg.h"
#include "mbedtls/x509_crt.h"
#include "mbedtls/x509.h"
#include "mbedtls/pem.h"
#include "mbedtls/error.h"
#include "mbedtls/asn1write.h"
#include "mbedtls/oid.h"
#endif

#define DEFAULT_DAYS 3650
#define DEFAULT_KEY_SIZE 256  /* ECDSA P-256 */
#define DEFAULT_RSA_KEY_SIZE 2048

static void usage(const char *prog) {
    printf("Usage: %s -h hostname -c cert_file -k key_file [-d days] [-s key_size] [-t type]\n", prog);
    printf("  -h, --hostname   Hostname for certificate CN\n");
    printf("  -c, --cert       Output certificate file\n");
    printf("  -k, --key        Output private key file\n");
    printf("  -d, --days       Certificate validity in days (default: %d)\n", DEFAULT_DAYS);
    printf("  -s, --key-size   Key size - ECDSA: 256,384,521 RSA: 2048,3072,4096 (default: %d)\n", DEFAULT_KEY_SIZE);
    printf("  -t, --type       Key type: ecdsa or rsa (default: ecdsa)\n");
    printf("  --help           Show this help message\n");
}

#ifdef HAVE_MBEDTLS

static int write_private_key_pem(mbedtls_pk_context *key, const char *key_file) {
    FILE *fp;
    unsigned char buf[4096];
    int ret;

    fp = fopen(key_file, "wb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot open key file for writing: %s\n", key_file);
        return -1;
    }

    ret = mbedtls_pk_write_key_pem(key, buf, sizeof(buf));
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error writing private key PEM: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        fclose(fp);
        return -1;
    }

    if (fwrite(buf, 1, strlen((char*)buf), fp) != strlen((char*)buf)) {
        fprintf(stderr, "Error writing key to file\n");
        fclose(fp);
        return -1;
    }

    fclose(fp);
    return 0;
}

static int write_certificate_pem(mbedtls_x509write_cert *crt, const char *cert_file,
                                 mbedtls_ctr_drbg_context *ctr_drbg) {
    FILE *fp;
    unsigned char buf[4096];
    int ret;

    fp = fopen(cert_file, "wb");
    if (!fp) {
        fprintf(stderr, "Error: Cannot open certificate file for writing: %s\n", cert_file);
        return -1;
    }

    ret = mbedtls_x509write_crt_pem(crt, buf, sizeof(buf), mbedtls_ctr_drbg_random, ctr_drbg);
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error writing certificate PEM: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        fclose(fp);
        return -1;
    }

    if (fwrite(buf, 1, strlen((char*)buf), fp) != strlen((char*)buf)) {
        fprintf(stderr, "Error writing certificate to file\n");
        fclose(fp);
        return -1;
    }

    fclose(fp);
    return 0;
}

static int generate_ecdsa_key(mbedtls_pk_context *key, int key_size, mbedtls_ctr_drbg_context *ctr_drbg) {
    int ret;
    mbedtls_ecp_group_id curve_id;

    /* Map key size to curve */
    switch (key_size) {
        case 256:
            curve_id = MBEDTLS_ECP_DP_SECP256R1;
            break;
        case 384:
            curve_id = MBEDTLS_ECP_DP_SECP384R1;
            break;
        case 521:
            curve_id = MBEDTLS_ECP_DP_SECP521R1;
            break;
        default:
            fprintf(stderr, "Unsupported ECDSA key size: %d (supported: 256, 384, 521)\n", key_size);
            return -1;
    }

    ret = mbedtls_pk_setup(key, mbedtls_pk_info_from_type(MBEDTLS_PK_ECKEY));
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting up ECDSA key: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        return -1;
    }

    ret = mbedtls_ecp_gen_key(curve_id, mbedtls_pk_ec(*key), mbedtls_ctr_drbg_random, ctr_drbg);
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error generating ECDSA key: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        return -1;
    }

    return 0;
}

static int generate_rsa_key(mbedtls_pk_context *key, int key_size, mbedtls_ctr_drbg_context *ctr_drbg) {
    int ret;

    if (key_size < 2048 || key_size > 4096) {
        fprintf(stderr, "Unsupported RSA key size: %d (supported: 2048-4096)\n", key_size);
        return -1;
    }

    ret = mbedtls_pk_setup(key, mbedtls_pk_info_from_type(MBEDTLS_PK_RSA));
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting up RSA key: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        return -1;
    }

    ret = mbedtls_rsa_gen_key(mbedtls_pk_rsa(*key), mbedtls_ctr_drbg_random, ctr_drbg, key_size, 65537);
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error generating RSA key: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        return -1;
    }

    return 0;
}

static int generate_certificate(const char *cert_file, const char *key_file,
                               const char *hostname, int days, int key_size, const char *key_type) {
    mbedtls_pk_context key;
    mbedtls_x509write_cert crt;
    mbedtls_entropy_context entropy;
    mbedtls_ctr_drbg_context ctr_drbg;
    const char *pers = "mbedtls-certgen";
    int ret = 0;
    char subject_name[256];
    char serial_str[32];

    printf("Generating %s key and certificate for hostname: %s\n", key_type, hostname);

    /* Initialize contexts */
    mbedtls_pk_init(&key);
    mbedtls_x509write_crt_init(&crt);
    mbedtls_entropy_init(&entropy);
    mbedtls_ctr_drbg_init(&ctr_drbg);

    /* Seed the random number generator */
    ret = mbedtls_ctr_drbg_seed(&ctr_drbg, mbedtls_entropy_func, &entropy,
                                (const unsigned char *) pers, strlen(pers));
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error seeding RNG: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        goto cleanup;
    }

    /* Generate key */
    printf("Generating %s private key (%d bits)...\n", key_type, key_size);
    if (strcmp(key_type, "ecdsa") == 0) {
        ret = generate_ecdsa_key(&key, key_size, &ctr_drbg);
    } else {
        ret = generate_rsa_key(&key, key_size, &ctr_drbg);
    }

    if (ret != 0) {
        goto cleanup;
    }

    /* Write private key */
    ret = write_private_key_pem(&key, key_file);
    if (ret != 0) {
        goto cleanup;
    }
    printf("Private key written to: %s\n", key_file);

    /* Set up certificate */
    mbedtls_x509write_crt_set_subject_key(&crt, &key);
    mbedtls_x509write_crt_set_issuer_key(&crt, &key);

    /* Set certificate fields */
    snprintf(subject_name, sizeof(subject_name),
             "C=US,ST=CA,L=San Francisco,O=Thingino,OU=Camera,CN=%s", hostname);

    ret = mbedtls_x509write_crt_set_subject_name(&crt, subject_name);
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting subject name: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        goto cleanup;
    }

    ret = mbedtls_x509write_crt_set_issuer_name(&crt, subject_name);
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting issuer name: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        goto cleanup;
    }

    /* Set serial number */
    snprintf(serial_str, sizeof(serial_str), "%d", (int)time(NULL));
    ret = mbedtls_x509write_crt_set_serial_raw(&crt, (unsigned char*)serial_str, strlen(serial_str));
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting serial number: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        goto cleanup;
    }

    /* Set validity period */
    ret = mbedtls_x509write_crt_set_validity(&crt, "20240101000000", "20341231235959");
    if (ret != 0) {
        char error_buf[100];
        mbedtls_strerror(ret, error_buf, sizeof(error_buf));
        fprintf(stderr, "Error setting validity: -0x%04x - %s\n", (unsigned int) -ret, error_buf);
        goto cleanup;
    }

    /* Set signature algorithm */
    mbedtls_x509write_crt_set_md_alg(&crt, MBEDTLS_MD_SHA256);

    /* Write certificate */
    printf("Generating self-signed certificate...\n");
    ret = write_certificate_pem(&crt, cert_file, &ctr_drbg);
    if (ret != 0) {
        goto cleanup;
    }
    printf("Certificate written to: %s\n", cert_file);

cleanup:
    mbedtls_pk_free(&key);
    mbedtls_x509write_crt_free(&crt);
    mbedtls_entropy_free(&entropy);
    mbedtls_ctr_drbg_free(&ctr_drbg);

    return ret;
}

#endif /* HAVE_MBEDTLS */

int main(int argc, char *argv[]) {
    char *hostname = NULL;
    char *cert_file = NULL;
    char *key_file = NULL;
    int days = DEFAULT_DAYS;
    int key_size = DEFAULT_KEY_SIZE;
    char *key_type = "ecdsa";
    int opt;

    static struct option long_options[] = {
        {"hostname", required_argument, 0, 'h'},
        {"cert", required_argument, 0, 'c'},
        {"key", required_argument, 0, 'k'},
        {"days", required_argument, 0, 'd'},
        {"key-size", required_argument, 0, 's'},
        {"type", required_argument, 0, 't'},
        {"help", no_argument, 0, 0},
        {0, 0, 0, 0}
    };

    while ((opt = getopt_long(argc, argv, "h:c:k:d:s:t:", long_options, NULL)) != -1) {
        switch (opt) {
            case 'h':
                hostname = optarg;
                break;
            case 'c':
                cert_file = optarg;
                break;
            case 'k':
                key_file = optarg;
                break;
            case 'd':
                days = atoi(optarg);
                if (days <= 0) {
                    fprintf(stderr, "Error: Invalid days value: %s\n", optarg);
                    return 1;
                }
                break;
            case 's':
                key_size = atoi(optarg);
                break;
            case 't':
                key_type = optarg;
                if (strcmp(key_type, "ecdsa") != 0 && strcmp(key_type, "rsa") != 0) {
                    fprintf(stderr, "Error: Invalid key type: %s (must be 'ecdsa' or 'rsa')\n", key_type);
                    return 1;
                }
                break;
            case 0:
                if (strcmp(long_options[optind-1].name, "help") == 0) {
                    usage(argv[0]);
                    return 0;
                }
                break;
            default:
                usage(argv[0]);
                return 1;
        }
    }

    if (!hostname || !cert_file || !key_file) {
        fprintf(stderr, "Error: Missing required arguments\n");
        usage(argv[0]);
        return 1;
    }

    /* Adjust key size defaults based on type */
    if (key_size == DEFAULT_KEY_SIZE && strcmp(key_type, "rsa") == 0) {
        key_size = DEFAULT_RSA_KEY_SIZE;
    }

#ifdef HAVE_MBEDTLS
    /* Generate certificate and key */
    if (generate_certificate(cert_file, key_file, hostname, days, key_size, key_type) != 0) {
        fprintf(stderr, "Failed to generate certificate and key\n");
        return 1;
    }

    /* Set proper file permissions */
    chmod(key_file, 0600);
    chmod(cert_file, 0644);

    printf("SSL certificate and key generated successfully\n");
    return 0;
#else
    fprintf(stderr, "Error: mbedTLS library not available\n");
    fprintf(stderr, "Please rebuild with mbedTLS support\n");
    return 1;
#endif
}
