# OrangeFox untuk Infinix Smart 9 HD (X6532C)

Device tree OrangeFox Recovery untuk **Infinix Smart 9 HD / X6532C**, MediaTek MT6765, Android 12 (Go), A/B + Virtual A/B.

> Bukan untuk Infinix Smart 9 (X6532) — itu Helio G81 / MT6769Z, chipset dan layout partisinya beda.

## Kenapa recovery masuk ke `vendor_boot`

HP ini tidak punya partisi `recovery`. Firmware aslinya menaruh seluruh resource recovery di dalam **vendor ramdisk** pada partisi `vendor_boot`:

```
vendor_boot_a/b.img
├── vendor_ramdisk00   (lz4, 23.4 MB)  → system/bin/recovery, recovery.fstab, init.recovery.mt6765.rc
├── dtb                (145.728 byte)
└── AVB footer         (unsigned, Algorithm NONE)
```

Karena itu build memakai `BOARD_MOVE_RECOVERY_RESOURCES_TO_VENDOR_BOOT := true` dan target `vendorbootimage`, bukan `recoveryimage`. Kernel tetap di partisi `boot` dan **tidak disentuh**, jadi Magisk Kitsune yang kamu pasang di ramdisk `boot` tetap utuh.

## Isi tree

```
device/infinix/X6532C/
├── BoardConfig.mk            angka dari dump: header v4, base/offset, ukuran partisi
├── device.mk                 Virtual A/B, dynamic partitions, fastbootd
├── twrp_X6532C.mk            produk twrp_X6532C (lunch target)
├── AndroidProducts.mk
├── vendorsetup.sh
├── system.prop               getprop dari HP
├── prebuilt/dtb.img          dari vendor_boot (sha256 5f2bd3de…)
└── recovery/root/
    ├── init.recovery.mt6765.rc      dari vendor_boot HP + import init.decrypt.rc
    ├── init.decrypt.rc              start Trustonic TEE, keymaster, gatekeeper
    ├── first_stage_ramdisk/fstab.mt6765
    ├── lib/modules/*.ko            156 modul, vermagic 5.10.237 (dari HP)
    ├── vendor/                      service keymaster/gatekeeper + libs + TA (32-bit)
    └── system/etc/{recovery.fstab,twrp.flags}
```

`vendor/` berisi binary dan library asli dari partisi `/vendor` HP ini (keymaster
4.1 Trustonic, gatekeeper 1.0, keymaster_attestation 1.1, `mcDriverDaemon`,
`libMcClient`, registry TA Trustonic). TWRP hanya me-mount `/vendor` asli saat
membaca prop lalu melepasnya sebelum dekripsi, jadi stack TEE harus ikut di
ramdisk. `mcDrvModule.ko` + `gpapi.ko` di-`insmod` dari `init.decrypt.rc` karena
loader modul TWRP baru jalan setelah init.

`recovery.fstab` dan `twrp.flags` ditulis tangan, diturunkan dari fstab stock tetapi **dikoreksi**:

| Salah di tree publik | Yang benar di HP ini |
|---|---|
| `/metadata` → `by-name/metadata` | `/metadata` → `by-name/md_udc` (mmcblk0p10) |
| `/misc` → `by-name/misc` | `/misc` → `by-name/para` (tidak ada partisi `misc`) |
| `/tee1`, `/tee2` | `tee_a`, `tee_b` (A/B) |
| super 9.126 GB | super 5.368.709.120 byte |
| kernel modul 5.10.209 | 5.10.237 |

Berkas yang diambil dari HP (`lib/modules`, `dtb.img`, init rc, fstab first stage, `mtk_plpath_utils`, `ueventd.rc`, `cgroups.json`) bisa dibuat ulang dengan:

```bash
tools/extract_from_device.sh dump/vendor_boot_b.img
```

## Build lewat GitHub Actions

1. Buat repo baru di GitHub, lalu dorong isi folder ini (folder `dump/` sudah di-ignore, jangan diunggah — isinya image pribadi HP kamu, 240 MB):

   ```bash
   cd x6532-ofrp
   git init -b main
   git add .
   git commit -m "device tree X6532C + OrangeFox workflow"
   git remote add origin git@github.com:<username>/<repo>.git
   git push -u origin main
   ```

2. Buka tab **Actions** → **Build OrangeFox for X6532C** → **Run workflow**.
   - `fox_branch`: `12.1` (sesuai Android 12.1, jangan pilih 14.1 untuk device ini)
   - Dekripsi FBE selalu aktif (`TW_INCLUDE_CRYPTO := true` di `BoardConfig.mk`).

3. Tunggu. Sync sumber OrangeFox ±45 GB (30–60 menit), build 40–90 menit. Hasil ada di **Artifacts**: `vendor_boot.img`, `build-info.txt`, `SHA256SUMS`.

Runner standar GitHub cuma punya ~30 GB kosong setelah pembersihan, jadi kalau sync gagal karena disk penuh, jalankan build lokal (lihat bawah).

