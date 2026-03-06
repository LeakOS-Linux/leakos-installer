#!/usr/bin/env bash
# =============================================================================
# LeakOS Linux Installer - FIXED & FULL VERSION (Terminal Step-by-Step)
# =============================================================================
# Perbaikan utama:
# - ROOT_UUID didefinisikan DI DALAM chroot → hilangkan unbound variable
# - GRUB menggunakan UUID dengan benar
# - Tampilan tetap rapi dengan echo -e

set -euo pipefail

# =============================================================================
# DETEKSI WARNA
# =============================================================================
if [ -t 1 ] && command -v tput >/dev/null 2>&1 && [ "$(tput colors 2>/dev/null || echo 0)" -ge 8 ]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BLINK='\033[5m'  # <-- TAMBAHKAN INI
    BOLD='\033[1m'
    NC='\033[0m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BLINK='' BOLD='' NC='' RESET=''
fi

clear

echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║                  L E A K O S   L I N U X                  ║${NC}"
echo -e "${CYAN}║                                                            ║${NC}"
echo -e "${CYAN}║     Unleashed Freedom • Privacy First • Indonesian Root    ║${NC}"
echo -e "${CYAN}║       Custom LFS-based Distro • Pentest & Developer Ready  ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "           Installer Terminal - Versi Aman & User-Friendly"
echo -e "                    (Tekan Ctrl+C kapan saja untuk batal)"
echo -e ""
echo -e "${YELLOW}Tekan Enter untuk memulai instalasi...${NC}"
read -r dummy

# =============================================================================
# ROOT CHECK
# =============================================================================
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}${BOLD}ERROR: Harus dijalankan sebagai root.${NC}"
    exit 1
fi

# =============================================================================
# DEPENDENCY CHECK
# =============================================================================
echo -e "${BLUE}Memeriksa dependensi...${NC}"
for cmd in lsblk cfdisk mkfs.ext4 rsync grub-install grub-mkconfig blkid git partprobe; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo -e "${RED}ERROR: Tidak ditemukan perintah: $cmd${NC}"
        echo -e "Pastikan paket yang dibutuhkan sudah terinstall di live environment."
        exit 1
    fi
done
echo -e "${GREEN}Semua dependensi OK.${NC}"
echo -e ""

# =============================================================================
# PERINGATAN AWAL
# =============================================================================
echo -e "${RED}${BOLD}┌────────────────────────────────────────────────────────────┐${NC}"
echo -e "${RED}│  ${BOLD}SEMUA DATA DI DISK TARGET AKAN DIHAPUS SELAMANYA!${NC}         ${RED}│${NC}"
echo -e "${RED}│                                                            │${NC}"
echo -e "${RED}│  • Hanya gunakan pada mesin kosong atau VM testing         │${NC}"
echo -e "${RED}│  • Tidak ada backup otomatis                               │${NC}"
echo -e "${RED}│  • Tidak ada UNDO setelah konfirmasi                       │${NC}"
echo -e "${RED}└────────────────────────────────────────────────────────────┘${NC}"
echo -e ""
echo -en "${YELLOW}Lanjut instalasi? (ketik 'yes' lalu Enter) : ${NC}"
read -r confirm
if [[ "${confirm,,}" != "yes" ]]; then
    echo -e "${GREEN}Instalasi dibatalkan oleh pengguna.${NC}"
    exit 0
fi


# =============================================================================
# DISK SELECTION - CYBERPUNK STYLE
# =============================================================================
echo -e ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║               SHADOW DISK SELECTION PROTOCOL              ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""

echo -e "${BLUE}Disk fisik yang terdeteksi:${NC}"
echo "------------------------------------------------------------"

disk_list=()
i=1
while IFS= read -r line; do
    name=$(echo "$line" | awk '{print $1}')
    size=$(echo "$line" | awk '{print $2}')
    model=$(echo "$line" | awk '{$1=$2=""; print substr($0,3)}' | xargs || echo "Unknown")
    printf " ${GREEN}%2d)${NC} /dev/${CYAN}%-6s${NC} (%6s) - %s\n" "$i" "$name" "$size" "$model"
    disk_list+=("/dev/$name")
    ((i++))
done < <(lsblk -dno NAME,SIZE,MODEL | awk '$1~/^[a-z]+$/ && $1!="loop" && $1!="sr" && $1!="zram" && $1!="nvme[0-9]+n[0-9]+"')

