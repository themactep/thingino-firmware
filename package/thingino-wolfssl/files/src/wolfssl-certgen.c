/*
 * wolfSSL ECDSA Certificate Generator for Thingino
 *
 * This program uses wolfSSL's ECC certificate generation API to create
 * fast self-signed SSL certificates for the Thingino web interface.
 *
 * ECDSA provides much faster generation than RSA:
 * - 256-bit ECDSA: ~1-3 seconds (equivalent to 3072-bit RSA security)
 * - 224-bit ECDSA: ~1-2 seconds (equivalent to 2048-bit RSA security)
 *
 * Based on wolfSSL documentation: https://www.wolfssl.com/documentation/manuals/wolfssl/chapter07.html
 *
 * Compile with: gcc -o wolfssl-certgen wolfssl-certgen.c -lwolfssl
 */

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <getopt.h>
#include <sys/stat.h>

#ifdef HAVE_WOLFSSL
#include <wolfssl/options.h>
#include <wolfssl/wolfcrypt/settings.h>
#include <wolfssl/wolfcrypt/ecc.h>
#include <wolfssl/wolfcrypt/asn_public.h>
#include <wolfssl/wolfcrypt/random.h>
#include <wolfssl/ssl.h>

#ifdef WOLFSSL_CERT_GEN
#include <wolfssl/wolfcrypt/asn.h>
#endif
#endif

#define DEFAULT_KEY_SIZE 256  /* 256-bit ECDSA - fast and secure for embedded devices */
#define DEFAULT_DAYS 3650
#define MAX_HOSTNAME_LEN 256
#define MAX_PATH_LEN 512

static void usage(const char *prog) {
    printf("Usage: %s -h hostname -c cert_file -k key_file [-d days] [-s key_size]\n", prog);
    printf("  -h, --hostname   Hostname for certificate CN\n");
    printf("  -c, --cert       Output certificate file\n");
    printf("  -k, --key        Output private key file\n");
    printf("  -d, --days       Certificate validity in days (default: %d)\n", DEFAULT_DAYS);
    printf("  -s, --key-size   ECDSA key size in bits (default: %d)\n", DEFAULT_KEY_SIZE);
    printf("                   Supported: 224, 256, 384, 521\n");
    printf("  --help           Show this help message\n");
}

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN

