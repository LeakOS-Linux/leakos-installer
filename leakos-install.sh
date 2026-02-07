#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux - LiveCD → HDD Installer (Zenity GUI) - Versi ULTIMATE + cfdisk + Dense Dracos-style Banner
# =============================================================================

set -euo pipefail

# Banner dense style mirip Dracos (hijau border + merah teks, Pango markup untuk Zenity)
LEAKOS_BANNER_PANGO="
<span foreground='#00ff00'>╔════════════════════════════════════════════════════════════╗</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'><b>L E A K O S   L I N U X</b></span>                               <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>██╗     ███████╗ █████╗ ██╗  ██╗ ██████╗ ███████╗</span>          <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>██║     ██╔════╝██╔══██╗██║ ██╔╝██╔════╝ ██╔════╝</span>          <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>██║     █████╗  ███████║█████╔╝ ██║  ███╗█████╗  </span>           <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>██║     ██╔══╝  ██╔══██║██╔═██╗ ██║   ██║██╔══╝  </span>           <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>███████╗███████╗██║  ██║██║  ██╗╚██████╔╝███████╗</span>          <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>  <span foreground='red'>╚══════╝╚══════╝╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝ ╚══════╝</span>          <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>║</span>     <span foreground='red'>Unleashed Freedom • Privacy First • Pentest Ready</span>      <span foreground='#00ff00'>║</span>
<span foreground='#00ff00'>╚════════════════════════════════════════════════════════════╝</span>

<span foreground='#00ff00'> LeakOS v1.x (C) 2025-2026 leakos.dev | Indonesian Custom Distro</span>
"

# Pastikan dijalankan sebagai root
if [ "$(id -u)" -ne 0 ]; then
    zenity --error --title="Akses Ditolak" --text="Jalankan sebagai root:\nsudo bash $0" --width=400
    exit 1
fi

# Cek zenity dan cfdisk
command -v zenity >/dev/null 2>&1 || { echo "Zenity tidak ditemukan!"; exit 1; }
command -v cfdisk >/dev/null 2>&1 || { zenity --error --text="cfdisk tidak ditemukan!"; exit 1; }

# ------------------------------------------------------------------------------
# Fungsi Bantu dengan branding
# ------------------------------------------------------------------------------

die() { zenity --error --title="LeakOS ERROR" --text="$1" --width=500; exit 1; }
info() { zenity --info --title="LeakOS Info" --text="$1" --width=500; }
confirm() { zenity --question --title="LeakOS Konfirmasi" --text="$1" --width=700 --ok-label="Ya" --cancel-label="Batal" || exit 0; }

choose_list() {
    zenity --list --title="LeakOS - $1" --column="ID" --column="Deskripsi" --width=600 --height=400 "$@"
}

# ------------------------------------------------------------------------------
# Wizard Persiapan
# ------------------------------------------------------------------------------

confirm "${LEAKOS_BANNER_PANGO}\n\n<b>SELAMAT DATANG DI INSTALLER LeakOS!</b>\nPartisi disk akan dibuat manual via cfdisk.\nData bisa hilang jika format!\n\nLanjut?" || exit 0

