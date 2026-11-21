# OrangeFox Recovery for the Infinix Smart 9 HD (X6532C)

OrangeFox Recovery device tree for the **Infinix Smart 9 HD / X6532C**, MediaTek
MT6765, Android 12 (Go), A/B + Virtual A/B.

> This is **not** for the Infinix Smart 9 (X6532) — that model is a Helio G81 /
> MT6769Z, with a different chipset and partition layout.

## Ready-made image

A build with FBE / metadata decryption (Trustonic TEE) is available in the
[`ofrp-12.1-crypto-v1` release](https://github.com/ryu4nn/ofrp_X6532C/releases/tag/ofrp-12.1-crypto-v1):

```
vendor_boot.img  67,108,864 bytes (exactly 64 MiB)
sha256 c2696090f36593fc784d0ab42957a63acbce691fc1b025f7991de59999000063
```

## Why recovery lives in `vendor_boot`

This phone has no `recovery` partition. The stock firmware keeps all recovery
resources in the **vendor ramdisk** inside the `vendor_boot` partition:

```
vendor_boot_a/b.img
├── vendor_ramdisk00   (lz4, 23.4 MB)  -> system/bin/recovery, recovery.fstab, init.recovery.mt6765.rc
├── dtb                (145,728 bytes)
└── AVB footer         (unsigned, Algorithm NONE)
```

The build therefore uses `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true`
and the `vendorbootimage` target, not `recoveryimage`. The kernel stays in the
`boot` partition and is **never touched**, so a Magisk Kitsune install in the
`boot` ramdisk remains intact.

## Tree contents

```
device/infinix/X6532C/
├── BoardConfig.mk            numbers from the dump: header v4, base/offset, partition sizes
├── device.mk                 Virtual A/B, dynamic partitions, fastbootd
├── twrp_X6532C.mk            twrp_X6532C product (lunch target)
├── AndroidProducts.mk
├── vendorsetup.sh
├── system.prop               getprop values from the device
├── prebuilt/dtb.img          from vendor_boot (sha256 5f2bd3de...)
└── recovery/root/
    ├── init.recovery.mt6765.rc      from the device's vendor_boot + imports init.decrypt.rc
    ├── init.decrypt.rc              starts the Trustonic TEE, keymaster, gatekeeper
    ├── first_stage_ramdisk/fstab.mt6765
    ├── lib/modules/*.ko            156 modules, vermagic 5.10.237 (from the device)
    ├── vendor/                     keymaster/gatekeeper services + libs + TA (32-bit)
    └── system/etc/{recovery.fstab,twrp.flags}
```

`vendor/` holds the original binaries and libraries from this device's `/vendor`
partition (Trustonic keymaster 4.1, gatekeeper 1.0, keymaster_attestation 1.1,
`mcDriverDaemon`, `libMcClient`, the Trustonic TA registry). TWRP only mounts the
real `/vendor` long enough to read props and unmounts it before decryption, so the
TEE stack has to ship in the ramdisk. `mcDrvModule.ko` and `gpapi.ko` are
`insmod`ed from `init.decrypt.rc` because TWRP's module loader runs after init.

`recovery.fstab` and `twrp.flags` are hand-written, derived from the stock fstab
but **corrected**:

| Wrong in public trees        | Correct on this device                    |
| ---------------------------- | ----------------------------------------- |
| `/metadata` -> `by-name/metadata` | `/metadata` -> `by-name/md_udc` (mmcblk0p10) |
| `/misc` -> `by-name/misc`    | `/misc` -> `by-name/para` (no `misc` partition) |
| `/tee1`, `/tee2`             | `tee_a`, `tee_b` (A/B)                    |
| super 9.126 GB               | super 5,368,709,120 bytes                 |
| kernel modules 5.10.209      | 5.10.237                                  |

Files taken from the device (`lib/modules`, `dtb.img`, init rc files, the
first-stage fstab, `mtk_plpath_utils`, `ueventd.rc`, `cgroups.json`) can be
regenerated with:

```bash
tools/extract_from_device.sh dump/vendor_boot_b.img
```

## Building with GitHub Actions

1. Create a new GitHub repository and push the contents of this folder (the
   `dump/` folder is already git-ignored, do not upload it — it holds 240 MB of
   personal device images):

   ```bash
   cd x6532-ofrp
   git init -b main
   git add .
   git commit -m "device tree X6532C + OrangeFox workflow"
   git remote add origin git@github.com:<username>/<repo>.git
   git push -u origin main
   ```

2. Open the **Actions** tab -> **Build OrangeFox for X6532C** -> **Run workflow**.
   - `fox_branch`: `12.1` (matches Android 12.1; do not pick 14.1 for this device)
   - FBE decryption is always enabled (`TW_INCLUDE_CRYPTO := true` in `BoardConfig.mk`).

3. Wait. The OrangeFox source sync is about 45 GB (30-60 minutes), the build
   takes 40-90 minutes. The results land in **Artifacts**: `vendor_boot.img`,
   `build-info.txt`, `SHA256SUMS`.

A stock GitHub runner has only ~30 GB free after cleanup, so if the sync fails on
disk space, build locally instead (see below).

## Local build (fallback)

```bash
export ALLOW_MISSING_DEPENDENCIES=true
export FOX_BUILD_DEVICE=X6532C
export FOX_AB_DEVICE=1
export FOX_VIRTUAL_AB_DEVICE=1
export LC_ALL=C
source build/envsetup.sh
lunch twrp_X6532C-eng
mka adbd vendorbootimage -j"$(nproc)"
```

The output is `out/target/product/X6532C/vendor_boot.img`.

If the bootloader rejects the built image, repack its ramdisk into the stock
container:

```bash
tools/repack_vendor_boot.sh dump/vendor_boot_b.img \
    out/target/product/X6532C/vendor_boot.img \
    vendor_boot_final.img
```

## Flashing

> Before flashing, make sure you have dumps of `boot_a`, `boot_b`,
> `vendor_boot_a`, `vendor_boot_b`, `vbmeta_a` and `vbmeta_b`. They are already
> in `dump/`.
>
> The active slot on this device is **b**. The image may only go to
> `vendor_boot_b`.
> Do not touch `boot`, `init_boot`, `preloader`, `seccfg`, `nvram`, `nvdata` or
> `persist`; Magisk Kitsune lives in `boot` and does not need to change.

Vendor_boot slot b has `AVB flags=3` (verification and hashtree disabled), so the
image does not need to be signed again and `vbmeta` does not need to be flashed.

### Method 1 - fastboot

```bash
adb reboot bootloader
fastboot devices
fastboot getvar current-slot          # must be b
fastboot flash vendor_boot_b vendor_boot.img
fastboot reboot recovery
```

If `fastboot flash` is refused (`not allowed in locked state`), do not force an
unlock (unlocking wipes data). Use method 2 instead.

### Method 2 - dd from a root shell (no fastboot, no unlock)

Boot Android normally, connect adb, then:

```bash
adb push vendor_boot.img /data/local/tmp/vendor_boot.img
adb shell
su
sha256sum /data/local/tmp/vendor_boot.img     # must match SHA256SUMS
dd if=/data/local/tmp/vendor_boot.img of=/dev/block/by-name/vendor_boot_b bs=1M
sync
sha256sum /dev/block/by-name/vendor_boot_b    # verify the write
reboot recovery
```

No other partition is written. If the read-back `sha256sum` differs, write again
before rebooting.

### After TWRP boots

```bash
adb shell mount | grep ' /data '     # must be f2fs, not empty
adb shell ls /sdcard                 # /data/media contents must be visible
adb shell ps -A | grep -E 'mobicore|keymaster|gatekeeper|keystore2'
```

If `/data` is not mounted, collect:
`logcat -d | grep -iE 'keymaster|gatekeeper|mobicore|keystore|fscrypt'`,
`dmesg | grep -iE 'mobicore|mcDrv'`, and `getprop | grep -i crypto`.

### Rollback

```bash
# fastboot
fastboot flash vendor_boot_b dump/vendor_boot_b.img
fastboot reboot

# or dd from a root shell
dd if=/data/local/tmp/vendor_boot_b_stock.img of=/dev/block/by-name/vendor_boot_b bs=1M
sync && reboot
```

If neither fastboot nor Android can be reached: hold **Volume Up + Power**
(recovery/preloader mode), then restore with SP Flash Tool using the official
X6532C firmware. That is why the partition dumps are kept first.

## Status / limitations

- FBE v2 + metadata decryption (`/metadata` on `md_udc`, keydirectory
  `/metadata/vold/metadata_encryption`) uses the Trustonic keymaster 4.1 running
  from the ramdisk. `/data` should mount without a password because the key is
  unwrapped through the TEE, not from a screen PIN.
- If `/data` still does not mount, check from `adb shell` in recovery:
  `ls -l /dev/mobicore*`, `ps -A | grep -E "mobicore|keymaster|gatekeeper|keystore2"`,
  `getprop | grep -i crypto`, and
  `logcat -d | grep -iE "keymaster|gatekeeper|mobicore|keystore|fscrypt"`.
- Normal Android boot is unaffected: `first_stage_ramdisk/fstab.mt6765` and the
  ramdisk modules stay stock, and the real `/vendor` partition masks the
  ramdisk's `vendor/` when Android boots.
- Vibration may not work (`regulator-vibrator.ko` loads, but TWRP needs
  `TW_NO_HAPTICS` if it crashes).
- A completely black screen during recovery boot means a panel module did not
  load. Check `lib/modules/modules.load.recovery` and make sure the modules came
  from this device, not from other firmware.

## License

This tree was written from a device dump and follows the AOSP/TWRP scheme. If you
publish builds, the tree source must be public too (GPLv3 for OrangeFox/TWRP).
