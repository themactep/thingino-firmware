#!/bin/bash
# Run the QEMU test harness for a thingino test profile.
#
# Usage: run.sh <profile> [extra harness args...]
#   run.sh qemu_t31x                  # wifi portal flow (slirp)
#   run.sh qemu_t31x_eth              # ethernet + full network lab (tap)
#   run.sh qemu_t31x_ethwifi          # dual + full network lab (tap)
#   run.sh qemu_t31x_eth --net slirp  # override backend
#
# Derives SoC and mode from the profile name, locates the newest built
# image and the buildroot host QEMU, and re-execs under sudo for tap mode.

set -e

PROFILE="${1:?Usage: $0 <profile> [harness args...]}"
shift

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# qemu_t31x -> soc=t31x mode=wifi; qemu_t31x_eth -> eth; qemu_t31x_ethwifi -> ethwifi
BASE="${PROFILE#qemu_}"
SOC="${BASE%%_*}"
SUFFIX="${BASE#"$SOC"}"
SUFFIX="${SUFFIX#_}"
case "$SUFFIX" in
	# XBurst2 qemu profiles ship the wired stack too (BR2_ETHERNET +
	# always-on kernel mac): the wired-gateway takeover is their correct
	# end state, so the bare profile name means ethwifi there.
	"")       case "$SOC" in
			t40*|t41*) MODE=ethwifi ;;
			*)         MODE=wifi ;;
		  esac ;;
	eth)      MODE=eth ;;
	ethwifi)  MODE=ethwifi ;;
	*)        echo "Cannot derive mode from profile suffix '$SUFFIX'" >&2; exit 1 ;;
esac

# Newest built image for this profile
IMAGE=$(find "$REPO_ROOT"/output -path "*/$PROFILE-*/images/thingino-$PROFILE.bin" -printf '%T@ %p\n' 2>/dev/null | sort -rn | head -1 | cut -d' ' -f2-)
if [ -z "$IMAGE" ]; then
	echo "No built image found for $PROFILE (looked in output/*/$PROFILE-*/images/)" >&2
	echo "Build it with: make GROUP=testing CAMERA=$PROFILE" >&2
	exit 1
fi

# Host QEMU from the same buildroot output, unless overridden
if [ -z "$QEMU_BIN" ]; then
	OUT_DIR=$(dirname "$(dirname "$IMAGE")")
	if [ -x "$OUT_DIR/host/bin/qemu-system-mipsel" ]; then
		export QEMU_BIN="$OUT_DIR/host/bin/qemu-system-mipsel"
	fi
fi

# Default flags per mode (extra args can extend/override)
case "$MODE" in
	wifi)        DEFAULTS="--host-tests --playwright --reboot-test" ;;
	eth|ethwifi) DEFAULTS="--net tap --playwright --reboot-test" ;;
esac

ARGS=("--image" "$IMAGE" "--soc" "$SOC" "--mode" "$MODE" "--profile" "$PROFILE")
# shellcheck disable=SC2086
set -- $DEFAULTS "$@"

# Effective backend = last --net on the command line (defaults first)
NET=slirp
prev=
for a in "$@"; do
	[ "$prev" = "--net" ] && NET="$a"
	prev="$a"
done

# npx must stay findable across sudo's secure_path
NPX_BIN="$(command -v npx || true)"
export NPX_BIN

echo "Profile: $PROFILE  SoC: $SOC  Mode: $MODE"
echo "Image:   $IMAGE"
echo "QEMU:    ${QEMU_BIN:-<search>}"

if [ "$NET" = tap ] && [ "$(id -u)" != 0 ]; then
	exec sudo -E python3 "$SCRIPT_DIR/harness.py" "${ARGS[@]}" "$@"
fi
exec python3 "$SCRIPT_DIR/harness.py" "${ARGS[@]}" "$@"