# 1. Pilih disk untuk partitioning & GRUB
disks=()
while IFS= read -r line; do disks+=("$line"); done < <(lsblk -dno NAME,SIZE,TRAN,MODEL | grep -v '^loop' | awk '{printf "%s\t%s\t%s\t%s\n", $1,$2,$3,substr($0,index($0,$4))}' | sed 's/\t/|/g')
[ ${#disks[@]} -eq 0 ] && die "Disk tidak ditemukan."
selected_disk=$(choose_list "Pilih DISK untuk Partitioning & Bootloader (GRUB)" "${disks[@]}") || exit 0
TARGET_DISK="/dev/${selected_disk%%|*}"

# 2. Jalankan cfdisk interaktif
zenity --info --title="LeakOS - Buat Partisi" --text="${LEAKOS_BANNER_PANGO}\n\nBuka <b>cfdisk ${TARGET_DISK}</b> sekarang.\n\nCara pakai:\n- Pilih [gpt] untuk UEFI\n- [New] → EFI 512M-1G (Type: EFI System)\n- [New] → Root (sisa space, Type: Linux filesystem)\n- Opsional: Swap\n- [Write] yes → [Quit]\n\nTekan OK untuk mulai." --width=700

cfdisk "${TARGET_DISK}"

partprobe "${TARGET_DISK}" 2>/dev/null || true
sleep 2

# 3. Pilih partisi root setelah partitioning
parts=()
while IFS= read -r line; do parts+=("$line"); done < <(lsblk -no NAME,SIZE,FSTYPE,MOUNTPOINT "${TARGET_DISK}" | grep -v '^NAME' | awk '{printf "%s\t%s\t%s\t%s\n", $1,$2,$3,($4?$4:"kosong")}' | sed 's/\t/|/g')
[ ${#parts[@]} -eq 0 ] && die "Tidak ada partisi di ${TARGET_DISK}!"
selected_part=$(choose_list "Pilih PARTISI ROOT (akan di-format ext4)" "${parts[@]}") || exit 0
TARGET_PART="/dev/${selected_part%%|*}"

confirm "${LEAKOS_BANNER_PANGO}\n\nFORMAT ${TARGET_PART} jadi ext4?\nSemua data di partisi ini AKAN HILANG!\n\nLanjut?" || exit 0

# ------------------------------------------------------------------------------
# Input Konfigurasi (sama seperti sebelumnya)
# ------------------------------------------------------------------------------

USER_FORM=$(zenity --forms --title="LeakOS - Identitas Sistem" \
    --add-entry="Username" --add-password="Password" --add-password="Konfirmasi Password" --add-entry="Hostname" \
    --separator="|") || exit 0
IFS='|' read -r NEW_USERNAME PW1 PW2 HOSTNAME <<< "$USER_FORM"
[ "$PW1" != "$PW2" ] && die "Password tidak cocok!"

KBD_LAYOUT=$(zenity --list --title="LeakOS - Layout Keyboard" --column="Kode" --column="Deskripsi" \
    "us" "US English (Default)" "id" "Indonesia" "uk" "United Kingdom" "jp" "Japan" "fr" "France" "de" "Germany" \
    --width=400 --height=300) || KBD_LAYOUT="us"

LOCALE=$(zenity --list --title="LeakOS - Bahasa Sistem" --column="Locale" --column="Bahasa" \
    "en_US.UTF-8" "English (US)" "id_ID.UTF-8" "Bahasa Indonesia" "en_GB.UTF-8" "English (UK)" \
    --width=400 --height=300) || LOCALE="en_US.UTF-8"

TIMEZONE=$(zenity --list --title="LeakOS - Zona Waktu" --width=550 --height=500 \
    --column="Zona Waktu" --column="Lokasi" \
    "Asia/Jakarta" "Indonesia (WIB)" "Asia/Makassar" "Indonesia (WITA)" "Asia/Jayapura" "Indonesia (WIT)" \
    "Asia/Singapore" "Singapore" "Asia/Kuala_Lumpur" "Malaysia" "Asia/Bangkok" "Thailand" \
    "Asia/Tokyo" "Japan" "Asia/Seoul" "South Korea" "Asia/Shanghai" "China" \
    "Europe/London" "United Kingdom" "Europe/Paris" "France" "Europe/Berlin" "Germany" \
    "Australia/Sydney" "Australia" "America/New_York" "USA (East Coast)" "America/Los_Angeles" "USA (West Coast)") || TIMEZONE="Asia/Jakarta"

# ------------------------------------------------------------------------------
# Instalasi utama
# ------------------------------------------------------------------------------

(
    echo "5"; echo "# ${LEAKOS_BANNER_PANGO}\nMemformat ${TARGET_PART}..."
    mkfs.ext4 -F "${TARGET_PART}" || exit 1

    echo "10"; echo "# ${LEAKOS_BANNER_PANGO}\nMounting..."
    mkdir -p /mnt/target && mount "${TARGET_PART}" /mnt/target

    EFI_PART=$(lsblk -no NAME,PARTTYPE "${TARGET_DISK}" | grep -i 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b' | head -1 | awk '{print "/dev/" $1}')
    if [ -n "$EFI_PART" ]; then
        mkdir -p /mnt/target/boot/efi
        mkfs.fat -F32 "$EFI_PART" 2>/dev/null || true
        mount "$EFI_PART" /mnt/target/boot/efi
    fi

    echo "30"; echo "# ${LEAKOS_BANNER_PANGO}\nMenyalin LeakOS (rsync)..."
    if mountpoint -q /.root 2>/dev/null; then
        rsync -aHAX --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/cow/*} /.root/ /mnt/target/
    else
        rsync -aHAX / /mnt/target/ --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/cow/*,/squash/*}
    fi
    mkdir -p /mnt/target/{boot,dev,proc,sys,run,tmp} && chmod 1777 /mnt/target/tmp

    mkdir -p /mnt/target/boot
    cp -a /boot/{vmlinuz*,grub} /mnt/target/boot/ 2>/dev/null || true

    echo "50"; echo "# ${LEAKOS_BANNER_PANGO}\nSetup fstab..."
    UUID=$(blkid -s UUID -o value "${TARGET_PART}")
    cat << EOF > /mnt/target/etc/fstab
UUID=$UUID / ext4 defaults,noatime 0 1
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
tmpfs /dev/shm tmpfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
EOF
    if [ -n "$EFI_PART" ]; then
        EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
        echo "UUID=$EFI_UUID /boot/efi vfat defaults 0 2" >> /mnt/target/etc/fstab
    fi

    echo "70"; echo "# ${LEAKOS_BANNER_PANGO}\nChroot & Konfigurasi..."
    for d in dev proc sys run; do mount --bind /$d /mnt/target/$d; done
    
    chroot /mnt/target /bin/bash -c "
        locale-gen
        echo '$HOSTNAME' > /etc/hostname
        ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
        echo 'KEYMAP=$KBD_LAYOUT' > /etc/vconsole.conf
        echo 'LANG=$LOCALE' > /etc/locale.conf
        useradd -m -G wheel,audio,video -s /bin/bash '$NEW_USERNAME' || true
        echo '$NEW_USERNAME:$PW1' | chpasswd
        echo '%wheel ALL=(ALL:ALL) ALL' > /etc/sudoers.d/wheel-group
        chmod 0440 /etc/sudoers.d/wheel-group
        
    "

    echo "90"; echo "# ${LEAKOS_BANNER_PANGO}\nInstal GRUB..."
    if [ -d /sys/firmware/efi ] && [ -n "$EFI_PART" ]; then
        chroot /mnt/target grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=LeakOS --recheck
    else
        chroot /mnt/target grub-install --target=i386-pc --recheck "${TARGET_DISK}"
    fi
    chroot /mnt/target grub-mkconfig -o /boot/grub/grub.cfg

    echo "100"; echo "# ${LEAKOS_BANNER_PANGO}\nSelesai!"
    sync && umount -R /mnt/target || true
) | zenity --progress --title="LeakOS Installer" --text="Menginstal LeakOS..." --pulsate --auto-close --width=750

if [ $? -eq 0 ]; then
    info "${LEAKOS_BANNER_PANGO}\n\n<b>INSTALASI BERHASIL!</b>\nUser: $NEW_USERNAME\nHostname: $HOSTNAME\nLocale: $LOCALE\nTimezone: $TIMEZONE\n\nReboot sekarang dan selamat menikmati LeakOS!\n(C) 2025-2026 leakos.dev"
else
    die "Instalasi Gagal! Cek koneksi atau log."
fi
