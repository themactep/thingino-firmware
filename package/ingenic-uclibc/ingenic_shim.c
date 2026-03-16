#include <fcntl.h>       // For file control options, off_t
#include <stdarg.h>      // For variable arguments handling
#include <stdio.h>       // For standard input/output functions, file handling
#include <stdlib.h>      // For standard library functions, abort
#include <sys/stat.h>    // For file status/statistics
#include <errno.h>       // For error number definitions
#include <string.h>      // For string handling functions
#include <unistd.h>      // For POSIX operating system API, syscall interface
#include <sys/syscall.h> // For syscall numbers and syscall interface
#include <stdint.h>      // For standard integer types
#include <ctype.h>       // For character type functions

/*
 * Shim to create missing function calls in the ingenic libimp library.
 */

#define DEBUG 0  // Set this to 1 to enable debug output or 0 to disable

#if DEBUG
#define DEBUG_PRINT(...) fprintf(__VA_ARGS__)
#else
#define DEBUG_PRINT(...) (void)0
#endif

void __pthread_register_cancel(void *buf) {
	DEBUG_PRINT(stderr, "[WARNING] Called __pthread_register_cancel. This is a shim and does nothing.\n");
}

void __pthread_unregister_cancel(void *buf) {
	DEBUG_PRINT(stderr, "[WARNING] Called __pthread_unregister_cancel. This is a shim and does nothing.\n");
}

void __assert(const char *msg, const char *file, int line) {
	DEBUG_PRINT(stderr, "Assertion failed: %s (%s: %d)\n", msg, file, line);
	abort();
}

int __fgetc_unlocked(FILE *stream) {
	DEBUG_PRINT(stderr, "[WARNING] Called __fgetc_unlocked. This is a shim and does nothing.\n");
	return fgetc(stream);
}

// Custom mmap implementations address an Ingenic library bug affecting memory mapping offsets.
// Using musl, the library requires specific handling of offsets, necessitating these workarounds.
// The first variant uses an `off_t` type for static memory mappings, aligning with systems where
// larger offset sizes may be needed. The second uses `uint32_t` for shared memory mappings,
// suitable for scenarios requiring defined, 32-bit wide offsets. Both adjust the offset by
// shifting it 12 bits right (off >> 12) before calling syscall with SYS_mmap2, ensuring proper
// offset handling despite the library's limitations.
#ifdef INGENIC_MMAP_STATIC
void *mmap(void *start, size_t len, int prot, int flags, int fd, off_t off) {
	DEBUG_PRINT(stderr, "[WARNING] Called INGENIC_MMAP_STATIC\n");
	return (void *)syscall(SYS_mmap2, start, len, prot, flags, fd, off >> 12);
}
#else // This else branch makes INGENIC_MMAP_SHARED the default if INGENIC_MMAP_STATIC is not defined
void *mmap(void *start, size_t len, int prot, int flags, int fd, uint32_t off) {
	DEBUG_PRINT(stderr, "[WARNING] Called INGENIC_MMAP_SHARED\n");
	return (void *)syscall(SYS_mmap2, start, len, prot, flags, fd, off >> 12);
}
#endif

/* Required for Xburst2 libraries */

int __fputc_unlocked(int c, FILE *stream) {
	DEBUG_PRINT(stderr, "[WARNING] Called __fputc_unlocked. This is a shim and does nothing.\n");
	return fputc(c, stream);
}

FILE* fopen64(const char *path, const char *mode) {
	DEBUG_PRINT(stderr, "[WARNING] Called fopen64. This is a shim and does nothing.\n");
	return fopen(path, mode);
}

int open64(const char *path, int flags, ...) {
	mode_t mode = 0;

	// Mode is only provided if O_CREAT is passed in flags
	if (flags & O_CREAT) {
		va_list args;
		va_start(args, flags);
		mode = va_arg(args, mode_t);
		va_end(args);
	}

	DEBUG_PRINT(stderr, "[WARNING] Called open64. This is a shim and does nothing.\n");
	if (flags & O_CREAT) {
		return open(path, flags, mode);
	} else {
		return open(path, flags);
	}
}

int fseeko64(FILE *stream, off_t offset, int whence) {
	DEBUG_PRINT(stderr, "[WARNING] Called fseeko64. This is a shim and does nothing.\n");
	return fseeko(stream, offset, whence);
}

void* mmap64(void *start, size_t len, int prot, int flags, int fd, uint32_t off) {
return (void *)syscall(SYS_mmap2, start, len, prot, flags, fd, off >> 12);
}

/* End Required for Xburst2 libraries */

/* glibc ctype compatibility for uclibc */
static unsigned short ctype_b_table[384];
static int ctype_tolower_table[384];
static int ctype_toupper_table[384];

static void __attribute__((constructor)) init_ctype_tables(void) {
    int i;
    unsigned short *b = ctype_b_table + 128;
    int *lower = ctype_tolower_table + 128;
    int *upper = ctype_toupper_table + 128;

    for (i = -128; i < 256; i++) {
        b[i] = 0;
        lower[i] = i;
        upper[i] = i;

        if (i >= 0 && i < 128) {
            // Manually classify characters to avoid uclibc ctype macro conflicts
            if ((i >= 'A' && i <= 'Z') || (i >= 'a' && i <= 'z')) b[i] |= 1024; // isalpha
            if (i >= '0' && i <= '9') b[i] |= 2048; // isdigit
            if (i == ' ' || i == '\t' || i == '\n' || i == '\r' || i == '\f' || i == '\v') b[i] |= 8192; // isspace
            if (i >= 'a' && i <= 'z') {
                b[i] |= 512; // islower
                upper[i] = i - 32; // toupper
            }
            if (i >= 'A' && i <= 'Z') {
                b[i] |= 256; // isupper
                lower[i] = i + 32; // tolower
            }
        }
    }
}

const unsigned short **__ctype_b_loc(void) {
    static const unsigned short *ptr = ctype_b_table + 128;
    return (const unsigned short **)&ptr;
}

const int **__ctype_tolower_loc(void) {
    static const int *ptr = ctype_tolower_table + 128;
    return (const int **)&ptr;
}

const int **__ctype_toupper_loc(void) {
    static const int *ptr = ctype_toupper_table + 128;
    return (const int **)&ptr;
}
