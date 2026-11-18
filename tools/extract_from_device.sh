#!/usr/bin/env bash
#
# Regenerate the device-specific files in this tree from a stock dump.
# Every file under device/infinix/X6532C that is not hand written comes
# from the phone itself, so the tree can be rebuilt from any dump of the
# same firmware.
#
# usage: tools/extract_from_device.sh <vendor_boot.img> [dtb_from_boot.img]
#
set -euo pipefail

VENDOR_BOOT="${1:?usage: extract_from_device.sh <vendor_boot.img> [dtb.img]}"
DTB_SRC="${2:-}"
TREE="device/infinix/X6532C"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

for bin in unpack_bootimg lz4 cpio file; do
    command -v "$bin" >/dev/null || { echo "missing tool: $bin"; exit 1; }
done

echo "-- unpacking $VENDOR_BOOT"
unpack_bootimg --boot_img "$VENDOR_BOOT" --out "$WORK/vb" >/dev/null

RADISK="$WORK/vb/vendor_ramdisk00"
rd="$WORK/ramdisk.cpio"
case "$(file -b "$RADISK")" in
    *LZ4*) lz4 -dc "$RADISK" > "$rd" ;;
    *gzip*) gzip -dc "$RADISK" > "$rd" ;;
    *) cp "$RADISK" "$rd" ;;
esac

mkdir -p "$WORK/root"
(cd "$WORK/root" && cpio -idm --no-absolute-filenames < "$rd" 2>/dev/null)

echo "-- installing kernel modules ($(ls "$WORK/root/lib/modules"/*.ko | wc -l) files)"
rm -rf "$TREE/recovery/root/lib/modules"
mkdir -p "$TREE/recovery/root/lib/modules"
cp -a "$WORK/root/lib/modules/." "$TREE/recovery/root/lib/modules/"

echo "-- installing init/recovery files"
cp "$WORK/root/init.recovery.mt6765.rc" "$TREE/recovery/root/init.recovery.mt6765.rc"
mkdir -p "$TREE/recovery/root/first_stage_ramdisk" "$TREE/recovery/root/system/bin" "$TREE/recovery/root/system/etc/init"
cp "$WORK/root/first_stage_ramdisk/fstab.mt6765" "$TREE/recovery/root/first_stage_ramdisk/fstab.mt6765"
cp "$WORK/root/system/bin/mtk_plpath_utils" "$TREE/recovery/root/system/bin/mtk_plpath_utils"
cp "$WORK/root/system/etc/ueventd.rc" "$TREE/recovery/root/system/etc/ueventd.rc"
cp "$WORK/root/system/etc/cgroups.json" "$TREE/recovery/root/system/etc/cgroups.json"
cp "$WORK/root/system/etc/init/mtk-plpath-utils.rc" "$TREE/recovery/root/system/etc/init/mtk-plpath-utils.rc" 2>/dev/null || true
chmod 755 "$TREE/recovery/root/system/bin/mtk_plpath_utils"

echo "-- installing dtb"
mkdir -p "$TREE/prebuilt"
if [ -n "$DTB_SRC" ] && [ -f "$DTB_SRC" ]; then
    cp "$DTB_SRC" "$TREE/prebuilt/dtb.img"
else
    cp "$WORK/vb/dtb" "$TREE/prebuilt/dtb.img"
fi

echo
echo "done. verify with:"
echo "  sha256sum $TREE/prebuilt/dtb.img $TREE/recovery/root/init.recovery.mt6765.rc"
echo "  ls $TREE/recovery/root/lib/modules/*.ko | wc -l"
