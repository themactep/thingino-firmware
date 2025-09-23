/*
 * wolfSSL Certificate Generator for Thingino
 *
 * This program uses wolfSSL's certificate generation API to create
 * self-signed SSL certificates for the Thingino web interface.
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
#include <wolfssl/wolfcrypt/rsa.h>
#include <wolfssl/wolfcrypt/asn.h>
#include <wolfssl/wolfcrypt/asn_public.h>
#include <wolfssl/wolfcrypt/error-crypt.h>
#include <wolfssl/wolfcrypt/random.h>
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

static int generate_rsa_key_and_cert(const char *cert_file, const char *key_file,
                                     const char *hostname, int key_size, int days) {
    RsaKey key;
    WC_RNG rng;
    Cert cert;
    int ret;
    FILE *fp;
    byte keyDer[4096];
    int keyDerSz;
    byte keyPem[8192];
    int keyPemSz;
    byte certDer[4096];
    int certDerSz;
    byte certPem[8192];
    int certPemSz;

    printf("Generating RSA key and certificate using wolfSSL APIs...\n");

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
    printf("Generating %d-bit RSA key pair...\n", key_size);
    ret = wc_MakeRsaKey(&key, key_size, 65537, &rng);
    if (ret != 0) {
        fprintf(stderr, "Error generating RSA key: %d\n", ret);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Export private key to DER format */
    keyDerSz = wc_RsaKeyToDer(&key, keyDer, sizeof(keyDer));
    if (keyDerSz < 0) {
        fprintf(stderr, "Error converting key to DER: %d\n", keyDerSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Convert key DER to PEM */
    keyPemSz = wc_DerToPem(keyDer, keyDerSz, keyPem, sizeof(keyPem), PRIVATEKEY_TYPE);
    if (keyPemSz < 0) {
        fprintf(stderr, "Error converting key DER to PEM: %d\n", keyPemSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Initialize certificate */
    wc_InitCert(&cert);

    /* Set certificate subject information */
    strncpy(cert.subject.country, "US", CTC_NAME_SIZE);
    strncpy(cert.subject.state, "CA", CTC_NAME_SIZE);
    strncpy(cert.subject.locality, "San Francisco", CTC_NAME_SIZE);
    strncpy(cert.subject.org, "Thingino", CTC_NAME_SIZE);
    strncpy(cert.subject.unit, "Camera", CTC_NAME_SIZE);
    strncpy(cert.subject.commonName, hostname, CTC_NAME_SIZE);
    strncpy(cert.subject.email, "admin@thingino.local", CTC_NAME_SIZE);

    /* Set certificate parameters */
    cert.daysValid = days;
    cert.selfSigned = 1;
    cert.sigType = CTC_SHA256wRSA;

    /* Generate self-signed certificate */
    printf("Generating self-signed certificate for %s...\n", hostname);
    certDerSz = wc_MakeSelfCert(&cert, certDer, sizeof(certDer), &key, &rng);
    if (certDerSz < 0) {
        fprintf(stderr, "Error generating certificate: %d\n", certDerSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Convert certificate DER to PEM */
    certPemSz = wc_DerToPem(certDer, certDerSz, certPem, sizeof(certPem), CERT_TYPE);
    if (certPemSz < 0) {
        fprintf(stderr, "Error converting certificate DER to PEM: %d\n", certPemSz);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    /* Write private key to file */
    fp = fopen(key_file, "w");
    if (!fp) {
        fprintf(stderr, "Error opening key file for writing: %s\n", key_file);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    if (fwrite(keyPem, 1, keyPemSz, fp) != (size_t)keyPemSz) {
        fprintf(stderr, "Error writing key file\n");
        fclose(fp);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    fclose(fp);

    /* Write certificate to file */
    fp = fopen(cert_file, "w");
    if (!fp) {
        fprintf(stderr, "Error opening certificate file for writing: %s\n", cert_file);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }

    if (fwrite(certPem, 1, certPemSz, fp) != (size_t)certPemSz) {
        fprintf(stderr, "Error writing certificate file\n");
        fclose(fp);
        wc_FreeRsaKey(&key);
        wc_FreeRng(&rng);
        return -1;
    }
    fclose(fp);

    /* Set proper file permissions */
    chmod(key_file, 0600);
    chmod(cert_file, 0644);

    /* Cleanup */
    wc_FreeRsaKey(&key);
    wc_FreeRng(&rng);

    printf("Certificate and key generated successfully!\n");
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
    /* Generate RSA key and self-signed certificate */
    if (generate_rsa_key_and_cert(cert_file, key_file, hostname, key_size, days) != 0) {
        fprintf(stderr, "Failed to generate certificate and key\n");
        return 1;
    }

    printf("SSL certificate and key generated successfully\n");
    return 0;
#else
    fprintf(stderr, "Error: wolfSSL was not compiled with certificate generation support\n");
    fprintf(stderr, "Please rebuild wolfSSL with --enable-certgen --enable-keygen\n");
    return 1;
#endif
#else
    fprintf(stderr, "Error: wolfSSL library not available\n");
    return 1;
#endif
}