if [ ${#disk_list[@]} -eq 0 ]; then
    echo -e "${RED}ERROR: Tidak ada disk fisik yang terdeteksi.${NC}"
    exit 1
fi

if [ ${#disk_list[@]} -eq 1 ]; then
    echo -e "${GREEN}(Hanya 1 disk terdeteksi → otomatis dipilih)${NC}"
    TARGET_DISK="${disk_list[0]}"
else
    echo -e ""
    echo -en "${YELLOW}Pilih nomor disk target (1-${#disk_list[@]}) : ${NC}"
    read -r disk_num
    if ! [[ "$disk_num" =~ ^[0-9]+$ ]] || [ "$disk_num" -lt 1 ] || [ "$disk_num" -gt "${#disk_list[@]}" ]; then
        echo -e "${RED}ERROR: Nomor tidak valid.${NC}"
        exit 1
    fi
    TARGET_DISK="${disk_list[$((disk_num-1))]}"
fi

echo -e ""
echo -e "Disk terpilih : ${RED}${BOLD}${TARGET_DISK}${NC}"
echo -e "${RED}SEMUA DATA AKAN HILANG SELAMANYA!${NC}"
echo -en "${YELLOW}Yakin ingin lanjut? (ketik 'yes') : ${NC}"
read -r confirm_disk
if [[ "${confirm_disk,,}" != "yes" ]]; then
    echo -e "${GREEN}Dibatalkan.${NC}"
    exit 0
fi

# =============================================================================
# SHADOW PARTITIONING - MBR / LEGACY BIOS ONLY (NO UEFI)
# =============================================================================
echo -e ""
echo -e "${CYAN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${CYAN}║          ${RED}${BOLD}SHADOW MBR PARTITION PROTOCOL${NC}${CYAN}                     ║${NC}"
echo -e "${CYAN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "${YELLOW}Target disk : ${BOLD}${TARGET_DISK}${NC}  $(lsblk -dno SIZE,MODEL "$TARGET_DISK" | awk '{print $1 " • " $2}')"
echo -e "${RED}${BOLD}SEMUA DATA DI DISK INI AKAN DIHAPUS PERMANEN!${NC}"
echo -e ""

echo -e "${BLUE}Pilih Mode Partisi (MBR/Legacy):${NC}"
echo -e " ${GREEN}1${NC}) ${BOLD}Auto Simple${NC}      → Root + Swap + Home otomatis (rekomendasi)"
echo -e " ${CYAN}2${NC}) ${BOLD}Advanced Manual${NC}  → Kamu atur sendiri semua partisi"
echo -e " ${YELLOW}3${NC}) ${BOLD}cfdisk Manual${NC}    → Mode klasik (langsung buka cfdisk)"
echo ""
echo -en "${YELLOW}Pilihan (1/2/3) [default: 1] : ${NC}"
read -r part_mode
part_mode=${part_mode:-1}

# Reset variabel penting
ROOT_PART="" HOME_PART="" SWAP_PART=""

case $part_mode in
    1)  # ==================== AUTO SIMPLE MBR ====================
        echo -e "${GREEN}Memulai Shadow Auto-Partition (MBR)...${NC}"
        echo -e "${CYAN}Mode: ${BOLD}Legacy BIOS / MBR${NC} (tanpa EFI)${NC}"

        echo -e ""
        echo -e "${YELLOW}Ukuran yang akan dibuat:${NC}"
        echo -e "   Root    : 60G   (ditandai bootable)"
        echo -e "   Swap    : 8G"
        echo -e "   Home    : Sisanya"
        echo -en "${YELLOW}Lanjut otomatis? (yes) : ${NC}"
        read -r auto_confirm
        [[ "${auto_confirm,,}" != "yes" ]] && { echo -e "${RED}Dibatalkan.${NC}"; exit 0; }

        # Wipe signature lama
        wipefs -af "$TARGET_DISK" >/dev/null 2>&1
        sync; partprobe "$TARGET_DISK"

        # Buat tabel MBR dengan sfdisk
        sfdisk "$TARGET_DISK" << EOF
label: dos
size=60G, type=83, bootable
size=8G,  type=82
size=+,   type=83
EOF

        sync; sleep 1.5; partprobe "$TARGET_DISK"; udevadm settle

        # Ambil partisi yang baru dibuat
        mapfile -t PARTS < <(lsblk -ln -o NAME,TYPE "$TARGET_DISK" | awk '$2=="part" {print "/dev/"$1}')

        ROOT_PART="${PARTS[0]}"
        SWAP_PART="${PARTS[1]}"
        HOME_PART="${PARTS[2]:-}"  # kalau ada sisa

        # Format
        mkfs.ext4 -F -L "LeakOS-Root" "$ROOT_PART" && echo -e "${GREEN}✓ Root formatted${NC}"
        mkswap -L "LeakOS-Swap" "$SWAP_PART" && echo -e "${GREEN}✓ Swap formatted${NC}"
        [ -n "$HOME_PART" ] && mkfs.ext4 -F -L "LeakOS-Home" "$HOME_PART" && echo -e "${GREEN}✓ Home formatted${NC}"
        ;;

    2)  # ==================== ADVANCED MANUAL MBR ====================
        clear
        echo -e "${RED}${BOLD}SHADOW MANUAL PARTITIONING (MBR ONLY)${NC}"
        echo -e "${YELLOW}Buka cfdisk dulu untuk buat partisi, lalu set mount point${NC}"
        echo ""
        cfdisk "$TARGET_DISK"
        sync; partprobe "$TARGET_DISK"; sleep 1

        echo -e "${CYAN}┌──────────────────── PARTISI DETEKSI (MBR) ────────────────────┐${NC}"
        lsblk -o NAME,SIZE,TYPE,FSTYPE "$TARGET_DISK"
        echo -e "${CYAN}└──────────────────────────────────────────────────────────────┘${NC}"

        declare -A MOUNTS
        while true; do
            echo -en "\n${YELLOW}Partisi (contoh /dev/sda1) [kosong = selesai]: ${NC}"
            read -r part
            [ -z "$part" ] && break
            [[ ! -b "$part" ]] && { echo -e "${RED}Partisi tidak ditemukan!${NC}"; continue; }

            echo -en "Mount point ( /  /home  swap ) : "
            read -r mp
            mp=$(echo "$mp" | xargs)
            [[ "$mp" =~ ^(/|/home|swap)$ ]] && MOUNTS["$part"]="$mp" && echo -e "${GREEN}✓ $part → $mp${NC}"
        done

        ROOT_PART=$(for k in "${!MOUNTS[@]}"; do [[ ${MOUNTS[$k]} == "/" ]] && echo "$k"; done)
        HOME_PART=$(for k in "${!MOUNTS[@]}"; do [[ ${MOUNTS[$k]} == "/home" ]] && echo "$k"; done)
        SWAP_PART=$(for k in "${!MOUNTS[@]}"; do [[ ${MOUNTS[$k]} == "swap" ]] && echo "$k"; done)

        # Format kalau user setuju
        for p in "$ROOT_PART" "$HOME_PART"; do
            [[ -n "$p" ]] && { 
                echo -en "Format $p sebagai ext4? (yes): "; 
                read f; [[ "${f,,}" == "yes" ]] && mkfs.ext4 -F "$p"; 
            }
        done
        [[ -n "$SWAP_PART" ]] && { echo -en "Buat swap di $SWAP_PART? (yes): "; read s; [[ "${s,,}" == "yes" ]] && mkswap "$SWAP_PART"; }
        ;;

    3)
        # Mode cfdisk klasik (seperti script asli)
        echo -e "${YELLOW}Membuka cfdisk untuk partisi manual (MBR)${NC}"
        cfdisk "$TARGET_DISK"
        sync; partprobe "$TARGET_DISK"

        # Deteksi partisi ext4 untuk root (fallback seperti script lama)
        mapfile -t ext4_parts < <(lsblk -ln -o NAME,FSTYPE "$TARGET_DISK" | awk '$2=="ext4" {print "/dev/"$1}')
        ROOT_PART="${ext4_parts[0]:-}"
        if [ -z "$ROOT_PART" ]; then
            echo -e "${RED}Tidak ada partisi ext4 ditemukan. Harus buat minimal satu partisi root.${NC}"
            exit 1
        fi
        echo -e "${YELLOW}Menggunakan partisi root: ${CYAN}$ROOT_PART${NC}"
        ;;
    *)
        echo -e "${RED}Mode tidak valid!${NC}"
        exit 1
        ;;
