#!/usr/bin/env bash
#
# Repack a built recovery ramdisk into the stock vendor_boot container.
#
# Use this when the "vendorbootimage" build target produces something the
# bootloader refuses, or when you want a byte-for-byte identical container
# layout to the stock image (same header, same page size, same dtb).
#
# Requires: mkbootimg, unpack_bootimg, avbtool, lz4, file
#
# usage:
#   tools/repack_vendor_boot.sh <stock_vendor_boot.img> <recovery.img|ramdisk> <output.img> [dtb.img]
#
set -euo pipefail

STOCK="${1:?usage: repack_vendor_boot.sh <stock_vendor_boot.img> <recovery.img|ramdisk> <output.img> [dtb.img]}"
BUILT="${2:?missing built recovery image or ramdisk}"
OUT="${3:?missing output path}"
DTB="${4:-device/infinix/X6532C/prebuilt/dtb.img}"

PARTITION_SIZE=67108864
CMDLINE="bootopt=64S3,32N2,64N2"

for bin in mkbootimg unpack_bootimg avbtool lz4 file; do
    command -v "$bin" >/dev/null || { echo "missing tool: $bin"; exit 1; }
done
[ -f "$STOCK" ] || { echo "stock image not found: $STOCK"; exit 1; }
[ -f "$DTB" ] || { echo "dtb not found: $DTB"; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# Locate the recovery ramdisk inside the built image, if it is a boot image.
if [ "$(head -c 8 "$BUILT" 2>/dev/null)" = "ANDROID!" ]; then
    echo "-- extracting ramdisk from $BUILT"
    unpack_bootimg --boot_img "$BUILT" --out "$WORK/boot" >/dev/null
    RAMDISK="$WORK/boot/ramdisk"
else
    RAMDISK="$BUILT"
fi

# Stock ramdisks on this device are LZ4 legacy frames; keep that format.
if file -b "$RAMDISK" | grep -qi lz4; then
    cp "$RAMDISK" "$WORK/ramdisk.lz4"
else
    echo "-- compressing ramdisk to legacy lz4"
    lz4 -l -12 -c "$RAMDISK" > "$WORK/ramdisk.lz4"
fi

echo "-- building vendor_boot (header v4)"
mkbootimg \
    --header_version 4 \
    --vendor_boot \
    --vendor_ramdisk "$WORK/ramdisk.lz4" \
    --dtb "$DTB" \
    --vendor_cmdline "$CMDLINE" \
    --pagesize 4096 \
    --base 0x40078000 \
    --kernel_offset 0x00008000 \
    --ramdisk_offset 0x11a88000 \
    --tags_offset 0x07808000 \
    --dtb_offset 0x07808000 \
    --board "" \
    -o "$WORK/vendor_boot.img"

# The stock vendor_boot carries an unsigned hash footer (Algorithm NONE),
# and vbmeta_b has flags=3, so verification is disabled. Match that exactly.
echo "-- adding unsigned AVB hash footer"
avbtool add_hash_footer \
    --image "$WORK/vendor_boot.img" \
    --partition_name vendor_boot \
    --partition_size "$PARTITION_SIZE" \
    --algorithm NONE

cp "$WORK/vendor_boot.img" "$OUT"

echo
echo "output : $OUT ($(stat -c%s "$OUT") bytes)"
echo "sha256 : $(sha256sum "$OUT" | cut -d' ' -f1)"
echo
echo "flash  : fastboot flash vendor_boot $OUT"
