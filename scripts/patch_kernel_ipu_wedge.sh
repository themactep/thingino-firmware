#!/bin/sh
# Apply the T20-family IPU wedge mitigation to the kernel source tree.
#
# Why this exists instead of a plain buildroot patch: the 3.10.14 kernels
# are fetched with BR2_LINUX_KERNEL_CUSTOM_GIT and a KERNEL_HASH that is
# resolved dynamically from the branch tip (git ls-remote in thingino.mk),
# so LINUX_VERSION is a moving git hash.  Buildroot only auto-applies
# BR2_GLOBAL_PATCH_DIR patches from linux/<VERSION>/, which can never
# match a moving hash - the patches in package/all-patches/linux/3.10.14/
# are NOT applied to these builds (verify: .applied_patches_list in the
# kernel build dir is empty).  The THINGINO_KOPT_PREPARE_KERNEL hook is
# the mechanism that actually modifies the fetched tree (it already
# rewrites board_base.c for LEDs), so this script rides the same hook.
#
# Guard logic:
#   - driver file absent               -> not this SoC family, skip quietly
#   - mitigation marker already there  -> already applied, skip quietly
#   - recognizable 3.10 driver         -> apply; a failed apply FAILS THE
#     BUILD loudly, because that means the upstream branch tip drifted and
#     the patch needs a rebase (silently losing a stability fix is worse)
#   - file present but unrecognized    -> different driver generation
#     (e.g. a 4.4.94 branch); warn and skip, mitigation not applicable as-is

set -eu

if [ "$#" -ne 2 ]; then
	echo "usage: patch_kernel_ipu_wedge.sh <linux_dir> <patch_file>" >&2
	exit 1
fi

LINUX_DIR="$1"
PATCH_FILE="$2"
DRIVER="$LINUX_DIR/drivers/video/jz_ipu/jz_ipu_v13.c"

if [ ! -f "$DRIVER" ]; then
	exit 0
fi

if grep -q "IPU_DONE_TIMEOUT_MS" "$DRIVER"; then
	exit 0
fi

if ! grep -q "msecs_to_jiffies(2000)" "$DRIVER"; then
	echo "WARNING: $DRIVER exists but is not the known 3.10 jz_ipu_v13 driver;" >&2
	echo "WARNING: skipping IPU wedge mitigation ($PATCH_FILE)" >&2
	exit 0
fi

if ! patch -p1 -N --no-backup-if-mismatch -d "$LINUX_DIR" <"$PATCH_FILE"; then
	echo "ERROR: IPU wedge mitigation failed to apply to $DRIVER" >&2
	echo "ERROR: the thingino-linux branch tip likely drifted; rebase $PATCH_FILE" >&2
	exit 1
fi