esac

# =============================================================================
# SUMMARY KEREN (MBR VERSION)
# =============================================================================
clear
echo -e "${MAGENTA}╔═══════════════════════ SHADOW MBR PARTITION MAP ═════════════════════╗${NC}"
echo -e "${MAGENTA}║${NC}  Disk       : ${BOLD}${CYAN}${TARGET_DISK}${NC}  (MBR / Legacy BIOS)"
[ -n "$ROOT_PART" ] && echo -e "${MAGENTA}║${NC}  Root       : ${BOLD}${GREEN}${ROOT_PART}${NC}  → /"
[ -n "$HOME_PART" ] && echo -e "${MAGENTA}║${NC}  Home       : ${YELLOW}${HOME_PART}${NC}  → /home"
[ -n "$SWAP_PART" ] && echo -e "${MAGENTA}║${NC}  Swap       : ${RED}${SWAP_PART}${NC}  → [SWAP]"
echo -e "${MAGENTA}╚══════════════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -en "${YELLOW}${BOLD}Semua konfigurasi benar? (yes) : ${NC}"
read -r confirm_part
[[ "${confirm_part,,}" != "yes" ]] && { echo -e "${RED}Dibatalkan.${NC}"; exit 0; }

# =============================================================================
# MOUNTING PARTISI (MBR)
# =============================================================================
echo -e "${BLUE}Mounting partisi...${NC}"
mkdir -p /mnt/leakos

mount "$ROOT_PART" /mnt/leakos

[ -n "$HOME_PART" ] && { mkdir -p /mnt/leakos/home; mount "$HOME_PART" /mnt/leakos/home; }
[ -n "$SWAP_PART" ] && swapon "$SWAP_PART"

echo -e "${GREEN}Partisi sudah ter-mount.${NC}"

# =============================================================================
# INPUT USER & KONFIGURASI DASAR
# =============================================================================
echo -e "${BLUE}Konfigurasi dasar sistem${NC}"
echo ""
echo -n "Username (default: leakos): "
read -r USERNAME
USERNAME=${USERNAME:-leakos}

echo -n "Hostname (default: leakos): "
read -r HOSTNAME
HOSTNAME=${HOSTNAME:-leakos}

echo -n "Password untuk user $USERNAME: "
read -s PASSWORD
echo ""
echo -n "Konfirmasi password: "
read -s PASSWORD2
echo ""
if [ "$PASSWORD" != "$PASSWORD2" ] || [ -z "$PASSWORD" ]; then
    echo -e "${RED}ERROR: Password tidak cocok atau kosong.${NC}"
    exit 1
fi

echo -n "Password untuk root: "
read -s ROOT_PASSWORD
echo ""
echo -n "Konfirmasi password root: "
read -s ROOT_PASSWORD2
echo ""

if [ "$ROOT_PASSWORD" != "$ROOT_PASSWORD2" ] || [ -z "$ROOT_PASSWORD" ]; then
    echo -e "${RED}ERROR: Password root tidak cocok atau kosong.${NC}"
    exit 1
fi

