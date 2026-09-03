#!/bin/bash
# Run the QEMU test harness for a thingino test profile.
#
# Usage: run.sh <profile> [extra harness args...]
#   run.sh qemu_t31x                  # wifi-only camera (slirp)
#   run.sh qemu_t31x_eth              # wired camera, full network lab (tap)
#   run.sh qemu_t31x_ethwifi          # both, full network lab (tap)
#   run.sh qemu_t31x_eth --net slirp  # override the backend
#
# The profile's configs/cameras-testing/<profile>/qemu-test.json says what
# it is; the driver picks the newest built image and the QEMU built beside
# it, applies the backend's default flags, and re-execs itself under sudo
# and into a private network namespace when the run needs a tap device.

set -e

PROFILE="${1:?Usage: $0 <profile> [harness args...]}"
shift
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
exec python3 "$SCRIPT_DIR/harness.py" --profile "$PROFILE" "$@"
