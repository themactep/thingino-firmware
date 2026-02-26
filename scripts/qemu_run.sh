#!/bin/bash
# Run a cross-compiled binary from the build target directory using QEMU user-mode emulation.
# Usage: qemu_run.sh <target_dir> <bin_path> [args...]
#   target_dir  path to the buildroot target/ sysroot
#   bin_path    absolute path to the binary within the sysroot (e.g. /bin/ffmpeg)
#   args        additional arguments passed to the binary

set -e

TARGET_DIR="${1:?Usage: $0 <target_dir> <bin_path> [args...]}"
BIN_PATH="${2:?Usage: $0 <target_dir> <bin_path> [args...]}"
shift 2

if [[ "$BIN_PATH" != /* ]]; then
	echo "Error: bin_path must be an absolute path (e.g. /bin/ffmpeg), got: $BIN_PATH" >&2
	exit 1
fi

FULL_BIN="${TARGET_DIR%/}/${BIN_PATH#/}"

if [ ! -f "$FULL_BIN" ]; then
	echo "Error: binary not found: $FULL_BIN" >&2
	exit 1
fi

# Resolve symlinks within the sysroot
while [ -L "$FULL_BIN" ]; do
	LINK_TARGET=$(readlink "$FULL_BIN")
	if [[ "$LINK_TARGET" == /* ]]; then
		FULL_BIN="${TARGET_DIR%/}/${LINK_TARGET#/}"
	else
		FULL_BIN="$(dirname "$FULL_BIN")/$LINK_TARGET"
	fi
	if [ ! -f "$FULL_BIN" ]; then
		echo "Error: symlink target not found: $FULL_BIN" >&2
		exit 1
	fi
done

# If the file is a shell script, resolve the interpreter from its shebang
if head -c 2 "$FULL_BIN" | grep -q '^#!'; then
	INTERP=$(head -1 "$FULL_BIN" | sed 's/^#![[:space:]]*//' | awk '{print $1}')
	if [[ "$INTERP" == /* ]]; then
		INTERP_FULL="${TARGET_DIR%/}/${INTERP#/}"
		if [ ! -f "$INTERP_FULL" ]; then
			echo "Error: interpreter not found in sysroot: $INTERP_FULL" >&2
			exit 1
		fi
		set -- "$FULL_BIN" "$@"
		FULL_BIN="$INTERP_FULL"
	fi
fi

QEMU=qemu-mipsel-static

if ! command -v "$QEMU" >/dev/null 2>&1; then
	echo "Error: $QEMU not found; install qemu-user-static" >&2
	exit 1
fi

exec "$QEMU" -L "$TARGET_DIR" "$FULL_BIN" "$@"
