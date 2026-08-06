#include <errno.h>
#include <pthread.h>
#include <stdatomic.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>
#include <unistd.h>

#include <openssl/sha.h>

typedef struct {
    const unsigned char *prefix;
    size_t prefix_len, suffix_len, nonce_offset;
    uint32_t target_word;
    uint64_t start, step, limit;
    int little_endian;
    atomic_int *stop;
    atomic_ullong *trials;
    atomic_ullong *found;
} worker_args_t;

static uint64_t parse_u64(const char *s) {
    char *end = NULL; errno = 0; unsigned long long v = strtoull(s, &end, 0);
    if (errno || !end || *end) { fprintf(stderr, "invalid integer: %s\n", s); exit(2); }
    return (uint64_t)v;
}

static unsigned char *read_file_slice(const char *path, size_t start, size_t end, size_t *out_len) {
    FILE *fp = fopen(path, "rb");
    if (!fp) { perror(path); exit(2); }
    if (fseek(fp, 0, SEEK_END) != 0) { perror("fseek"); exit(2); }
    long size = ftell(fp);
    if (size < 0 || end > (size_t)size || start >= end) { fprintf(stderr, "invalid slice for %s\n", path); exit(2); }
    if (fseek(fp, (long)start, SEEK_SET) != 0) { perror("fseek"); exit(2); }
    *out_len = end - start;
    unsigned char *buf = malloc(*out_len);
    if (!buf) { perror("malloc"); exit(2); }
    if (fread(buf, 1, *out_len, fp) != *out_len) { perror("fread"); exit(2); }
    fclose(fp);
    return buf;
}

static void write_nonce(unsigned char *dst, uint64_t nonce, int little_endian) {
    uint32_t n = (uint32_t)nonce;
    if (little_endian) {
        dst[0] = (unsigned char)(n & 0xffu); dst[1] = (unsigned char)((n >> 8) & 0xffu);
        dst[2] = (unsigned char)((n >> 16) & 0xffu); dst[3] = (unsigned char)((n >> 24) & 0xffu);
    } else {
        dst[0] = (unsigned char)((n >> 24) & 0xffu); dst[1] = (unsigned char)((n >> 16) & 0xffu);
        dst[2] = (unsigned char)((n >> 8) & 0xffu); dst[3] = (unsigned char)(n & 0xffu);
    }
}

static void *worker_main(void *opaque) {
    worker_args_t *args = (worker_args_t *)opaque;
    SHA256_CTX prefix_ctx;
    unsigned char digest[SHA256_DIGEST_LENGTH];
    unsigned char *suffix = malloc(args->suffix_len);
    if (!suffix) { perror("malloc"); return NULL; }
    memcpy(suffix, args->prefix + args->prefix_len, args->suffix_len);

    SHA256_Init(&prefix_ctx);
    SHA256_Update(&prefix_ctx, args->prefix, args->prefix_len);

    uint64_t nonce = args->start;
    uint64_t local = 0;
    while (nonce < args->limit && !atomic_load(args->stop)) {
        write_nonce(suffix + args->nonce_offset, nonce, args->little_endian);
        SHA256_CTX ctx = prefix_ctx;
        SHA256_Update(&ctx, suffix, args->suffix_len);
        SHA256_Final(digest, &ctx);
        uint32_t word = ((uint32_t)digest[0] << 24) | ((uint32_t)digest[1] << 16) | ((uint32_t)digest[2] << 8) | digest[3];
        local++;
        if (word == args->target_word) {
            atomic_store(args->found, nonce);
            atomic_store(args->stop, 1);
            break;
        }
        if ((local & 0xfffULL) == 0) atomic_fetch_add(args->trials, 0x1000ULL);
        nonce += args->step;
    }
    atomic_fetch_add(args->trials, local & 0xfffULL);
    free(suffix);
    return NULL;
}

