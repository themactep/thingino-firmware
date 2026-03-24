Toolchains
==========

This guide explains how Thingino selects a toolchain configuration and how to switch between available toolchain variants.

Overview
--------

Thingino builds select a toolchain fragment from three Kconfig dimensions:

1. Toolchain type
2. GCC major version
3. C library (libc)

The selected combination is converted into a fragment filename under:

`configs/fragments/toolchain/`

Format:

`<type>-gcc<version>-<libc>.fragment`

Where:

- `type` is one of `br`, `ext`, `loc`
- `version` is `13`, `14`, or `15`
- `libc` is lowercase `glibc`, `musl`, or `uclibc`

Examples:

- `ext-gcc15-musl.fragment`
- `br-gcc14-uclibc.fragment`
- `loc-gcc15-musl.fragment`

Kconfig Menu
------------

In menuconfig, open the Toolchain submenu and pick one value in each group:

- Thingino toolchain type: Buildroot, External, or Local
- Thingino GCC version: GCC 13/14/15
- Thingino toolchain libc: glibc/musl/uClibc

Run:

```bash
CAMERA=<camera_defconfig> make menuconfig
```

Then save:

```bash
CAMERA=<camera_defconfig> make saveconfig
```

Defconfig Symbols
-----------------

The selected toolchain is stored in the camera defconfig using these symbols:

- `BR2_THINGINO_TOOLCHAIN_TYPE_BUILDROOT=y` or `BR2_THINGINO_TOOLCHAIN_TYPE_EXTERNAL=y` or `BR2_THINGINO_TOOLCHAIN_TYPE_LOCAL=y`
- `BR2_THINGINO_TOOLCHAIN_GCC_13=y` or `BR2_THINGINO_TOOLCHAIN_GCC_14=y` or `BR2_THINGINO_TOOLCHAIN_GCC_15=y`
- `BR2_THINGINO_TOOLCHAIN_LIBC_GLIBC=y` or `BR2_THINGINO_TOOLCHAIN_LIBC_MUSL=y` or `BR2_THINGINO_TOOLCHAIN_LIBC_UCLIBC=y`

Current default profile used by camera defconfigs is typically:

```text
BR2_THINGINO_TOOLCHAIN_TYPE_EXTERNAL=y
BR2_THINGINO_TOOLCHAIN_GCC_15=y
BR2_THINGINO_TOOLCHAIN_LIBC_MUSL=y
```

Fallback Defaults
-----------------

If a defconfig does not explicitly set one of the three dimensions, Thingino falls back to:

- Type: `EXTERNAL`
- GCC: `15`
- libc: `MUSL`

This maps to:

`configs/fragments/toolchain/ext-gcc15-musl.fragment`

Important Notes
---------------

- Toolchain selection is independent from the `# FRAG:` header list in camera defconfigs.
- The selected fragment file must exist in `configs/fragments/toolchain/`.
- The selected libc also affects the output directory suffix (for example `-musl`, `-glibc`, or `-uclibc`).

Available Fragments
-------------------

At the time of writing, the repository contains:

- `br-gcc14-glibc.fragment`
- `br-gcc14-musl.fragment`
- `br-gcc14-uclibc.fragment`
- `br-gcc15-glibc.fragment`
- `br-gcc15-musl.fragment`
- `br-gcc15-uclibc.fragment`
- `ext-gcc13-glibc.fragment`
- `ext-gcc13-musl.fragment`
- `ext-gcc14-glibc.fragment`
- `ext-gcc14-musl.fragment`
- `ext-gcc14-uclibc.fragment`
- `ext-gcc15-glibc.fragment`
- `ext-gcc15-musl.fragment`
- `ext-gcc15-uclibc.fragment`
- `loc-gcc14-uclibc.fragment`
- `loc-gcc15-musl.fragment`

If you need a new combination, add the corresponding fragment file under `configs/fragments/toolchain/`.

Quick Examples
--------------

Use external GCC 15 with musl:

```text
BR2_THINGINO_TOOLCHAIN_TYPE_EXTERNAL=y
BR2_THINGINO_TOOLCHAIN_GCC_15=y
BR2_THINGINO_TOOLCHAIN_LIBC_MUSL=y
```

Use Buildroot GCC 14 with uClibc:

```text
BR2_THINGINO_TOOLCHAIN_TYPE_BUILDROOT=y
BR2_THINGINO_TOOLCHAIN_GCC_14=y
BR2_THINGINO_TOOLCHAIN_LIBC_UCLIBC=y
```

Use local GCC 15 with musl:

```text
BR2_THINGINO_TOOLCHAIN_TYPE_LOCAL=y
BR2_THINGINO_TOOLCHAIN_GCC_15=y
BR2_THINGINO_TOOLCHAIN_LIBC_MUSL=y
```
