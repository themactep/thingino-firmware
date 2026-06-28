open64 / fopen64 / fseeko64 recursion in libuclibcshim.so
========================================================

**Last updated:** 2026-06-28

## Symptoms

`prudynt` crashes with SIGSEGV in `libuclibcshim.so`:

```
[    5.928306] do_page_fault() #2: sending SIGSEGV to prudynt for invalid write access to
[    5.928306] 7f08dff8
[    5.928323] epc = 77bc4bc8 in libuclibcshim.so[77bc4000+1000]
[    5.928344] ra  = 77bc4c00 in libuclibcshim.so[77bc4000+1000]
```

Key indicators:

- **Fault address ends in `0xff8`** — the last 8 bytes of a 4 KB page, i.e. the stack guard page.
- **`epc = libuclibcshim.so + 0xbc8`** — `sw gp,16(sp)` in `open64`, a prologue instruction that writes to the stack.
- **`ra = libuclibcshim.so + 0xc00`** — return address pointing back into `open64`'s epilogue.

## Root cause

uClibc-ng's `features.h` **unconditionally** defines `__USE_FILE_OFFSET64` on
all targets (including MIPS):

```c
#undef  _FILE_OFFSET_BITS
#define _FILE_OFFSET_BITS    64
#define __USE_FILE_OFFSET64  1
```

This activates preprocessor redirects in `fcntl.h` and `stdio.h`:

```c
#ifndef __USE_FILE_OFFSET64
extern int open (...);
#else
# define open open64    /* every `open` token -> `open64` */
#endif
```

The shim source in `uclibc_shim.c` defines `open64()` and calls `open()` inside
its body.  The preprocessor expands `open()` to `open64()` — **infinite recursion**.

## Affected functions

| Function | Offset | Calls (in source) | Actually calls | Result |
|---|---|---|---|---|
| `open64` | `0xbb0` | `open(...)` | `bal 0xbb0` (self) | 🔴 Stack overflow → **SIGSEGV** |
| `fopen64` | `0xba8` | `fopen(...)` | `b 0xba8` (self) | 🔴 Infinite loop (band-aid) |
| `fseeko64` | `0xc08` | `fseeko(...)` | `b 0xc08` (self) | 🔴 Infinite loop (band-aid) |

The `fopen64` and `fseeko64` functions were deliberately turned into infinite
loops (`b .` in MIPS) to avoid crashing — someone hit this bug before and
applied a band-aid instead of fixing the root cause.

## Fix

Add `#undef` before each wrapper function so the macro is suppressed at the
point of the body:

```c
#undef fopen
FILE* fopen64(const char *path, const char *mode) { return fopen(path, mode); }

#undef open
int open64(const char *path, int flags, ...)     { return open(path, flags, mode); }

#undef fseeko
int fseeko64(FILE *stream, off_t offset, int whence) { return fseeko(stream, offset, whence); }
```

This is implemented in the patch:

    package/ingenic-uclibc/0001-fix-open64-fopen64-fseeko64-recursion.patch

## Rebuild

```bash
CAMERA=<your-camera> make rebuild-ingenic-uclibc
# or just:
CAMERA=<your-camera> make fast
```
