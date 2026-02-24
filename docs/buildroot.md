Buildroot
=========

### Macro assignment

Use the `:=` assignment instead of `=`.

`:=` assignment causes the right hand side to be expanded immediately,
and stored in the left hand variable.

With `=` assignment every single occurrence of its macro will be
expanding the `$(...)` syntax and thus invoking the shell command.

```
FILES := $(shell ...)
# expand now; FILES is now the result of $(shell ...)

FILES = $(shell ...)
# expand later: FILES holds the syntax $(shell ...)
```

### Override workflow basics

Thingino relies on Buildroot's `BR2_EXTERNAL` hook plus a single
`BR2_PACKAGE_OVERRIDE_FILE` entry point to keep package tweaks together.

* Every override lives under `package/thingino-<pkg>/<pkg>-override.mk` so the
	layout mirrors upstream Buildroot packages.
* The aggregator at `package/thingino-overrides.mk` is the only file referenced
	by `BR2_PACKAGE_OVERRIDE_FILE`. Add new overrides to that file (alphabetical)
	and they will be pulled in automatically when the associated package is
	enabled.
* Keep overrides idempotent. Guard them with the relevant kconfig symbol (for
	example `ifeq ($(BR2_PACKAGE_THINGINO_MOSQUITTO),y)`) so Buildroot does not
	evaluate them unnecessarily.
* Favor `override` assignments inside these files (`override FOO := ...`) so
	we unambiguously replace the upstream value after Buildroot sets it.

### Creating a new override package

1. Create the directory `package/thingino-<pkg>/` and add a file named
	 `<pkg>-override.mk`.
2. Wrap the contents in the package symbol guard to avoid side effects when the
	 package is disabled.
3. Override the upstream variables you need (`<PKG>_VERSION`, `<PKG>_SITE`,
	 `<PKG>_DEPENDENCIES`, `<PKG>_MAKE_OPTS`, etc.). Use `filter-out`/`+=` to
	 surgically adjust lists rather than rewriting them from scratch.
4. When you need to run custom install commands or skip upstream steps, redefine
	 the Buildroot hooks such as `define <PKG>_INSTALL_TARGET_CMDS`.
5. Add an `include $(BR2_EXTERNAL)/package/thingino-<pkg>/<pkg>-override.mk`
	 line to `package/thingino-overrides.mk` (keep the block alphabetical).
6. Rebuild the package with `make <pkg>-dirclean && make <pkg>` or use the
	 Thingino helper target (for cameras, `CAMERA=<model> make rebuild-<pkg>`).

Example skeleton:

```
ifeq ($(BR2_PACKAGE_THINGINO_FOO),y)

override FOO_VERSION = 1.2.3
override FOO_DEPENDENCIES += bar

override define FOO_INSTALL_TARGET_CMDS
	$(MAKE) -C $(@D) ... DESTDIR=$(TARGET_DIR) install
endef

endif # BR2_PACKAGE_THINGINO_FOO
```

### Patch placement and naming

Buildroot scans multiple patch locations in order. Thingino keeps custom
patches in `package/all-patches/<pkg>/<version>/` so the same tarball can be
reused across different override use cases.

* Number patches with a zero-padded prefix (`0001-`, `0002-`, ...). The prefix
	defines application order and keeps diffs readable.
* Use short, descriptive, kebab-case names after the number
	(`0001-sync-with-thingino-overrides.patch`). Keep the subject line in the
	patch itself identical to the file name for easier debugging.
* The `<version>` directory must match the tarball version in the associated
	package recipe. If you bump the version, copy or regenerate the patches under
	a new directory so old builds stay reproducible.
* Buildroot applies upstream package patches first, then everything pointed to
	by `BR2_GLOBAL_PATCH_DIR`. Thingino sets `BR2_GLOBAL_PATCH_DIR` to
	`package/all-patches`, so any new patch you drop there will be applied after
	the official patches but before the package is built.
* Generate patches with `git format-patch` (preferred) or `git diff
	--no-index`. When using the latter, compare against `/dev/null` for entirely
	new files so the patch contains the correct `new file mode` metadata.

### Common pitfalls

* **Missing files in tarball**: If you add new source files in a patch, double
	check that the filenames match the includes in the upstream sources. Missing
	headers will halt the build after the patch phase, which is harder to debug.
* **Duplicate patch application**: Do not point `MOSQUITTO_PATCHES` (or similar)
	at your custom patches when `BR2_GLOBAL_PATCH_DIR` already provides them; the
	Buildroot patch loop would apply them twice and fail on the second attempt.
* **Silent rebuilds**: Remember the patch directory is cached. Run `make
	<pkg>-dirclean` after editing an override or patch so Buildroot re-extracts
	the package and re-applies your changes.
* **Config drift**: If you need package-specific configuration symbols, add
	them to `Config.in` under `package/thingino-<pkg>/` and select them from your
	camera `defconfig` just like any other Buildroot option.
