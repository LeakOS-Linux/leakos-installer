#!/bin/bash
# ========================================================
# Script: LeakOS-Mode Undercover Switcher (Optimized)
# ========================================================

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Konfigurasi Tema
WINDOWS_WM_THEME="Windows"
DEFAULT_WM_THEME="Default"
BACKUP_DIR="/root/leakos_undercover_backup" # Folder backup tetap (Static)
WINDOWS_WALLPAPER="/usr/share/backgrounds/leak/Windows-10.jpg"
JETBLUE_WALLPAPER="/usr/share/backgrounds/leak/leak.png"

check_root() {
    if [[ $EUID -ne 0 ]]; then
        echo -e "${RED}[!] Script ini harus dijalankan sebagai root${NC}"
        exit 1
    fi
}

restart_panel() {
    echo -e "${BLUE}[*] Menyegarkan Panel XFCE...${NC}"
    pkill xfce4-panel
    sleep 1
    (xfce4-panel > /dev/null 2>&1 &)
}

do_backup() {
    # Backup ke folder tunggal (menimpa yang lama)
    echo -e "${BLUE}[*] Memperbarui backup di: $BACKUP_DIR${NC}"
    mkdir -p "$BACKUP_DIR"
    
    # Simpan konfigurasi asli ke file teks
    xfconf-query -c xsettings -p /Net/ThemeName > "$BACKUP_DIR/theme_name.txt" 2>/dev/null
    xfconf-query -c xsettings -p /Net/IconThemeName > "$BACKUP_DIR/icon_name.txt" 2>/dev/null
    xfconf-query -c xfwm4 -p /general/theme > "$BACKUP_DIR/wm_theme.txt" 2>/dev/null
    
    # Backup file panel jika ada
    [[ -f /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml ]] && \
    cp /etc/xdg/xfce4/xfconf/xfce-perchannel-xml/xfce4-panel.xml "$BACKUP_DIR/"
}

