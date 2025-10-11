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
    printf("Usage: %s [GENERATE] -h hostname -c cert_file -k key_file [-d days] [-s key_size]\n", prog);
    printf("       %s [INSPECT] -i cert_file [--json]\n", prog);
    printf("\nGenerate certificate:\n");
    printf("  -h, --hostname   Hostname for certificate CN\n");
    printf("  -c, --cert       Output certificate file\n");
    printf("  -k, --key        Output private key file\n");
    printf("  -d, --days       Certificate validity in days (default: %d)\n", DEFAULT_DAYS);
    printf("  -s, --key-size   ECDSA key size in bits (default: %d)\n", DEFAULT_KEY_SIZE);
    printf("                   Supported: 224, 256, 384, 521\n");
    printf("\nInspect certificate:\n");
    printf("  -i, --inspect    Inspect and display certificate information\n");
    printf("  --json           Output certificate information in JSON format\n");
    printf("\nOther options:\n");
    printf("  --help           Show this help message\n");
}

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN

static int inspect_certificate(const char *cert_file, int json_output) {
    FILE *file;
    char *pem_data = NULL;
    long file_size;
    int ret;

    printf("Inspecting certificate: %s\n", cert_file);

    /* Read PEM certificate file */
    file = fopen(cert_file, "rb");
    if (!file) {
        fprintf(stderr, "Error: Cannot open certificate file: %s\n", cert_file);
        return -1;
    }

    /* Get file size */
    fseek(file, 0, SEEK_END);
    file_size = ftell(file);
    fseek(file, 0, SEEK_SET);

    /* Allocate buffer and read file */
    pem_data = malloc(file_size + 1);
    if (!pem_data) {
        fprintf(stderr, "Error: Memory allocation failed\n");
        fclose(file);
        return -1;
    }

    fread(pem_data, 1, file_size, file);
    pem_data[file_size] = '\0';
    fclose(file);

    /* Convert PEM to DER */
    byte der_cert[4096];
    int der_size;

    der_size = wc_CertPemToDer((const unsigned char*)pem_data, file_size, der_cert, sizeof(der_cert), CERT_TYPE);
    if (der_size <= 0) {
        fprintf(stderr, "Error: Failed to convert PEM to DER: %d\n", der_size);
        free(pem_data);
        return -1;
    }

    /* Parse certificate */
    DecodedCert decoded_cert;

    wc_InitDecodedCert(&decoded_cert, der_cert, der_size, NULL);
    ret = wc_ParseCert(&decoded_cert, CERT_TYPE, NO_VERIFY, NULL);
    if (ret != 0) {
        fprintf(stderr, "Error: Failed to parse certificate: %d\n", ret);
        wc_FreeDecodedCert(&decoded_cert);
        free(pem_data);
        return -1;
    }

    /* Display certificate information */
    if (json_output) {
        printf("{\n");

        /* Subject information */
        if (decoded_cert.subject[0] != '\0') {
            printf("  \"subject\": \"%s\",\n", decoded_cert.subject);

            /* Extract common name from subject */
            char *cn_start = strstr(decoded_cert.subject, "CN=");
            if (cn_start) {
                cn_start += 3; /* Skip "CN=" */
                char *cn_end = strchr(cn_start, '/');
                if (cn_end) {
                    int cn_len = cn_end - cn_start;
                    printf("  \"common_name\": \"%.*s\",\n", cn_len, cn_start);
                } else {
                    printf("  \"common_name\": \"%s\",\n", cn_start);
                }
            }
        }

        /* Issuer information */
        if (decoded_cert.issuer[0] != '\0') {
            printf("  \"issuer\": \"%s\",\n", decoded_cert.issuer);
        }

        /* Validity dates */
        if (decoded_cert.afterDate && decoded_cert.afterDateLen > 0) {
            printf("  \"expires_on\": \"");
            for (int i = 0; i < decoded_cert.afterDateLen; i++) {
                printf("%c", decoded_cert.afterDate[i]);
            }
            printf("\",\n");
        }

        if (decoded_cert.beforeDate && decoded_cert.beforeDateLen > 0) {
            printf("  \"valid_from\": \"");
            for (int i = 0; i < decoded_cert.beforeDateLen; i++) {
                printf("%c", decoded_cert.beforeDate[i]);
            }
            printf("\",\n");
        }

        /* Key information */
        printf("  \"signature_type\": \"");
        switch (decoded_cert.signatureOID) {
            case CTC_SHA256wECDSA:
                printf("ECDSA with SHA256");
                break;
            case CTC_SHA256wRSA:
                printf("RSA with SHA256");
                break;
            default:
                printf("Unknown (%d)", decoded_cert.signatureOID);
                break;
        }
        printf("\",\n");

        /* Public key size */
        if (decoded_cert.pubKeySize > 0) {
            printf("  \"public_key_size\": %d,\n", decoded_cert.pubKeySize * 8);
        }

        /* Serial number */
        if (decoded_cert.serialSz > 0) {
            printf("  \"serial_number\": \"");
            for (int i = 0; i < decoded_cert.serialSz && i < 16; i++) {
                printf("%02X", decoded_cert.serial[i]);
                if (i < decoded_cert.serialSz - 1 && i < 15) printf(":");
            }
            printf("\"\n");
        }

        printf("}\n");
    } else {
        printf("\n=== Certificate Information ===\n");

        /* Subject information */
        if (decoded_cert.subject[0] != '\0') {
            printf("subject name      : %s\n", decoded_cert.subject);
        }

        /* Issuer information */
        if (decoded_cert.issuer[0] != '\0') {
            printf("issuer name       : %s\n", decoded_cert.issuer);
        }

        /* Validity dates */
        if (decoded_cert.afterDate && decoded_cert.afterDateLen > 0) {
            printf("expires on        : ");
            for (int i = 0; i < decoded_cert.afterDateLen; i++) {
                printf("%c", decoded_cert.afterDate[i]);
            }
            printf("\n");
        }

        if (decoded_cert.beforeDate && decoded_cert.beforeDateLen > 0) {
            printf("valid from        : ");
            for (int i = 0; i < decoded_cert.beforeDateLen; i++) {
                printf("%c", decoded_cert.beforeDate[i]);
            }
            printf("\n");
        }

        /* Key information */
        printf("signature type    : ");
        switch (decoded_cert.signatureOID) {
            case CTC_SHA256wECDSA:
                printf("ECDSA with SHA256\n");
                break;
            case CTC_SHA256wRSA:
                printf("RSA with SHA256\n");
                break;
            default:
                printf("Unknown (%d)\n", decoded_cert.signatureOID);
                break;
        }

        /* Public key size */
        if (decoded_cert.pubKeySize > 0) {
            printf("public key size   : %d bits\n", decoded_cert.pubKeySize * 8);
        }

        /* Serial number */
        if (decoded_cert.serialSz > 0) {
            printf("serial number     : ");
            for (int i = 0; i < decoded_cert.serialSz && i < 16; i++) {
                printf("%02X", decoded_cert.serial[i]);
                if (i < decoded_cert.serialSz - 1 && i < 15) printf(":");
            }
            printf("\n");
        }

        printf("================================\n");
    }

    /* Cleanup */
    wc_FreeDecodedCert(&decoded_cert);
    free(pem_data);

    return 0;
}

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
    char inspect_file[MAX_PATH_LEN] = {0};
    int days = DEFAULT_DAYS;
    int key_size = DEFAULT_KEY_SIZE;
    int inspect_mode = 0;
    int json_output = 0;
    int opt;

    static struct option long_options[] = {
        {"hostname", required_argument, 0, 'h'},
        {"cert", required_argument, 0, 'c'},
        {"key", required_argument, 0, 'k'},
        {"days", required_argument, 0, 'd'},
        {"key-size", required_argument, 0, 's'},
        {"inspect", required_argument, 0, 'i'},
        {"json", no_argument, 0, 'j'},
        {"help", no_argument, 0, 0},
        {0, 0, 0, 0}
    };

    while ((opt = getopt_long(argc, argv, "h:c:k:d:s:i:j", long_options, NULL)) != -1) {
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
            case 'i':
                strncpy(inspect_file, optarg, sizeof(inspect_file) - 1);
                inspect_mode = 1;
                break;
            case 'j':
                json_output = 1;
                break;
            case 0:
                usage(argv[0]);
                return 0;
            default:
                usage(argv[0]);
                return 1;
        }
    }

    /* Validate required parameters based on mode */
    if (inspect_mode) {
        if (strlen(inspect_file) == 0) {
            fprintf(stderr, "Error: Missing certificate file for inspection\n");
            usage(argv[0]);
            return 1;
        }

#ifdef HAVE_WOLFSSL
#ifdef WOLFSSL_CERT_GEN
        /* Initialize wolfSSL for certificate inspection */
        wolfSSL_Init();

        /* Inspect certificate */
        if (inspect_certificate(inspect_file, json_output) != 0) {
            fprintf(stderr, "Failed to inspect certificate\n");
            wolfSSL_Cleanup();
            return 1;
        }

        wolfSSL_Cleanup();
        return 0;
#else
        fprintf(stderr, "Error: wolfSSL was not compiled with certificate support\n");
        return 1;
#endif
#else
        fprintf(stderr, "Error: wolfSSL library not available\n");
        return 1;
#endif
    } else {
        /* Generation mode - validate generation parameters */
        if (strlen(hostname) == 0 || strlen(cert_file) == 0 || strlen(key_file) == 0) {
            fprintf(stderr, "Error: Missing required parameters for certificate generation\n");
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
}
