#!/bin/sh
# Fail safe on the OSS3 inner-codec speaker-amp default.
#
# The Ingenic OSS3 codecs (t32's audio stack) default spk_gpio to the ISVP
# reference board's enable pin: GPIO_PB(31) (gpio 63) in the PRJ007/PRJ008 inner
# codecs, GPIO_PC(4) or GPIO_PB(31) in the es8389 external codec. thingino
# always passes spk_gpio= on the module command line, so that default is only
# hit when the parameter goes missing - and then the codec would claim and drive
# a pin that on another board is a motor phase, an LED, or a sensor reset.
# Disable instead: -1 makes incodec_spk_gpio_request() and the enable/disable
# paths no-ops, the correct behaviour for a board with no configured amp.
#
# Runs as a POST_PATCH hook on every kernel. A tree without the OSS3 sources
# (every non-t32 branch, and 3.10) is left untouched - which is why it is a hook
# and not a package/all-patches/linux/4.4.94/ patch: that directory is shared by
# branches that do not carry sound/oss3, so a patch naming those files would
# fail to apply there.
#
# Usage: fix_kernel_spk_gpio_default.sh <linux-dir>
set -eu

LINUX="${1:-}"
[ -n "$LINUX" ] || exit 0

for rel in \
	sound/oss3/inner_codecs/PRJ007/codec.c \
	sound/oss3/inner_codecs/PRJ008/codec.c \
	sound/oss3/ex_codecs/es8389_codec.c; do
	file="$LINUX/$rel"
	[ -f "$file" ] || continue
	grep -Eq '^static int spk_gpio =[[:space:]]*GPIO_P[A-Z]' "$file" || continue
	sed -i -E 's/^(static int spk_gpio =[[:space:]]*)GPIO_P[A-Z]\([0-9]+\);/\1-1;/' "$file"
	echo "thingino: disabled the spk_gpio default in $rel"
done