setup_terminal() {
    local mode="$1"
    
    for user_home in /home/*; do
        local username=$(basename "$user_home")
        local bashrc="$user_home/.bashrc"
        local term_dir="$user_home/.config/xfce4/terminal"
        
        if [[ -d "$user_home" ]]; then
            if [[ "$mode" == "windows" ]]; then
                echo -e "${BLUE}[*] Mengubah Terminal menjadi CMD untuk $username...${NC}"
                
                # 1. Terminal Visual (CMD Look)
                mkdir -p "$term_dir"
                cat > "$term_dir/terminalrc" << EOF
[Configuration]
FontName=Consolas 11
ColorForeground=#C0C0C0
ColorBackground=#000000
ColorCursor=#FFFFFF
MiscAlwaysShowTabs=FALSE
MiscBell=FALSE
MiscBordersDefault=FALSE
MiscCursorBlinks=TRUE
MiscCursorShape=TERMINAL_CURSOR_SHAPE_BLOCK
MiscMenubarDefault=FALSE
MiscToolbarDefault=FALSE
EOF

                # 2. Bash Prompt & Banner Spoofing
                sed -i '/# CMD_STYLE_START/,/# CMD_STYLE_END/d' "$bashrc"
                cat >> "$bashrc" << 'EOF'
# CMD_STYLE_START
clear
echo "Microsoft Windows [Version 10.0.16299.192]"
echo "(c) 2017 Microsoft Corporation. All rights reserved."
echo ""
export PS1='C:\\Users\\$(whoami)> '
alias cls='clear && echo "Microsoft Windows [Version 10.0.16299.192]" && echo "(c) 2017 Microsoft Corporation. All rights reserved." && echo ""'
alias dir='ls -lah --group-directories-first'
# CMD_STYLE_END
EOF
            else
                echo -e "${YELLOW}[*] Mengembalikan Terminal ke standar $username...${NC}"
                rm "$term_dir/terminalrc" 2>/dev/null
                sed -i '/# CMD_STYLE_START/,/# CMD_STYLE_END/d' "$bashrc"
            fi
            chown -R "$username":"$username" "$term_dir" "$bashrc" 2>/dev/null
        fi
    done
}

update_whisker_icon() {
    local icon_path="$1"
    local ids=$(xfconf-query -c xfce4-panel -p /plugins -l | grep "plugin-" | cut -d'/' -f3 | sort -u)
    for id in $ids; do
        type=$(xfconf-query -c xfce4-panel -p /plugins/$id -v 2>/dev/null)
        if [[ "$type" == *"whiskermenu"* ]]; then
            xfconf-query -c xfce4-panel -p /plugins/$id/button-icon -n -t string -s "$icon_path"
            xfconf-query -c xfce4-panel -p /plugins/$id/show-button-title -n -t bool -s false
        fi
    done
}

enable_undercover() {
    check_root
    if [[ -d "/usr/share/themes/Windows" ]]; then
        do_backup
        echo -e "${BLUE}[*] Menerapkan UI Windows 10...${NC}"
        
        # GTK & Icon
        xfconf-query -c xsettings -p /Net/ThemeName -s "Windows" 2>/dev/null
        xfconf-query -c xsettings -p /Net/IconThemeName -s "Windows" 2>/dev/null
        
        # Window Manager Theme
        xfconf-query -c xfwm4 -p /general/theme -s "$WINDOWS_WM_THEME" 2>/dev/null
        
        # Panel & Wallpaper
        xfconf-query -c xfce4-panel -p /panels/panel-1/position -s "p=8;x=0;y=0" 2>/dev/null
        xfconf-query -c xfce4-panel -p /panels/panel-1/size -s 37 2>/dev/null
        update_whisker_icon "/usr/share/icons/Windows/start-menu.png"
        
        setup_terminal "windows"
        
        # Set Wallpaper
        if [[ -f "$WINDOWS_WALLPAPER" ]]; then
            xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$WINDOWS_WALLPAPER" 2>/dev/null
        fi
        
        restart_panel
        echo -e "${GREEN}[✓] Mode Undercover Aktif!${NC}"
    else
        echo -e "${RED}[!] Tema Windows tidak ditemukan di /usr/share/themes/Windows!${NC}"
    fi
}

disable_undercover() {
    check_root
    echo -e "${YELLOW}[+] Mengembalikan ke gaya LeakOS...${NC}"
    
    # Ambil nilai dari backup jika folder ada
    if [[ -d "$BACKUP_DIR" ]]; then
        ORIG_THEME=$(cat "$BACKUP_DIR/theme_name.txt" 2>/dev/null || echo "Jetblue")
        ORIG_ICON=$(cat "$BACKUP_DIR/icon_name.txt" 2>/dev/null || echo "Treepata")
        ORIG_WM=$(cat "$BACKUP_DIR/wm_theme.txt" 2>/dev/null || echo "$DEFAULT_WM_THEME")
        
        xfconf-query -c xsettings -p /Net/ThemeName -s "$ORIG_THEME" 2>/dev/null
        xfconf-query -c xsettings -p /Net/IconThemeName -s "$ORIG_ICON" 2>/dev/null
        xfconf-query -c xfwm4 -p /general/theme -s "$ORIG_WM" 2>/dev/null
    fi

    xfconf-query -c xfce4-panel -p /panels/panel-1/position -s "p=6;x=0;y=0" 2>/dev/null
    setup_terminal "restore"
    update_whisker_icon "/usr/share/icons/leakos-icon/apps/48/wine.png"
    
    if [[ -f "$JETBLUE_WALLPAPER" ]]; then
        xfconf-query -c xfce4-desktop -p /backdrop/screen0/monitor0/workspace0/last-image -s "$JETBLUE_WALLPAPER" 2>/dev/null
    fi
    
    restart_panel
    echo -e "${GREEN}[✓] Kembali ke LeakOS Style.${NC}"
}

case "$1" in
    --enable|-e)  enable_undercover ;;
    --disable|-d) disable_undercover ;;
    *) echo "Usage: sudo $0 --enable | --disable" ;;
esac
