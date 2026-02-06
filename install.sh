#!/usr/bin/env bash
# =============================================================================
# LFS LiveCD -> HDD Installer (Zenity GUI) - Versi ULTIMATE
# =============================================================================

set -euo pipefail

# Pastikan dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    zenity --error --title="Akses Ditolak" --text="Jalankan sebagai root:\nsudo bash $0" --width=400
    exit 1
fi

# Cek ketersediaan zenity
command -v zenity >/dev/null 2>&1 || { echo "Zenity tidak ditemukan!"; exit 1; }

# ------------------------------------------------------------------------------
# Fungsi Bantu
# ------------------------------------------------------------------------------

die() { zenity --error --title="ERROR" --text="$1" --width=500; exit 1; }
info() { zenity --info --title="Info" --text="$1" --width=500; }
confirm() { zenity --question --title="Konfirmasi" --text="$1" --width=600 --ok-label="Ya" --cancel-label="Batal" || exit 0; }

choose_list() {
    zenity --list --title="$1" --column="ID" --column="Deskripsi" --width=600 --height=400 "$@"
}

# ------------------------------------------------------------------------------
# Wizard Persiapan
# ------------------------------------------------------------------------------

confirm "SELAMAT DATANG DI INSTALLER LFS!\nData di partisi target AKAN DIHAPUS TOTAL (Format ext4).\n\nLanjut?" || exit 0

