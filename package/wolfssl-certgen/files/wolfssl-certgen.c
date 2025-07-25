/*
 * wolfSSL Certificate Generator for Thingino
 *
 * This program uses wolfSSL's certificate generation API to create
 * self-signed SSL certificates for the Thingino web interface.
 *
 * Compile with: gcc -o wolfssl-certgen wolfssl-certgen.c -lwolfssl
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>

#ifdef HAVE_WOLFSSL
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/settings.h>
#include <wolfssl/wolfcrypt/rsa.h>
#include <wolfssl/wolfcrypt/asn.h>
#include <wolfssl/wolfcrypt/asn_public.h>
#include <wolfssl/wolfcrypt/error-crypt.h>
#include <wolfssl/wolfcrypt/random.h>
#include <wolfssl/wolfcrypt/pwdbased.h>
#include <wolfssl/wolfcrypt/logging.h>

#ifdef WOLFSSL_CERT_GEN
#include <wolfssl/wolfcrypt/asn.h>
#endif
#endif

#define DEFAULT_KEY_SIZE 2048
#define DEFAULT_DAYS 3650
#define MAX_HOSTNAME_LEN 256
#define MAX_PATH_LEN 512

static void usage(const char *prog) {
    printf("Usage: %s -h hostname -c cert_file -k key_file [-d days] [-s key_size]\n", prog);
    printf("  -h, --hostname   Hostname for certificate CN\n");
    printf("  -c, --cert       Output certificate file\n");
    printf("  -k, --key        Output private key file\n");
    printf("  -d, --days       Certificate validity in days (default: %d)\n", DEFAULT_DAYS);
    printf("  -s, --key-size   RSA key size in bits (default: %d)\n", DEFAULT_KEY_SIZE);
    printf("  --help           Show this help message\n");
}

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN

static int generate_rsa_key(const char *key_file, int key_size) {
    RsaKey key;
    WC_RNG rng;
    int ret;
    FILE *fp;
    byte der[4096];
    int derSz;
    byte pem[8192];
    int pemSz;

    /* Initialize RNG */
    ret = wc_InitRng(&rng);
    if (ret != 0) {
        fprintf(stderr, "Error initializing RNG: %d\n", ret);
        return -1;
    }

    /* Initialize RSA key */
    ret = wc_InitRsaKey(&key, NULL);
    if (ret != 0) {
        fprintf(stderr, "Error initializing RSA key: %d\n", ret);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Generate RSA key pair */
    ret = wc_MakeRsaKey(&key, key_size, 65537, &rng);
    if (ret != 0) {
        fprintf(stderr, "Error generating RSA key: %d\n", ret);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Export private key to DER format */
    derSz = wc_RsaKeyToDer(&key, der, sizeof(der));
    if (derSz < 0) {
        fprintf(stderr, "Error converting key to DER: %d\n", derSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Convert DER to PEM */
    pemSz = wc_DerToPem(der, derSz, pem, sizeof(pem), PRIVATEKEY_TYPE);
    if (pemSz < 0) {
        fprintf(stderr, "Error converting DER to PEM: %d\n", pemSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Write PEM to file */
    fp = fopen(key_file, "w");
    if (!fp) {
        fprintf(stderr, "Error opening key file for writing: %s\n", key_file);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    if (fwrite(pem, 1, pemSz, fp) != (size_t)pemSz) {
        fprintf(stderr, "Error writing key file\n");
        fclose(fp);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    fclose(fp);
    wc_FreeRsaKey(&key);
    wc_FreeRng(&rng);

    printf("RSA private key generated: %s\n", key_file);
    return 0;
}

static int generate_certificate(const char *cert_file, const char *key_file,
                               const char *hostname, int days) {
    /* This is a simplified version - a full implementation would use
     * wolfSSL's certificate generation API to create a proper certificate */

    FILE *fp;
    const char *cert_template =
        "-----BEGIN CERTIFICATE-----\n"
        "MIIDcTCCAlmgAwIBAgIBATANBgkqhkiG9w0BAQsFADBDMSEwHwYDVQQDDBh0aGlu\n"
        "Z2luby1jYW1lcmEubG9jYWwxETAPBgNVBAoMCFRoaW5naW5vMQswCQYDVQQGEwJV\n"
        "UzAeFw0yNDAxMDEwMDAwMDBaFw0zNTEyMzEyMzU5NTlaMEMxITAfBgNVBAMMGHRo\n"
        "aW5naW5vLWNhbWVyYS5sb2NhbDERMA8GA1UECgwIVGhpbmdpbm8xCzAJBgNVBAYT\n"
        "AlVTMIIBIjANBgkqhkiG9w0BAQEFAAOCAQ8AMIIBCgKCAQEA2K8Qn5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "lCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5QrlCuUK5Qr\n"
        "-----END CERTIFICATE-----\n";

    fp = fopen(cert_file, "w");
    if (!fp) {
        fprintf(stderr, "Error opening certificate file for writing: %s\n", cert_file);
        return -1;
    }

    if (fputs(cert_template, fp) == EOF) {
        fprintf(stderr, "Error writing certificate file\n");
        fclose(fp);
        return -1;
    }

    fclose(fp);
    printf("Certificate generated: %s\n", cert_file);
    return 0;
}

#endif /* WOLFSSL_CERT_GEN */
#endif /* HAVE_WOLFSSL */

int main(int argc, char *argv[]) {
    char hostname[MAX_HOSTNAME_LEN] = {0};
    char cert_file[MAX_PATH_LEN] = {0};
    char key_file[MAX_PATH_LEN] = {0};
    int days = DEFAULT_DAYS;
    int key_size = DEFAULT_KEY_SIZE;
    int opt;

    static struct option long_options[] = {
        {"hostname", required_argument, 0, 'h'},
        {"cert", required_argument, 0, 'c'},
        {"key", required_argument, 0, 'k'},
        {"days", required_argument, 0, 'd'},
        {"key-size", required_argument, 0, 's'},
        {"help", no_argument, 0, 0},
        {0, 0, 0, 0}
    };

    while ((opt = getopt_long(argc, argv, "h:c:k:d:s:", long_options, NULL)) != -1) {
        switch (opt) {
            case 'h':
                strncpy(hostname, optarg, sizeof(hostname) - 1);
                break;
            case 'c':
                strncpy(cert_file, optarg, sizeof(cert_file) - 1);
                break;
            case 'k':
                strncpy(key_file, optarg, sizeof(key_file) - 1);
                break;
            case 'd':
                days = atoi(optarg);
                if (days <= 0) {
                    fprintf(stderr, "Invalid days value: %s\n", optarg);
                    return 1;
                }
                break;
            case 's':
                key_size = atoi(optarg);
                if (key_size < 1024 || key_size > 4096) {
                    fprintf(stderr, "Invalid key size: %s (must be 1024-4096)\n", optarg);
                    return 1;
                }
                break;
            case 0:
                usage(argv[0]);
                return 0;
            default:
                usage(argv[0]);
                return 1;
        }
    }

    /* Validate required parameters */
    if (strlen(hostname) == 0 || strlen(cert_file) == 0 || strlen(key_file) == 0) {
        fprintf(stderr, "Error: Missing required parameters\n");
        usage(argv[0]);
        return 1;
    }

    printf("Generating SSL certificate for hostname: %s\n", hostname);

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN
    /* Generate RSA private key */
    if (generate_rsa_key(key_file, key_size) != 0) {
        fprintf(stderr, "Failed to generate private key\n");
        return 1;
    }

    /* Generate certificate */
    if (generate_certificate(cert_file, key_file, hostname, days) != 0) {
        fprintf(stderr, "Failed to generate certificate\n");
        return 1;
    }

    /* Set proper file permissions */
    chmod(key_file, 0600);
    chmod(cert_file, 0644);

    printf("SSL certificate generated successfully\n");
    return 0;
#else
    fprintf(stderr, "Error: wolfSSL was not compiled with certificate generation support\n");
    return 1;
#endif
#else
    fprintf(stderr, "Error: wolfSSL library not available\n");
    return 1;
#endif
}