static int generate_ecdsa_key_and_cert(const char *cert_file, const char *key_file,
                                       const char *hostname, int key_size, int days) {
    WC_RNG rng;
    ecc_key key;
    Cert cert;
    int ret;

    printf("Generating ECDSA key and certificate using wolfSSL APIs...\n");

    /* Initialize wolfSSL */
    wolfSSL_Init();

    /* Initialize random number generator */
    ret = wc_InitRng(&rng);
    if (ret != 0) {
        fprintf(stderr, "RNG init failed: %d\n", ret);
        return -1;
    }

    /* Initialize ECC key */
    ret = wc_ecc_init(&key);
    if (ret != 0) {
        fprintf(stderr, "ECC init failed: %d\n", ret);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Generate ECC key (32 bytes = 256-bit) */
    printf("Generating %d-bit ECDSA key pair", key_size);
    fflush(stdout);
    ret = wc_ecc_make_key(&rng, 32, &key);
    if (ret != 0) {
        fprintf(stderr, "\nECC key generation failed: %d\n", ret);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    printf(" ✓\n");

    /* Initialize certificate */
    wc_InitCert(&cert);

    /* Set certificate fields */
    strncpy(cert.subject.country, "US", CTC_NAME_SIZE);
    strncpy(cert.subject.state, "CA", CTC_NAME_SIZE);
    strncpy(cert.subject.locality, "San Francisco", CTC_NAME_SIZE);
    strncpy(cert.subject.org, "Thingino", CTC_NAME_SIZE);
    strncpy(cert.subject.unit, "Camera", CTC_NAME_SIZE);
    strncpy(cert.subject.commonName, hostname, CTC_NAME_SIZE);
    strncpy(cert.subject.email, "admin@thingino.local", CTC_NAME_SIZE);
    cert.daysValid = days;
    cert.selfSigned = 1;  /* Self-signed certificate */
    cert.sigType = CTC_SHA256wECDSA;  /* Use ECDSA signature */

    /* Set issuer same as subject for self-signed cert */
    memcpy(&cert.issuer, &cert.subject, sizeof(CertName));

    /* Create certificate with ECC key using two-step process */
    printf("Generating self-signed certificate for %s", hostname);
    fflush(stdout);
    byte derCert[4096];
    int certSz;

    /* First create the certificate body */
    certSz = wc_MakeCert(&cert, derCert, sizeof(derCert), NULL, &key, &rng);
    if (certSz <= 0) {
        fprintf(stderr, "\nCertificate body creation failed: %d\n", certSz);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Then sign it with the ECC key */
    certSz = wc_SignCert(cert.bodySz, cert.sigType, derCert, sizeof(derCert), NULL, &key, &rng);
    if (certSz <= 0) {
        fprintf(stderr, "\nCertificate signing failed: %d\n", certSz);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    printf(" ✓\n");

    /* Convert DER to PEM and save certificate */
    byte pemCert[4096];
    int pemCertSz;
    pemCertSz = wc_DerToPem(derCert, certSz, pemCert, sizeof(pemCert), CERT_TYPE);
    if (pemCertSz <= 0) {
        fprintf(stderr, "DER to PEM conversion failed: %d\n", pemCertSz);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Save certificate to file */
    FILE* certFile = fopen(cert_file, "wb");
    if (certFile == NULL) {
        fprintf(stderr, "Failed to open certificate file: %s\n", cert_file);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    fwrite(pemCert, 1, pemCertSz, certFile);
    fclose(certFile);

    /* Save private key to file */
    byte keyDer[1024];
    int keyDerSz;
    byte pemKey[4096];
    int pemKeySz;

    /* First convert ECC key to DER format */
    keyDerSz = wc_EccKeyToDer(&key, keyDer, sizeof(keyDer));
    if (keyDerSz <= 0) {
        fprintf(stderr, "Key to DER conversion failed: %d\n", keyDerSz);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Then convert DER to PEM format */
    pemKeySz = wc_DerToPem(keyDer, keyDerSz, pemKey, sizeof(pemKey), ECC_PRIVATEKEY_TYPE);
    if (pemKeySz <= 0) {
        fprintf(stderr, "Key DER to PEM conversion failed: %d\n", pemKeySz);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    FILE* keyFile = fopen(key_file, "wb");
    if (keyFile == NULL) {
        fprintf(stderr, "Failed to open key file: %s\n", key_file);
        wc_ecc_free(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    fwrite(pemKey, 1, pemKeySz, keyFile);
    fclose(keyFile);

    /* Set proper file permissions */
    chmod(key_file, 0600);
    chmod(cert_file, 0644);

    /* Cleanup */
    wc_ecc_free(&key);
    wc_FreeRng(&rng);
    wolfSSL_Cleanup();

    printf("ECDSA certificate and key generated successfully!\n");
    printf("Certificate: %s\n", cert_file);
    printf("Private key: %s\n", key_file);
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
                if (key_size != 224 && key_size != 256 && key_size != 384 && key_size != 521) {
                    fprintf(stderr, "Invalid ECDSA key size: %s\n", optarg);
                    fprintf(stderr, "Supported sizes: 224, 256, 384, 521\n");
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

    printf("Generating ECDSA SSL certificate for hostname: %s\n", hostname);

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN
    /* Generate ECDSA key and self-signed certificate */
    if (generate_ecdsa_key_and_cert(cert_file, key_file, hostname, key_size, days) != 0) {
        fprintf(stderr, "Failed to generate certificate and key\n");
        return 1;
    }

    printf("ECDSA SSL certificate and key generated successfully\n");
    return 0;
#else
    fprintf(stderr, "Error: wolfSSL was not compiled with certificate generation support\n");
    fprintf(stderr, "Please rebuild wolfSSL with --enable-certgen --enable-keygen --enable-ecc\n");
    return 1;
#endif
#else
    fprintf(stderr, "Error: wolfSSL library not available\n");
    return 1;
#endif
}