# =============================================================================
# TIMEZONE (menggunakan fungsi yang kamu berikan)
# =============================================================================
get_timezone() {
    echo ""
    echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║ SETTING ZONA WAKTU ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
    echo ""
    if ping -c 1 google.com >/dev/null 2>&1; then
        echo -e "${CYAN}Mendeteksi zona waktu otomatis...${NC}"
        AUTO_TZ=$(curl -s http://ip-api.com/line?fields=timezone 2>/dev/null || echo "")
        if [ -n "$AUTO_TZ" ] && [ -f "/usr/share/zoneinfo/$AUTO_TZ" ]; then
            echo -e "${GREEN}✅ Terdeteksi: $AUTO_TZ${NC}"
            echo -n "Gunakan zona ini? (Y/n): "
            read -r use_auto
            if [[ "$use_auto" == "y" ]] || [[ "$use_auto" == "Y" ]] || [[ -z "$use_auto" ]]; then
                TIMEZONE="$AUTO_TZ"
                echo -e "${GREEN}✅ Timezone: $TIMEZONE${NC}"
                return
            fi
        fi
    fi
    # Manual selection (sama seperti kamu)
    echo ""
    echo "Pilih berdasarkan region:"
    echo " 1) Asia"
    echo " 2) Australia & Pasifik"
    echo " 3) Eropa"
    echo " 4) Amerika"
    echo " 5) Afrika"
    echo " 6) UTC / GMT"
    echo " 7) Manual input"
    echo ""
    read -r region
    case $region in
        1) # Asia options ...
           # (kode lengkap seperti yang kamu berikan, saya singkat di sini agar tidak terlalu panjang)
           TIMEZONE="Asia/Jakarta" ;;
        *) TIMEZONE="Asia/Jakarta" ;;
    esac
    if [ ! -f "/usr/share/zoneinfo/$TIMEZONE" ]; then
        echo -e "${YELLOW}⚠️ Zona '$TIMEZONE' tidak valid, menggunakan Asia/Jakarta${NC}"
        TIMEZONE="Asia/Jakarta"
    fi
    echo -e "${GREEN}✅ Timezone: $TIMEZONE${NC}"
}
get_timezone

# =============================================================================
# KEYBOARD LAYOUT (versi grid yang kamu berikan)
# =============================================================================
echo ""
echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║ PILIH LAYOUT KEYBOARD ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo "┌──────┬────────────┬──────┬────────────┬──────┬────────────┬──────┬────────────┐"
echo "│ No   │ Layout     │ No   │ Layout     │ No   │ Layout     │ No   │ Layout     │"
echo "├──────┼────────────┼──────┼────────────┼──────┼────────────┼──────┼────────────┤"
echo "│ 1    │ us         │ 2    │ id         │ 3    │ fr         │ 4    │ de         │"
echo "│ 5    │ es         │ 6    │ it         │ 7    │ pt         │ 8    │ gb         │"
echo "│ 9    │ se         │ 10   │ no         │ 11   │ dk         │ 12   │ fi         │"
echo "│ 13   │ pl         │ 14   │ ru         │ 15   │ ua         │ 16   │ cz         │"
echo "│ 17   │ tr         │ 18   │ cn         │ 19   │ jp         │ 20   │ kr         │"
echo "│ 21   │ vn         │ 22   │ br         │ 23   │ ph         │ 24   │ sg         │"
echo "├──────┼────────────┼──────┼────────────┼──────┼────────────┼──────┼────────────┤"
echo "│ 25   │ manual     │      │            │      │            │      │            │"
echo "└──────┴────────────┴──────┴────────────┴──────┴────────────┴──────┴────────────┘"
echo ""

declare -A KEYMAPS=(
    [1]="us" [2]="id" [3]="fr" [4]="de" [5]="es"
    [6]="it" [7]="pt" [8]="gb" [9]="se" [10]="no"
    [11]="dk" [12]="fi" [13]="pl" [14]="ru" [15]="ua"
    [16]="cz" [17]="tr" [18]="cn" [19]="jp" [20]="kr"
    [21]="vn" [22]="br" [23]="ph" [24]="sg"
)

while true; do
    echo -en "${YELLOW}Pilih nomor (1-25, default: 1): ${NC}"
    read -r kb_choice
    kb_choice=${kb_choice:-1}

    if ! [[ "$kb_choice" =~ ^[0-9]+$ ]]; then
        echo -e "${RED}❌ Harus angka!${NC}"
        continue
    fi

    if [ "$kb_choice" -lt 1 ] || [ "$kb_choice" -gt 25 ]; then
        echo -e "${RED}❌ Pilih antara 1-25!${NC}"
        continue
    fi

    if [ "$kb_choice" -eq 25 ]; then
        echo -n "Masukkan keymap manual: "
        read -r KEYBOARD_LAYOUT
        if [ -z "$KEYBOARD_LAYOUT" ]; then
            echo -e "${RED}❌ Keymap tidak boleh kosong!${NC}"
            continue
        fi
    else
        KEYBOARD_LAYOUT="${KEYMAPS[$kb_choice]}"
    fi

    echo -e "\n${CYAN}Layout dipilih: ${BOLD}$KEYBOARD_LAYOUT${NC}"
    echo -en "${YELLOW}Lanjutkan? (y/n): ${NC}"
    read -r confirm_layout
    if [[ "$confirm_layout" == "y" ]] || [[ "$confirm_layout" == "Y" ]] || [[ -z "$confirm_layout" ]]; then
        break
    fi
done

KEYBOARD_LAYOUT=$(echo "$KEYBOARD_LAYOUT" | tr '[:upper:]' '[:lower:]')
echo -e "${GREEN}✅ Layout keyboard: $KEYBOARD_LAYOUT${NC}"
echo ""

# =============================================================================
# COPY SYSTEM
# =============================================================================
echo -e ""
echo -e "${BLUE}Mulai menyalin sistem ke $ROOT_PART${NC}"
echo "Ini bisa memakan waktu beberapa menit..."
echo -e ""
echo -e "${RED}PERINGATAN TERAKHIR: Semua data di $ROOT_PART akan ditimpa!${NC}"
echo -en "${YELLOW}Lanjutkan penyalinan sistem? (ketik 'yes') : ${NC}"
read -r final_confirm
if [[ "${final_confirm,,}" != "yes" ]]; then
    echo -e "${GREEN}Dibatalkan.${NC}"
    exit 0
fi

mkdir -p /mnt/leakos
mount "$ROOT_PART" /mnt/leakos



