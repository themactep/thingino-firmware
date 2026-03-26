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
static __ctype_touplow_t ctype_tolower_table[384];
static __ctype_touplow_t ctype_toupper_table[384];

/* Old glibc compat (T20 libalog uses direct pointers, not _loc functions) */
unsigned short *__ctype_b;
__ctype_touplow_t *__ctype_tolower;
__ctype_touplow_t *__ctype_toupper;

static void __attribute__((constructor)) init_ctype_tables(void) {
    int i;
    unsigned short *b = ctype_b_table + 128;
    __ctype_touplow_t *lower = ctype_tolower_table + 128;
    __ctype_touplow_t *upper = ctype_toupper_table + 128;

    for (i = -128; i < 256; i++) {
        b[i] = 0;
        lower[i] = (__ctype_touplow_t)i;
        upper[i] = (__ctype_touplow_t)i;

        if (i >= 0 && i < 128) {
            /*
             * uclibc _ISbit(n) = (1 << n):
             *   _ISupper=1, _ISlower=2, _ISalpha=4, _ISdigit=8,
             *   _ISxdigit=16, _ISspace=32, _ISprint=64, _ISgraph=128,
             *   _ISblank=256, _IScntrl=512, _ISpunct=1024, _ISalnum=2048
             */
            if (i >= 'A' && i <= 'Z') {
                b[i] |= 1;    /* _ISupper */
                b[i] |= 4;    /* _ISalpha */
                b[i] |= 2048; /* _ISalnum */
                b[i] |= 64;   /* _ISprint */
                b[i] |= 128;  /* _ISgraph */
                lower[i] = (__ctype_touplow_t)(i + 32);
            }
            if (i >= 'a' && i <= 'z') {
                b[i] |= 2;    /* _ISlower */
                b[i] |= 4;    /* _ISalpha */
                b[i] |= 2048; /* _ISalnum */
                b[i] |= 64;   /* _ISprint */
                b[i] |= 128;  /* _ISgraph */
                upper[i] = (__ctype_touplow_t)(i - 32);
            }
            if (i >= '0' && i <= '9') {
                b[i] |= 8;    /* _ISdigit */
                b[i] |= 16;   /* _ISxdigit */
                b[i] |= 2048; /* _ISalnum */
                b[i] |= 64;   /* _ISprint */
                b[i] |= 128;  /* _ISgraph */
            }
            if ((i >= 'A' && i <= 'F') || (i >= 'a' && i <= 'f'))
                b[i] |= 16;   /* _ISxdigit */
            if (i == ' ' || i == '\t' || i == '\n' || i == '\r' || i == '\f' || i == '\v')
                b[i] |= 32;   /* _ISspace */
            if (i == ' ' || i == '\t')
                b[i] |= 256;  /* _ISblank */
            if (i >= 0x20 && i <= 0x7e)
                b[i] |= 64;   /* _ISprint */
            if (i >= 0x21 && i <= 0x7e)
                b[i] |= 128;  /* _ISgraph */
            if (i < 0x20 || i == 0x7f)
                b[i] |= 512;  /* _IScntrl */
            if ((i >= 0x21 && i <= 0x2f) || (i >= 0x3a && i <= 0x40) ||
                (i >= 0x5b && i <= 0x60) || (i >= 0x7b && i <= 0x7e))
                b[i] |= 1024; /* _ISpunct */
        }
    }

    /* Set old-style direct pointers after tables are populated */
    __ctype_b = ctype_b_table + 128;
    __ctype_tolower = ctype_tolower_table + 128;
    __ctype_toupper = ctype_toupper_table + 128;
}

const unsigned short **__ctype_b_loc(void) {
    static const unsigned short *ptr = ctype_b_table + 128;
    return (const unsigned short **)&ptr;
}

const __ctype_touplow_t **__ctype_tolower_loc(void) {
    static const __ctype_touplow_t *ptr = ctype_tolower_table + 128;
    return (const __ctype_touplow_t **)&ptr;
}

const __ctype_touplow_t **__ctype_toupper_loc(void) {
    static const __ctype_touplow_t *ptr = ctype_toupper_table + 128;
    return (const __ctype_touplow_t **)&ptr;
}
