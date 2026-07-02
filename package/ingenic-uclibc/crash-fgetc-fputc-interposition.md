__fgetc_unlocked / __fputc_unlocked interposition recursion in libuclibcshim.so
=================================================================================

**Last updated:** 2026-07-02

## Symptoms

After fixing the `open64`/`fopen64`/`fseeko64` macro recursion (patch 0001),
`prudynt` still crashes with SIGSEGV in `libuclibcshim.so`:

```
[    8.623642] do_page_fault() #2: sending SIGSEGV to prudynt for invalid write access to
[    8.623642] 7f14efe0
[    8.623664] epc = 77b15bc8 in libuclibcshim.so[77b15000+1000]
[    8.623692] ra  = 77b15c00 in libuclibcshim.so[77b15000+1000]
```

Key indicators:

- **Fault address `0x7f14efe0`** — inside the stack guard page (4 KB guard below
  the valid stack region), consistent with stack exhaustion from recursion.
- **`epc = libuclibcshim.so + 0xbc8`** — inside `__fputc_unlocked`, writing to
  the stack (`sw gp,16(sp)` in the function prologue on a recursive call).
- **`ra = libuclibcshim.so + 0xc00`** — return address pointing back into the
  call chain.

## Root cause

This is a **runtime symbol interposition** problem, not a preprocessor macro
bug. The shim defines `__fgetc_unlocked` and `__fputc_unlocked` with strong
symbols to satisfy Ingenic libimp dependencies. These functions call `fgetc()`
and `fputc()` expecting to delegate to uClibc-ng.

However, uClibc-ng's own `fgetc()` and `fputc()` implementations internally
**branch to** `__fgetc_unlocked` / `__fputc_unlocked`.  Verified in the
disassembly of uClibc-ng 1.0.57:

```asm
; fgetc buffer-empty slow path at 0x479f0:
    lw   t9,-32192(gp)
    b    48f70 <__fgetc_unlocked>
```

Because the shim exports `__fgetc_unlocked` as a strong symbol, it **interposes**
(shadows) uClibc-ng's own implementation.  The result is an interposition cycle:

```
shim's __fgetc_unlocked → uclibc's fgetc → uclibc's __fgetc_unlocked (interposed!)
                                                      ↓
                            shim's __fgetc_unlocked ←──┘
```

Each iteration pushes a new stack frame.  The stack overflows and hits the
guard page, producing the SIGSEGV.

Note: uClibc-ng's `stdio.h` uses the parenthesised macro trick (`(fgetc)(…)`)
to prevent preprocessor re-expansion, so `#undef` directives (as used in patch
0001) cannot fix this.  The recursion happens through the dynamic linker's
symbol resolution, not the preprocessor.

## Affected functions

| Function | Offset | Calls (in source) | Actually reaches | Result |
|---|---|---|---|---|
| `__fgetc_unlocked` | `0x9ac` | `fgetc(stream)` | uclibc's `fgetc` → branches to shim's `__fgetc_unlocked` | 🔴 Stack overflow → **SIGSEGV** |
| `__fputc_unlocked` | `0xb00` | `fputc(c, stream)` | uclibc's `fputc` → branches to shim's `__fputc_unlocked` | 🔴 Stack overflow → **SIGSEGV** |

(The crash prologue instruction lands in `__fputc_unlocked`'s prologue at
offset `0xbc8` because the shim's `open64`/`fopen64`/`fseeko64` (now fixed
by patch 0001) call into stdio, which triggers the `__fputc_unlocked` cycle.)

## Fix

Use `dlsym(RTLD_NEXT, …)` to obtain uClibc-ng's original implementation
pointers on first call, bypassing the shim's interposed symbols entirely:

```c
int __fgetc_unlocked(FILE *stream) {
    static int (*real___fgetc_unlocked)(FILE *) = NULL;
    if (!real___fgetc_unlocked) {
        real___fgetc_unlocked = dlsym(RTLD_NEXT, "__fgetc_unlocked");
        if (!real___fgetc_unlocked) abort();
    }
    return real___fgetc_unlocked(stream);
}

int __fputc_unlocked(int c, FILE *stream) {
    static int (*real___fputc_unlocked)(int, FILE *) = NULL;
    if (!real___fputc_unlocked) {
        real___fputc_unlocked = dlsym(RTLD_NEXT, "__fputc_unlocked");
        if (!real___fputc_unlocked) abort();
    }
    return real___fputc_unlocked(c, stream);
}
```

`RTLD_NEXT` instructs the dynamic linker to skip the calling shared object
(libuclibcshim.so) and return the **next** definition of the symbol — which is
uClibc-ng's own `__fgetc_unlocked` / `__fputc_unlocked`.  The function pointer
is cached in a `static` variable, so `dlsym` is called at most once per
function (first use).

This is implemented in the patch:

    package/ingenic-uclibc/0002-fix-fgetc-fputc-unlocked-interposition.patch

## Rebuild

```bash
CAMERA=<your-camera> make rebuild-ingenic-uclibc
# or just:
CAMERA=<your-camera> make fast
```
