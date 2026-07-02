Symbol interposition crashes in libuclibcshim.so
===============================================

**Last updated:** 2026-07-02

## Summary of changes

| File | Action |
|------|--------|
| `package/ingenic-uclibc/0001-remove-redundant-shim-definitions.patch` | **New** accumulated patch removing all 6 redundant functions in one step. |
| `package/ingenic-uclibc/0001-fix-open64-….patch` | **Deleted** — `#undef` workaround superseded. |
| `package/ingenic-uclibc/0002-fix-fgetc-….patch` | **Deleted** — partial fix superseded. |
| `package/ingenic-uclibc/crash-fgetc-fputc-interposition.md` | **Updated** to document the full fix. |
| `overrides/ingenic-uclibc/uclibc_shim.c` | **Optional** local override for dev iteration. |
| `local.mk` | **Optional** `INGENIC_UCLIBC_OVERRIDE_SRCDIR` for dev iteration. |

**Functions removed from the shim** (all provided by uClibc-ng):
`__fgetc_unlocked`, `__fputc_unlocked`, `fopen64`, `open64`, `fseeko64`, `mmap64`.

**Functions kept:** `mmap` (off>>12 workaround), `__assert`, `__pthread_*`
stubs, ctype compat.

## Symptoms

`prudynt` crashes with SIGSEGV in `libuclibcshim.so` at various offsets,
all with the same pattern: stack guard page fault (address ending in
`0xfe0`/`0xfe8`), epc and ra inside the shim.

Example (__fgetc_unlocked/__fputc_unlocked interposition):
```
[    8.623642] do_page_fault() #2: sending SIGSEGV to prudynt for invalid write access to
[    8.623642] 7f14efe0
[    8.623664] epc = 77b15bc8 in libuclibcshim.so[77b15000+1000]
[    8.623692] ra  = 77b15c00 in libuclibcshim.so[77b15000+1000]
```

Example (open64/fopen64/fseeko64 interposition):
```
[   10.537123] do_page_fault() #2: sending SIGSEGV to prudynt for invalid write access to
[   10.537123] 7f784fe8
[   10.537137] epc = 76ef1c24 in libuclibcshim.so[76ef1000+1000]
[   10.537157] ra  = 76ef1c5c in libuclibcshim.so[76ef1000+1000]
```

Key indicators:

- **Fault address ending in `0xfe0`/`0xfe8`** — inside the stack guard page,
  consistent with stack exhaustion from recursion.
- **`epc` and `ra` both in the shim** — the crash is inside a shim function
  that is calling itself recursively.
- **`ra - epc` ≈ 0x38** — the return address is 56 bytes ahead, consistent
  with a function calling itself.

## Root cause

The shim defines multiple functions that are **already provided by uClibc-ng**:

| Shim function    | uClibc-ng provides | Interposition problem |
|-----------------|--------------------|------------------------|
| `__fgetc_unlocked` | ✓ `00048f70 g`   | shim → fgetc → uclibc's __fgetc_unlocked (interposed!) |
| `__fputc_unlocked` | ✓ `00049210 g`   | shim → fputc → uclibc's __fputc_unlocked (interposed!) |
| `fopen64`       | ✓ `0003fb80 g`     | shim → fopen → uclibc's fopen64 (interposed!) |
| `open64`        | ✓ `000167f0 g`     | shim → open → uclibc's open64 (interposed!) |
| `fseeko64`      | ✓ `0003fe80 g`     | shim → fseeko → uclibc's fseeko64 (interposed!) |
| `mmap64`        | ✓ `00016740 g`     | present but redundant |

Because uClibc-ng is built with `-D_FILE_OFFSET_BITS=64` (__USE_FILE_OFFSET64
always defined), all code compiled against it calls the `*64` variants.
The shim exports strong symbols with the same names, **interposing** on
uClibc-ng's real implementations.

For `__fgetc_unlocked`/`__fputc_unlocked`:
```
shim's __fgetc_unlocked → uclibc's fgetc → uclibc's __fgetc_unlocked (interposed!)
                                                      ↓
                            shim's __fgetc_unlocked ←──┘
```

For `fopen64`/`open64`/`fseeko64`, the same interposition cycle occurs
because uclibc-ng's internal implementations branch to the `*64` variants
through PLT entries that the shim shadows.

Note: the `#undef` approach (former patch 0001) only prevents **compile-time**
macro expansion (`fopen` → `fopen64`).  It cannot fix **runtime** symbol
interposition through the dynamic linker's PLT/GOT mechanism.

## Fix

Remove **all six** redundant shim definitions.  uClibc-ng provides each
of them natively.  The only shim functions that remain are:

- `mmap()` — has a required `off>>12` workaround for an Ingenic MMU bug
- `__assert()` — not provided by uClibc-ng
- `__pthread_register_cancel()` / `__pthread_unregister_cancel()` — stubs
- ctype-compat functions (`__ctype_b_loc`, etc.) — glibc compat layer

Removed:
- `__fgetc_unlocked()` — uclibc-ng exports `00048f70 g`
- `__fputc_unlocked()` — uclibc-ng exports `00049210 g`
- `fopen64()` — uclibc-ng exports `0003fb80 g`
- `open64()` — uclibc-ng exports `000167f0 g`
- `fseeko64()` — uclibc-ng exports `0003fe80 g`
- `mmap64()` — uclibc-ng exports `00016740 g`

This is implemented in a single accumulated patch:

    package/ingenic-uclibc/0001-remove-redundant-shim-definitions.patch

This replaces the previous two-patch approach (0001 #undef + 0002 partial
removal).

## Rebuild

```bash
CAMERA=<your-camera> make rebuild-ingenic-uclibc
# or just:
CAMERA=<your-camera> make fast
```
