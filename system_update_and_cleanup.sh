#!/usr/bin/env bash
set -euo pipefail
# System Update and Cleanup Interface

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

timestamp() { date +'%Y-%m-%d_%H-%M-%S'; }
LOGFILE="$LOG_DIR/sysupdate-$(timestamp).log"

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "This script requires admin privileges."
    echo "Re-run using: sudo $0"
    exit 1
fi

# Logs
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }
msgbox() { dialog --msgbox "$1" 8 60; }
expand_path() { eval echo "$1"; }

# Detect distro
detect_pkg_manager() {
    if command -v apt-get >/dev/null 2>&1; then echo "apt"
    elif command -v dnf >/dev/null 2>&1; then echo "dnf"
    elif command -v zypper >/dev/null 2>&1; then echo "zypper"
    elif command -v pacman >/dev/null 2>&1; then echo "pacman"
    else echo "unknown"; fi
}

# Cleanup
system_cleanup() {
    read -rp "Clean leftover packages and free disk space? [Y/N]: " c
    [[ ! "$c" =~ ^[Yy]$ ]] && { log "Cleanup skipped."; return; }
    case "$1" in
        apt)
            log "Cleaning apt system..."
            { apt autoremove -y && apt autoclean -y && apt clean -y && journalctl --vacuum-time=10d; } \
                >>"$LOGFILE" 2>&1 ;;
        dnf)
            log "Cleaning dnf system..."
            { dnf autoremove -y && dnf clean all && journalctl --vacuum-time=10d; } \
                >>"$LOGFILE" 2>&1 ;;
        zypper)
            log "Cleaning zypper system..."
            { zypper clean --all && journalctl --vacuum-time=10d; } \
                >>"$LOGFILE" 2>&1 ;;
        pacman)
            log "Cleaning pacman system..."
            { paccache -r && pacman -Sc --noconfirm && journalctl --vacuum-time=10d; } \
                >>"$LOGFILE" 2>&1 ;;
    esac
    log "Cleanup done."
}

# Updaters
update_debian() {
    local version
    version=$(grep -i "ubuntu" /etc/os-release 2>/dev/null | grep -oP '[0-9]{2}\.[0-9]{2}' || echo "0")
    if command -v nala >/dev/null 2>&1; then
        log "Using Nala for updates."
        { nala update && nala upgrade; } >>"$LOGFILE" 2>&1
    else
        if [[ $(echo "$version >= 22.04" | bc -l) -eq 1 ]]; then
            read -rp "Install Nala (recommended)? [Y/N]: " ans
            if [[ "$ans" =~ ^[Yy]$ ]]; then
                { apt update && apt install -y nala && nala update && nala upgrade; } >>"$LOGFILE" 2>&1
                return
            fi
        fi
        log "Using apt for updates."
        { apt update -y && apt upgrade -y && apt dist-upgrade -y; } >>"$LOGFILE" 2>&1
    fi
}

update_fedora() {
    log "Updating via DNF..."
    { dnf upgrade --refresh -y; } >>"$LOGFILE" 2>&1
}

update_opensuse() {
    log "Updating via Zypper..."
    { zypper refresh && zypper update -y; } >>"$LOGFILE" 2>&1
}

update_arch() {
    if command -v yay >/dev/null 2>&1; then
        log "Using yay for updates."
        { yay -Syu --noconfirm; } >>"$LOGFILE" 2>&1
    else
        read -rp "Install yay (recommended)? [Y/N]: " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            { pacman -S --noconfirm git base-devel && cd /tmp && git clone https://aur.archlinux.org/yay.git \
              && cd yay && makepkg -si --noconfirm && yay -Syu --noconfirm; } >>"$LOGFILE" 2>&1
        else
            log "Using pacman fallback."
            { pacman -Syu --noconfirm; } >>"$LOGFILE" 2>&1
        fi
    fi
}

# Snap & Flatpak updaters
update_snap() {
    if ! command -v snap >/dev/null 2>&1; then msgbox "Snap not installed."; return; fi
    log "Updating Snap packages..."
    { snap refresh; } >>"$LOGFILE" 2>&1
    msgbox "Snap packages updated successfully!"
}

update_flatpak() {
    if ! command -v flatpak >/dev/null 2>&1; then msgbox "Flatpak not installed."; return; fi
    log "Updating Flatpak packages..."
    { flatpak update -y; } >>"$LOGFILE" 2>&1
    msgbox "Flatpak packages updated successfully!"
}

# Full system update
full_system_update() {
    local pkg_mgr; pkg_mgr=$(detect_pkg_manager)
    if [[ "$pkg_mgr" == "unknown" ]]; then msgbox "Unsupported distribution!"; return; fi

    dialog --infobox "Running full system update using $pkg_mgr..." 5 60
    log "======== SYSTEM UPDATE START ($pkg_mgr) ========"

    case "$pkg_mgr" in
        apt) update_debian ;;
        dnf) update_fedora ;;
        zypper) update_opensuse ;;
        pacman) update_arch ;;
    esac

    log "======== CLEANUP PHASE ========"
    system_cleanup "$pkg_mgr"

    log "======== SYSTEM UPDATE END ========"
    msgbox "System update completed successfully!\n\nLog file: $LOGFILE"
}

# Menu
main_menu() {
    while true; do
        local choice
        choice=$(dialog --clear --backtitle "System Update Utility" \
            --title "Main Menu" \
            --menu "Select an operation:" 15 60 6 \
            1 "Full system update + cleanup" \
            2 "Update Snap packages" \
            3 "Update Flatpak packages" \
            4 "Exit" 3>&1 1>&2 2>&3) || { clear; break; }
        clear
        case "$choice" in
            1) full_system_update ;;
            2) update_snap ;;
            3) update_flatpak ;;
            4) clear; log "Exited successfully."; break ;;
        esac
    done
}

# Starter
log "===== Script started ====="
main_menu
log "===== Script ended ====="
exit 0