static void *progress_main(void *opaque) {
    atomic_ullong *trials = ((atomic_ullong **)opaque)[0];
    atomic_int *stop = ((atomic_int **)opaque)[1];
    struct timespec start; clock_gettime(CLOCK_MONOTONIC, &start);
    while (!atomic_load(stop)) {
        sleep(1);
        struct timespec now; clock_gettime(CLOCK_MONOTONIC, &now);
        double elapsed = (now.tv_sec - start.tv_sec) + (now.tv_nsec - start.tv_nsec) / 1e9;
        unsigned long long count = atomic_load(trials);
        fprintf(stderr, "\rtries=%llu rate=%.2f Mh/s", count, elapsed > 0.0 ? (count / elapsed) / 1e6 : 0.0);
        fflush(stderr);
    }
    fprintf(stderr, "\n");
    return NULL;
}

int main(int argc, char **argv) {
    const char *image = NULL, *byteorder = "little";
    size_t payload_offset = 0, hash_end = 0, nonce_offset = 0;
    uint32_t target_word = 0; uint64_t nonce_start = 0, nonce_limit = 0x100000000ULL;
    int workers = 0, quiet = 0;
    for (int i = 1; i < argc; i++) {
        if (!strcmp(argv[i], "--image") && i + 1 < argc) image = argv[++i];
        else if (!strcmp(argv[i], "--payload-offset") && i + 1 < argc) payload_offset = (size_t)parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--hash-end") && i + 1 < argc) hash_end = (size_t)parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--nonce-offset") && i + 1 < argc) nonce_offset = (size_t)parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--target-word") && i + 1 < argc) target_word = (uint32_t)parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--workers") && i + 1 < argc) workers = (int)parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--nonce-start") && i + 1 < argc) nonce_start = parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--nonce-limit") && i + 1 < argc) nonce_limit = parse_u64(argv[++i]);
        else if (!strcmp(argv[i], "--nonce-byteorder") && i + 1 < argc) byteorder = argv[++i];
        else if (!strcmp(argv[i], "--quiet")) quiet = 1;
        else { fprintf(stderr, "unknown/invalid arg: %s\n", argv[i]); return 2; }
    }
    if (!image || !payload_offset || !hash_end || !workers || nonce_offset + 4 > hash_end - payload_offset) {
        fprintf(stderr, "usage: --image <file> --payload-offset <n> --hash-end <n> --nonce-offset <n> --target-word <n> --workers <n>\n");
        return 2;
    }

    size_t payload_len = 0;
    unsigned char *payload = read_file_slice(image, payload_offset, hash_end, &payload_len);
    size_t block_start = nonce_offset & ~(size_t)63;
    size_t mutable_off = nonce_offset - block_start;
    worker_args_t *args = calloc((size_t)workers, sizeof(*args));
    pthread_t *threads = calloc((size_t)workers, sizeof(*threads));
    pthread_t progress;
    atomic_int stop = 0;
    atomic_ullong trials = 0;
    atomic_ullong found; atomic_init(&found, UINT64_MAX);
    void *progress_args[2] = { &trials, &stop };

    for (int i = 0; i < workers; i++) {
        args[i] = (worker_args_t){
            .prefix = payload, .prefix_len = block_start, .suffix_len = payload_len - block_start,
            .nonce_offset = mutable_off, .target_word = target_word, .start = nonce_start + (uint64_t)i,
            .step = (uint64_t)workers, .limit = nonce_limit, .little_endian = strcmp(byteorder, "big") != 0,
            .stop = &stop, .trials = &trials, .found = &found,
        };
        pthread_create(&threads[i], NULL, worker_main, &args[i]);
    }
    if (!quiet) pthread_create(&progress, NULL, progress_main, progress_args);
    for (int i = 0; i < workers; i++) pthread_join(threads[i], NULL);
    atomic_store(&stop, 1);
    if (!quiet) pthread_join(progress, NULL);

    uint64_t nonce = atomic_load(&found);
    if (nonce == UINT64_MAX) {
        printf("status=not_found\n");
        free(payload); free(args); free(threads);
        return 1;
    }
    printf("nonce=0x%08llx\n", (unsigned long long)nonce);
    free(payload); free(args); free(threads);
    return 0;
}