# 1. Pilih disk untuk GRUB
disks=()
while IFS= read -r line; do disks+=("$line"); done < <(lsblk -dno NAME,SIZE,TRAN,MODEL | grep -v '^loop' | awk '{printf "%s\t%s\t%s\t%s\n", $1,$2,$3,substr($0,index($0,$4))}' | sed 's/\t/|/g')
[ ${#disks[@]} -eq 0 ] && die "Disk tidak ditemukan."
selected_disk=$(choose_list "Pilih DISK untuk Bootloader (GRUB)" "${disks[@]}") || exit 0
TARGET_DISK="/dev/${selected_disk%%|*}"

# 2. Pilih partisi root
parts=()
while IFS= read -r line; do parts+=("$line"); done < <(lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT | grep -v '^loop' | awk '$3 == "ext4" || $3 == "" {printf "%s\t%s\t%s\t%s\n", $1,$2,$3,($4?$4:"kosong")}' | sed 's/\t/|/g')
[ ${#parts[@]} -eq 0 ] && die "Tidak ada partisi ext4 yang tersedia."
selected_part=$(choose_list "Pilih PARTISI ROOT (Akan di-format)" "${parts[@]}") || exit 0
TARGET_PART="/dev/${selected_part%%|*}"

# ------------------------------------------------------------------------------
# Input Konfigurasi Sistem
# ------------------------------------------------------------------------------

# 3. Form Akun & Hostname
USER_FORM=$(zenity --forms --title="Identitas Sistem" \
    --add-entry="Username" --add-password="Password" --add-password="Konfirmasi Password" --add-entry="Hostname" \
    --separator="|") || exit 0
IFS='|' read -r NEW_USERNAME PW1 PW2 HOSTNAME <<< "$USER_FORM"
[ "$PW1" != "$PW2" ] && die "Password tidak cocok!"

# 4. Pilih Keyboard Layout
KBD_LAYOUT=$(zenity --list --title="Layout Keyboard" --column="Kode" --column="Deskripsi" \
    "us" "US English (Default)" "id" "Indonesia" "uk" "United Kingdom" "jp" "Japan" "fr" "France" "de" "Germany" \
    --width=400 --height=300) || KBD_LAYOUT="us"

# 5. Pilih Locale (Bahasa Sistem)
LOCALE=$(zenity --list --title="Bahasa Sistem (Locale)" --column="Locale" --column="Bahasa" \
    "en_US.UTF-8" "English (US)" "id_ID.UTF-8" "Bahasa Indonesia" "en_GB.UTF-8" "English (UK)" \
    "ja_JP.UTF-8" "Japanese" "de_DE.UTF-8" "German" \
    --width=400 --height=300) || LOCALE="en_US.UTF-8"

# 6. Pilih Timezone (Daftar Sangat Lengkap)
TIMEZONE=$(zenity --list --title="Zona Waktu / Lokasi" --width=550 --height=500 \
    --column="Zona Waktu" --column="Lokasi" \
    "Asia/Jakarta" "Indonesia (WIB)" "Asia/Makassar" "Indonesia (WITA)" "Asia/Jayapura" "Indonesia (WIT)" \
    "Asia/Singapore" "Singapore" "Asia/Kuala_Lumpur" "Malaysia" "Asia/Bangkok" "Thailand" \
    "Asia/Tokyo" "Japan" "Asia/Seoul" "South Korea" "Asia/Shanghai" "China" \
    "Europe/London" "United Kingdom" "Europe/Paris" "France" "Europe/Berlin" "Germany" \
    "Australia/Sydney" "Australia" "America/New_York" "USA (East Coast)" "America/Los_Angeles" "USA (West Coast)") || TIMEZONE="Asia/Jakarta"

# ------------------------------------------------------------------------------
# Eksekusi Instalasi
# ------------------------------------------------------------------------------

(
    echo "5"; echo "# Memformat $TARGET_PART (Ext4)..."
    mkfs.ext4 -F "$TARGET_PART" || exit 1

    echo "10"; echo "# Mounting target..."
    mkdir -p /mnt/target && mount "$TARGET_PART" /mnt/target

    echo "30"; echo "# Menyalin sistem (rsync)..."
    # Salin file dari live environment
    if mountpoint -q /.root 2>/dev/null; then
        rsync -aHAX --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/cow/*} /.root/ /mnt/target/
    else
        rsync -aHAX / /mnt/target/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/cow/*,/squash/*}
    fi
    mkdir -p /mnt/target/{boot,dev,proc,sys,run,tmp} && chmod 1777 /mnt/target/tmp

    echo "50"; echo "# Mengatur fstab..."
    UUID=$(blkid -s UUID -o value "$TARGET_PART")
    echo "UUID=$UUID / ext4 defaults,noatime 1 1" > /mnt/target/etc/fstab
    echo "tmpfs /tmp tmpfs defaults,mode=1777 0 0" >> /mnt/target/etc/fstab

    echo "70"; echo "# Masuk ke Chroot & Konfigurasi..."
    for d in dev proc sys run; do mount --bind /$d /mnt/target/$d; done
    
    chroot /mnt/target /bin/bash -c "
        echo '$HOSTNAME' > /etc/hostname
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        
        # Atur Keyboard & Locale
        echo 'KEYMAP=$KBD_LAYOUT' > /etc/vconsole.conf
        echo 'LANG=$LOCALE' > /etc/locale.conf
        
        # Buat user & hak sudo
        useradd -m -G wheel,audio,video -s /bin/bash '$NEW_USERNAME' || true
        echo '$NEW_USERNAME:$PW1' | chpasswd
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel-group
        chmod 0440 /etc/sudoers.d/wheel-group
    "

    echo "90"; echo "# Instalasi GRUB..."
    if [ -d /sys/firmware/efi ]; then
        mkdir -p /mnt/target/boot/efi
        EFI_PART=$(lsblk -no NAME,PARTTYPE "$TARGET_DISK" | grep -i ef00 | head -1 | awk '{print "/dev/" $1}')
        if [ -n "$EFI_PART" ]; then
            mount "$EFI_PART" /mnt/target/boot/efi && chroot /mnt/target grub-install --target=x86_64-efi --bootloader-id=LFS
        fi
    else
        chroot /mnt/target grub-install --target=i386-pc "$TARGET_DISK"
    fi
    chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

    echo "100"; echo "# Instalasi Selesai!"
    sync && umount -R /mnt/target || true
) | zenity --progress --title="LFS Installer" --text="Menginstal sistem ke HDD..." --pulsate --auto-close --width=550

[ $? -eq 0 ] && info "INSTALASI SUKSES!\n\nUser: $NEW_USERNAME\nHostname: $HOSTNAME\nLocale: $LOCALE\nTimezone: $TIMEZONE\n\nSilakan Reboot." || die "Instalasi Gagal!"