## Build lokal (cadangan)

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

Hasil: `out/target/product/X6532C/vendor_boot.img`.

Kalau image hasil build ditolak bootloader, bungkus ulang ramdisk-nya ke container stock:

```bash
tools/repack_vendor_boot.sh dump/vendor_boot_b.img \
    out/target/product/X6532C/vendor_boot.img \
    vendor_boot_final.img
```

## Flashing

> Sebelum flash, pastikan punya dump `boot_a`, `boot_b`, `vendor_boot_a`, `vendor_boot_b`, `vbmeta_a`, `vbmeta_b`. Sudah ada di `dump/`.
>
> Slot aktif HP ini **b**. Image hanya boleh masuk ke `vendor_boot_b`.
> Jangan sentuh `boot`, `init_boot`, `preloader`, `seccfg`, `nvram`, `nvdata`,
> `persist`; Magisk Kitsune ada di `boot` dan tidak perlu diubah.

Vendor_boot slot b punya `AVB flags=3` (verification + hashtree dimatikan), jadi
image tidak perlu ditandatangani ulang dan `vbmeta` tidak perlu diflash.

### Cara 1 — fastboot

```bash
adb reboot bootloader
fastboot devices
fastboot getvar current-slot          # harus b
fastboot flash vendor_boot_b vendor_boot.img
fastboot reboot recovery
```

Kalau `fastboot flash` ditolak (`not allowed in locked state`), jangan paksa
unlock (unlock menghapus data). Pakai cara 2.

### Cara 2 — dd dari root (tanpa fastboot, tanpa unlock)

Boot normal ke Android, sambungkan adb, lalu:

```bash
adb push vendor_boot.img /data/local/tmp/vendor_boot.img
adb shell
su
sha256sum /data/local/tmp/vendor_boot.img     # harus sama dengan SHA256SUMS
dd if=/data/local/tmp/vendor_boot.img of=/dev/block/by-name/vendor_boot_b bs=1M
sync
sha256sum /dev/block/by-name/vendor_boot_b    # verifikasi tulis
reboot recovery
```

Tidak ada partisi lain yang ditulis. Kalau `sha256sum` hasil baca berbeda,
tulis ulang sebelum reboot.

### Setelah masuk TWRP

```bash
adb shell mount | grep ' /data '     # harus f2fs, bukan kosong
adb shell ls /sdcard                 # isi /data/media harus terlihat
adb shell ps -A | grep -E 'mobicore|keymaster|gatekeeper|keystore2'
```

Kalau `/data` belum ter-mount, kirim output:
`logcat -d | grep -iE 'keymaster|gatekeeper|mobicore|keystore|fscrypt'`,
`dmesg | grep -iE 'mobicore|mcDrv'`, dan `getprop | grep -i crypto`.

### Rollback

```bash
# fastboot
fastboot flash vendor_boot_b dump/vendor_boot_b.img
fastboot reboot

# atau dd dari root
dd if=/data/local/tmp/vendor_boot_b_stock.img of=/dev/block/by-name/vendor_boot_b bs=1M
sync && reboot
```

Kalau sampai tidak bisa masuk fastboot/Android: tekan **Volume Up + Power**
(mode recovery/preloader), lalu pulihkan lewat SP Flash Tool dengan firmware
resmi X6532C. Itu sebabnya dump partisi disimpan dulu.

## Status / yang belum

- Dekripsi FBE v2 + metadata (`/metadata` di `md_udc`, keydirectory
  `/metadata/vold/metadata_encryption`) memakai keymaster 4.1 Trustonic yang
  dijalankan dari ramdisk. `/data` seharusnya langsung ter-mount tanpa password
  karena kuncinya di-unwrap lewat TEE, bukan PIN layar.
- Kalau `/data` tetap tidak ter-mount, cek dari `adb shell` di recovery:
  `ls -l /dev/mobicore*`, `ps -A | grep -E "mobicore|keymaster|gatekeeper|keystore2"`,
  `getprop | grep -i crypto`, dan `logcat -d | grep -iE "keymaster|gatekeeper|mobicore|keystore|fscrypt"`.
- Normal boot Android tidak terpengaruh: `first_stage_ramdisk/fstab.mt6765` dan
  modul di ramdisk tetap milik stock, dan partisi `/vendor` asli menutupi
  `vendor/` milik ramdisk saat Android boot.
- Vibrasi kemungkinan tidak jalan (`regulator-vibrator.ko` termuat, tapi TWRP butuh `TW_NO_HAPTICS` bila crash).
- Kalau layar mati total saat recovery boot: itu tanda modul panel tidak termuat. Cek `lib/modules/modules.load.recovery` dan pastikan memakai modul dari HP ini, bukan dari firmware lain.

## Lisensi

Tree ini ditulis dari dump device dan mengikuti skema AOSP/TWRP. Kalau kamu merilis build ke publik, sumber tree-nya wajib publik juga (GPLv3 untuk OrangeFox/TWRP).