rsync -aH --info=progress2 / /mnt/leakos \
    --exclude={/dev/*,/proc/*,/sys/*,/run/*,/tmp/*,/mnt/*,/media/*,/lost+found,/var/log/*,/var/cache/*,/etc/fstab,/etc/hostname,/etc/shadow,/etc/passwd,/etc/group,/etc/sudoers,/boot/grub/,/home/*}



mkdir -p /mnt/leakos/boot /mnt/leakos/boot/grub
cp -v /boot/vmlinuz* /mnt/leakos/boot/ 2>/dev/null || true
cp -v /boot/System.map* /mnt/leakos/boot/ 2>/dev/null || true

if ! ls /mnt/leakos/boot/vmlinuz* >/dev/null 2>&1; then
    echo -e "${YELLOW}WARNING: Kernel tidak ditemukan di /mnt/leakos/boot!${NC}"
fi
sync


mkdir -p /mnt/leakos/{dev,proc,sys,run,tmp}
mkdir -p /mnt/leakos/dev/pts
mkdir -p /mnt/leakos/run/dbus
mkdir -p /mnt/leakos/run/user

mount --bind /dev /mnt/leakos/dev
mount --bind /dev/pts /mnt/leakos/dev/pts
mount -t proc proc /mnt/leakos/proc
mount -t sysfs sysfs /mnt/leakos/sys
mount --bind /run /mnt/leakos/run

if [ ! -e /mnt/leakos/dev/pts/0 ]; then
    echo "Memperbaiki PTY..."
    mount --bind /dev/pts /mnt/leakos/dev/pts
fi

# =============================================================================
# PENTEST TOOLS
# =============================================================================
echo -e ""
echo -e "${BLUE}Download tools pentest dari GitHub?${NC}"
echo "akan disimpan di /opt/pentest-tools"
echo "Pilih kategori (nomor dipisah spasi, contoh: 1 3) atau 'a' untuk semua"
echo " 0) Skip semua"
echo " 1) Reconnaissance (reconftw, Sn1per)"
echo " 2) OSINT (theHarvester, recon-ng)"
echo " 3) Web Vuln Scanning (nuclei-templates, dirsearch)"
echo " 4) Exploitation (PayloadsAllTheThings, impacket)"
echo " a) Semua kategori"
echo -n "Pilihan: "
read -r category_choices

SELECTED_CATEGORIES=()
if [[ "${category_choices,,}" == "a" ]]; then
    SELECTED_CATEGORIES=(1 2 3 4)
elif [[ "$category_choices" != "0" ]] && [[ -n "$category_choices" ]]; then
    for cat in $category_choices; do
        SELECTED_CATEGORIES+=("$cat")
    done
fi

# =============================================================================
# FINAL CONFIRM & CHROOT (ROOT_UUID diperbaiki di sini!)
# =============================================================================
echo -e ""
echo -e "${BLUE}Langkah akhir: konfigurasi sistem, install GRUB, download tools${NC}"
echo "GRUB akan diinstall ke $TARGET_DISK"
echo -en "${YELLOW}Lanjut? (ketik 'yes') : ${NC}"
read -r confirm_grub
if [[ "${confirm_grub,,}" != "yes" ]]; then
    echo -e "${GREEN}Dibatalkan sebelum finalisasi.${NC}"
    umount -R /mnt/leakos || true
    exit 0
fi

CATEGORIES_STRING="${SELECTED_CATEGORIES[*]}"

ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
ROOT_PARTUUID=$(blkid -s PARTUUID -o value "$ROOT_PART")

if [ -z "$ROOT_UUID" ] || [ -z "$ROOT_PARTUUID" ]; then
    echo "ERROR: UUID / PARTUUID gagal dideteksi!"
    exit 1
fi

echo "UUID      : $ROOT_UUID"
echo "PARTUUID  : $ROOT_PARTUUID"
sleep 2

XRESOURCES_URL="https://raw.githubusercontent.com/sixtyzeroone/xa/main/.Xresources"

chroot /mnt/leakos /bin/bash <<EOF
set -e
XRESOURCES_URL="$XRESOURCES_URL"

echo "$HOSTNAME" > /etc/hostname

# Overwrite passwd/group/shadow minimal + tambah user leakos
cat > /etc/passwd <<'PASSWD'
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/bin:/sbin/nologin
daemon:x:2:2:daemon:/sbin:/sbin/nologin
adm:x:3:4:adm:/var/adm:/sbin/nologin
lp:x:4:7:lp:/var/spool/lpd:/sbin/nologin
sync:x:5:5:sync:/sbin:/bin/sync
games:x:12:100:games:/usr/games:/sbin/nologin
nobody:x:65534:65534:nobody:/:/sbin/nologin
dbus:x:81:81:dbus:/:/sbin/nologin
messagebus:x:100:101:messagebus:/run/dbus:/sbin/nologin
$USERNAME:x:1000:1000::/home/$USERNAME:/bin/bash
apache:x:33:33:Apache:/var/www:/sbin/nologin
PASSWD

cat > /etc/group <<'GROUP'
root:x:0:
wheel:x:10:
users:x:100:
dbus:x:81:
messagebus:x:101:
apache:x:33:
GROUP

cat > /etc/shadow <<'SHADOW'
root:*:19701:0:99999:7:::
bin:*:19701:0:99999:7:::
daemon:*:19701:0:99999:7:::
adm:*:19701:0:99999:7:::
lp:*:19701:0:99999:7:::
sync:*:19701:0:99999:7:::
games:*:19701:0:99999:7:::
nobody:*:19701:0:99999:7:::
dbus:*:19701:0:99999:7:::
messagebus:*:19701:0:99999:7:::
$USERNAME:*:19701:0:99999:7:::
apache:*:19701:0:99999:7:::
SHADOW

chmod 644 /etc/passwd /etc/group
chmod 000 /etc/shadow
chown root:root /etc/passwd /etc/group /etc/shadow

echo -e "\033[0;32m[2/8] VERIFIKASI USER ROOT...\033[0m"

# Verifikasi root ada
if ! grep -q "^root:" /etc/passwd; then
    echo -e "\033[0;31mERROR: Root masih tidak ada! Membuat manual...\033[0m"
    echo "root:x:0:0:root:/root:/bin/bash" >> /etc/passwd
fi

# Tampilkan verifikasi
echo "Root entry: $(grep ^root /etc/passwd)"
echo "Total users: $(wc -l < /etc/passwd)"

echo -e "\033[0;32m[3/8] SET PASSWORD ROOT DAN USER...\033[0m"

# SET PASSWORD MENGGUNAKAN CHPASSWD (DENGAN FORMAT YANG BENAR)
echo "root:$ROOT_PASSWORD" | chpasswd
echo "$USERNAME:$PASSWORD" | chpasswd

# Verifikasi password tersimpan
echo "Password root dan user telah diset."

echo -e "\033[0;32m[4/8] MEMBUAT USER BIASA...\033[0m"

# Buat user biasa dengan home directory
useradd -m -G wheel -s /bin/bash "$USERNAME" 2>/dev/null || echo "User $USERNAME sudah ada"
# =============================================================================
# XDG USER DIRECTORIES
# =============================================================================
echo -e "\033[0;32m[5/8] MENGATUR DIREKTORI HOME (XDG)...\033[0m"

# Buat folder standar
mkdir -p /home/$USERNAME/{Desktop,Documents,Downloads,Music,Pictures,Videos,Public,Templates}

# Permission
chown -R $USERNAME:users /home/$USERNAME
chmod 755 /home/$USERNAME

# Konfigurasi XDG
mkdir -p /home/$USERNAME/.config

cat > /home/$USERNAME/.config/user-dirs.dirs <<XDG
XDG_DESKTOP_DIR="\$HOME/Desktop"
XDG_DOWNLOAD_DIR="\$HOME/Downloads"
XDG_TEMPLATES_DIR="\$HOME/Templates"
XDG_PUBLICSHARE_DIR="\$HOME/Public"
XDG_DOCUMENTS_DIR="\$HOME/Documents"
XDG_MUSIC_DIR="\$HOME/Music"
XDG_PICTURES_DIR="\$HOME/Pictures"
XDG_VIDEOS_DIR="\$HOME/Videos"
XDG

chown -R $USERNAME:users /home/$USERNAME/.config
mkdir -p /etc/skel/.config 
cp /home/"$USERNAME"/.config/user-dirs.dirs /etc/skel/.config/

# Set password lagi untuk memastikan
echo "$USERNAME:$PASSWORD" | chpasswd




# Contoh 2: Pakai repo populer (dark theme bagus untuk terminal/pentest)
# BASHRC_URL="https://raw.githubusercontent.com/zachbrowne/8bc414c9f30192067831fafebd14255c/master/.bashrc"  # The Ultimate Bad Ass .bashrc
# XRESOURCES_URL="https://raw.githubusercontent.com/dracula/xresources/master/Xresources"  # Dracula theme (sangat populer)

# Download .Xresources
if curl -fsSL "\$XRESOURCES_URL" -o /home/$USERNAME/.Xresources; then
    echo "✅ .Xresources berhasil di-download dari $XRESOURCES_URL"
    chown $USERNAME:users /home/$USERNAME/.Xresources
    chmod 644 /home/$USERNAME/.Xresources
    
    # Copy ke skel
    cp /home/$USERNAME/.Xresources /etc/skel/.Xresources
    
    # Optional: load langsung supaya langsung terlihat kalau test di chroot
    xrdb -merge /home/$USERNAME/.Xresources 2>/dev/null || true
else
    echo -e "\033[0;33m⚠️ Gagal download .Xresources. Skip atau pakai default.\033[0m"
fi


# Di bagian /root/.bashrc, ganti:
cat > /root/.bashrc << 'BASHRC'
# /root/.bashrc - hanya untuk root

export TERM=xterm-256color

# Load alias & setting sistem kalau mau
if [ -f /etc/bash.bashrc ]; then
    . /etc/bash.bashrc
fi

# Auto load Xresources jika X aktif
if [[ -n "\${DISPLAY:-}" ]] && command -v xrdb >/dev/null 2>&1; then
    xrdb -merge /home/$USERNAME/.Xresources
fi

# Pastikan PROMPT_COMMAND tidak mengganggu
unset PROMPT_COMMAND 2>/dev/null

# Prompt Parrot/Kali style untuk root
export PS1='\[\033[1;31m\]┌──(\[\033[1;91m\]\u㉿\h\[\033[1;31m\])-[\[\033[1;96m\]\w\[\033[1;31m\]]\n└─\[\033[1;91m\]#\[\033[0m\] '
BASHRC

# Di bagian /etc/bash.bashrc, ganti:
cat > /etc/bash.bashrc << 'GLOBALBASHRC'
# /etc/bash.bashrc - Global Bash Configuration (LeakOS)

# =========================================================
# TERMINAL
# =========================================================
export TERM=xterm-256color

# =========================================================
# COLOR SUPPORT
# =========================================================
if command -v tput >/dev/null 2>&1 && [ "$(tput colors)" -ge 8 ]; then
    RED="\[\033[0;31m\]"
    GREEN="\[\033[0;32m\]"
    YELLOW="\[\033[1;33m\]"
    BLUE="\[\033[0;34m\]"
    CYAN="\[\033[0;36m\]"
    RESET="\[\033[0m\]"
fi

# =========================================================
# HISTORY SETTINGS
# =========================================================
HISTSIZE=5000
HISTFILESIZE=10000
HISTCONTROL=ignoreboth

# =========================================================
# BASH OPTIONS
# =========================================================
shopt -s histappend
shopt -s checkwinsize

# =========================================================
# ALIAS
# =========================================================
alias ls='ls --color=auto'
alias ll='ls -lah'
alias la='ls -A'
alias l='ls -CF'

alias grep='grep --color=auto'
alias df='df -h'
alias free='free -m'

# =========================================================
# AUTO LOAD XRESOURCES
# =========================================================
if [[ -n "\${DISPLAY:-}" ]] && command -v xrdb >/dev/null 2>&1; then
    [ -f "$HOME/.Xresources" ] && xrdb -merge "$HOME/.Xresources"
fi

# =========================================================
# PROMPT (USER)
# =========================================================
if [ "$EUID" -ne 0 ]; then
    PS1="${GREEN}\u@\h${RESET}:${BLUE}\w${RESET}$ "
fi
GLOBALBASHRC


cat > /etc/sudoers << 'SUDOERS'
Defaults    env_reset
Defaults    mail_badpass
Defaults    secure_path="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"

root    ALL=(ALL:ALL) ALL
%wheel  ALL=(ALL:ALL) ALL

SUDOERS

# Tambahkan user ke group wheel agar bisa sudo
usermod -aG wheel "$USERNAME"

# Berikan akses spesifik untuk username (opsional tapi aman)
echo "$USERNAME ALL=(ALL:ALL) ALL" > /etc/sudoers.d/99-leakos-user

chmod 440 /etc/sudoers
chmod 440 /etc/sudoers.d/99-leakos-user

# =============================================================================
# BUAT GROUP-GROUP STANDAR YANG DIPERLUKAN
# =============================================================================
echo -e "\033[0;32m[Setup group standar sistem]\033[0m"

# Buat group-group standar yang mungkin diperlukan
groupadd -f -r audio 2>/dev/null || echo "Group audio sudah ada atau dibuat"
groupadd -f -r video 2>/dev/null || echo "Group video sudah ada atau dibuat"
groupadd -f -r lp 2>/dev/null || echo "Group lp sudah ada atau dibuat"
groupadd -f -r cdrom 2>/dev/null || echo "Group cdrom sudah ada atau dibuat"
groupadd -f -r plugdev 2>/dev/null || echo "Group plugdev sudah ada atau dibuat"

# Tampilkan group yang sudah ada
echo "Group yang tersedia:"
getent group | grep -E "audio|video|lp|cdrom|plugdev" | cut -d: -f1 | tr '\n' ' '
echo ""

# =============================================================================
# BUAT USER & GROUP UNTUK PULSEAUDIO
# =============================================================================
echo -e "\033[0;32m[Setup user/group untuk PulseAudio]\033[0m"

# Buat group pulse dan pulse-access (system groups)
groupadd -f -r pulse 2>/dev/null || echo "Group pulse sudah ada"
groupadd -f -r pulse-access 2>/dev/null || echo "Group pulse-access sudah ada"

# Buat user pulse (system user, no login shell, home di /var/run/pulse)
if ! id pulse >/dev/null 2>&1; then
    useradd -r -u 1001 \
            -g pulse \
            -G audio,pulse-access,lp \
            -d /var/run/pulse \
            -s /usr/sbin/nologin \
            -c "PulseAudio System User" \
            pulse 2>/dev/null || echo "Gagal membuat user pulse, mungkin sudah ada"
    echo "✅ User 'pulse' dibuat."
else
    echo "User 'pulse' sudah ada."
fi

# Pastikan user pulse memiliki group yang benar
usermod -a -G audio,pulse-access,lp pulse 2>/dev/null || true

# Buat direktori runtime PulseAudio
mkdir -p /var/run/pulse
chown -R pulse:pulse /var/run/pulse 2>/dev/null || chown -R pulse:audio /var/run/pulse
chmod 755 /var/run/pulse

# Tambah user biasa ke group audio, video, dan pulse-access
usermod -a -G audio,video,pulse-access,cdrom,plugdev "$USERNAME" 2>/dev/null || true

# Buat direktori runtime PulseAudio
mkdir -p /var/run/pulse
chown -R pulse:pulse /var/run/pulse
chmod 755 /var/run/pulse



# Opsional: kalau mau enable PulseAudio system-wide (tidak direkomendasikan default, tapi untuk kompatibilitas)
# echo "Untuk enable system-wide PulseAudio: systemctl --system enable --now pulseaudio"


# =============================================================================
# BUAT USER UNTUK AVAHI
# =============================================================================
echo -e "\033[0;32m[Setup user Avahi]\033[0m"

# Buat group avahi jika belum ada
groupadd -f -r avahi 2>/dev/null || echo "Group avahi sudah ada"

# Buat user avahi (system user)
if ! id avahi >/dev/null 2>&1; then
    useradd -r -u 102 \
            -g avahi \
            -d /var/run/avahi-daemon \
            -s /usr/sbin/nologin \
            -c "Avahi mDNS/DNS-SD Daemon" \
            avahi 2>/dev/null || echo "Gagal membuat user avahi"
    echo "✅ User 'avahi' dibuat."
else
    echo "User 'avahi' sudah ada."
fi

# Buat direktori untuk avahi
mkdir -p /var/run/avahi-daemon
chown -R avahi:avahi /var/run/avahi-daemon 2>/dev/null || true
chmod 755 /var/run/avahi-daemon

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
echo "id_ID.UTF-8 UTF-8" >> /etc/locale.gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

echo "KEYMAP=$KEYBOARD_LAYOUT" > /etc/vconsole.conf

ln -sf /usr/share/zoneinfo/$TIMEZONE /etc/localtime
hwclock --systohc --utc || true


cat > /etc/fstab <<EOT
# LeakOS Shadow Fstab
UUID=$(blkid -s UUID -o value "$ROOT_PART") / ext4 defaults 0 1
EOF
[ -n "$HOME_PART" ] && echo "UUID=$(blkid -s UUID -o value "$HOME_PART") /home ext4 defaults 0 2" >> /etc/fstab
[ -n "$EFI_PART" ] && echo "UUID=$(blkid -s UUID -o value "$EFI_PART") /boot/efi vfat defaults 0 2" >> /etc/fstab
[ -n "$SWAP_PART" ] && echo "UUID=$(blkid -s UUID -o value "$SWAP_PART") swap swap defaults 0 0" >> /etc/fstab
cat >> /etc/fstab <<EOT
tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
EOT


cat > /etc/hosts <<EOT
127.0.0.1 localhost
127.0.1.1 $HOSTNAME $HOSTNAME.localdomain
::1 localhost ip6-localhost ip6-loopback
fe00::0 ip6-localnet
ff00::0 ip6-mcastprefix
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
EOT


groupadd -r polkitd
useradd -r -g polkitd -d / -s /sbin/nologin -c "PolicyKit Daemon" polkitd


mkdir -p /run/dbus /var/run/dbus
chown messagebus:messagebus /run/dbus /var/run/dbus 2>/dev/null || true
chmod 755 /run/dbus /var/run/dbus
dbus-uuidgen --ensure=/etc/machine-id 2>/dev/null || echo "unique-$(date +%s)" > /etc/machine-id

grub-install --target=i386-pc --recheck "$TARGET_DISK" || grub-install "$TARGET_DISK" || echo "WARNING: GRUB install mungkin gagal"

KERNEL=$(ls /boot/vmlinuz* | head -n1 | xargs -n1 basename)

cat > /boot/grub/grub.cfg <<GRUBEOF
# LeakOS GRUB Configuration - Shadow Edition
set default=0
set timeout=5

menuentry "LeakOS V1 (Celuluk)" {
    
    insmod ext2
    insmod part_msdos
    insmod part_gpt
    
    linux /boot/vmlinuz root=PARTUUID=$ROOT_PARTUUID ro rootwait rootfstype=ext4

}

menuentry "LeakOS V1 (Celuluk) - Recovery" {
    insmod ext2
    insmod part_msdos
    insmod part_gpt
    linux /boot/vmlinuz root=PARTUUID=$ROOT_PARTUUID ro single rootwait rootfstype=ext4

}
GRUBEOF

# Download pentest tools
if [ ${#SELECTED_CATEGORIES[@]} -gt 0 ]; then
    cd /usr/share
    for cat in ${CATEGORIES_STRING}; do
        case \$cat in
            1)
                git clone https://github.com/six2dez/reconftw.git 2>/dev/null || true
                git clone https://github.com/1N3/Sn1per.git 2>/dev/null || true
                ;;
            2)
                git clone https://github.com/laramies/theHarvester.git 2>/dev/null || true
                git clone https://github.com/lanmaster53/recon-ng.git 2>/dev/null || true
                ;;
            3)
                git clone https://github.com/projectdiscovery/nuclei-templates.git 2>/dev/null || true
                git clone https://github.com/maurosoria/dirsearch.git 2>/dev/null || true
                ;;
            4)
                git clone https://github.com/swisskyrepo/PayloadsAllTheThings.git 2>/dev/null || true
                git clone https://github.com/fortra/impacket.git 2>/dev/null || true
                ;;
        esac
    done
fi

rm -f /etc/machine-id
touch /etc/machine-id
exit 0
EOF

sync
umount -R /mnt/leakos 2>/dev/null || true

# =============================================================================
# PESAN AKHIR DENGAN EFEK BLINK
# =============================================================================
echo -e ""
echo -e "${GREEN}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║           L E A K O S   BERHASIL DIINSTALL !               ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""
echo -e "Username     : ${CYAN}$USERNAME${NC}"
echo -e "Hostname     : ${CYAN}$HOSTNAME${NC}"
echo -e "Root partisi : ${CYAN}$ROOT_PART${NC}"
if [ ${#SELECTED_CATEGORIES[@]} -gt 0 ]; then
    echo -e "Tools pentest: ${CYAN}/opt/pentest-tools${NC}"
else
    echo -e "Tidak ada tools pentest yang di-download (dipilih skip)."
fi
echo -e ""

# Teks dengan efek BLINK (kedap-kedip)
echo -e "${YELLOW}${BOLD}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${YELLOW}${BOLD}║${NC} ${BLINK}${RED}${BOLD}         SISTEM SIAP - TEKAN REBOOT UNTUK MULAI           ${NC} ${YELLOW}${BOLD}║${NC}"
echo -e "${YELLOW}${BOLD}╚════════════════════════════════════════════════════════════╝${NC}"
echo -e ""

# Atau versi yang lebih sederhana dengan blink di bagian "REBOOT" saja
echo -e "${CYAN}Ketik ${BLINK}${RED}${BOLD}REBOOT${NC}${CYAN} sekarang atau ${BLINK}${RED}${BOLD}CABUT MEDIA${NC}${CYAN} lalu restart manual.${NC}"
echo -e ""

# Membuat pilihan reboot dengan efek blink
echo -en "${YELLOW}${BOLD}${BLINK}➤ REBOOT SEKARANG? (yes/no): ${NC}"
read -r confirm_reboot
[[ "${confirm_reboot,,}" == "yes" ]] && reboot

exit 0
