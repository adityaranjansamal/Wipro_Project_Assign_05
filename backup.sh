#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

timestamp() { date +'%Y-%m-%d_%H-%M-%S'; }
LOGFILE="$LOG_DIR/backup-$(timestamp).log"

# Detect package manager
detect_pkg_manager() {
    for pm in apt dnf zypper pacman; do
        command -v "$pm" >/dev/null 2>&1 && { echo "$pm"; return; }
    done
    echo "unknown"
}

# Dependency check + installation
check_dependencies() {
    local deps=("rsync" "dialog" "tee")
    local missing=()
    for dep in "${deps[@]}"; do
        command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
    done
    (( ${#missing[@]} == 0 )) && return

    echo "Missing dependencies: ${missing[*]}"
    read -rp "Install missing dependencies (Y/N)? " ans
    [[ ! "$ans" =~ ^[Yy] ]] && { echo "Dependencies not satisfied. Aborting."; exit 1; }

    local pmgr; pmgr=$(detect_pkg_manager)
    case "$pmgr" in
        apt)     sudo apt update && sudo apt install -y "${missing[@]}" ;;
        dnf)     sudo dnf install -y "${missing[@]}" ;;
        zypper)  sudo zypper install -y "${missing[@]}" ;;
        pacman)  sudo pacman -Sy --noconfirm "${missing[@]}" ;;
        *)       echo "Unsupported package manager. Install manually."; exit 1 ;;
    esac
}

# Utilities
expand_path() { eval echo "$1"; }
log() { echo "[$(timestamp)] $*" | tee -a "$LOGFILE"; }

ensure_destination() {
    local dest="$1"
    mkdir -p "$dest" 2>/dev/null || { log "Cannot create destination $dest"; return 1; }
    touch "$dest/.test_$$" 2>/dev/null || { log "Destination not writable: $dest"; return 1; }
    rm -f "$dest/.test_$$"; return 0
}

# Free-space check for destination
check_space() {
    local src="$1" dest="$2"
    local src_kb dest_kb
    src_kb=$(du -sk --exclude="/proc" --exclude="/sys" --exclude="/dev" "$src" 2>/dev/null | awk '{sum+=$1} END{print sum}')
    dest_kb=$(df -k --output=avail "$dest" 2>/dev/null | tail -1)
    [[ -z "$src_kb" || -z "$dest_kb" ]] && { log "Cannot determine space."; return 0; }
    (( dest_kb < src_kb )) && {
        dialog --msgbox "Not enough space!\nRequired: $(awk "BEGIN{printf \"%.2f\",$src_kb/1048576}") GB\nAvailable: $(awk "BEGIN{printf \"%.2f\",$dest_kb/1048576}") GB" 9 55
        log "Insufficient space."; return 1; }
    return 0
}

# Rsync progress bar
run_with_progress() {
    local cmd="$1"
    log "Executing: $cmd"
    ( eval "$cmd" 2>&1 | while IFS= read -r line; do
          echo "$line" >> "$LOGFILE"
          if [[ "$line" =~ ([0-9]{1,3})% ]]; then echo "${BASH_REMATCH[1]}"; fi
      done ) | dialog --title "Backup Progress" --gauge "Running backup..." 10 70 0
}

# Directory selector using dialog for destination
select_directory() {
    local start_path="${1:-$HOME}"
    local choice
    choice=$(dialog --clear --backtitle "Select Destination" \
             --title "Destination Browser" \
             --dselect "$start_path/" 15 70 3>&1 1>&2 2>&3) || return 1
    echo "$choice"
}

# Backup types
system_backup() {
    [[ $EUID -ne 0 ]] && dialog --msgbox "Run as root for full system backup.\nNon-root will skip some files." 8 60
    local dest; dest=$(select_directory "/mnt") || { dialog --msgbox "Cancelled." 6 40; return; }
    dest=$(expand_path "$dest")
    ensure_destination "$dest" || { dialog --msgbox "Invalid destination." 6 40; return; }
    check_space "/" "$dest" || return

    local subdir="$dest/system_backup_$(timestamp)"; mkdir -p "$subdir"
    local excludes=(--exclude=/home/* --exclude=/proc/* --exclude=/sys/* --exclude=/dev/* --exclude=/run/* --exclude=/tmp/* --exclude=/mnt/* --exclude=/media/* --exclude=/lost+found)
    local cmd="rsync -aAXHv --delete --info=progress2 --progress ${excludes[*]} / \"$subdir\""
    run_with_progress "$cmd"
    dialog --msgbox "System backup complete!\nLogs: $LOGFILE" 8 50
}

home_backup() {
    local dest; dest=$(select_directory "/mnt") || { dialog --msgbox "Cancelled." 6 40; return; }
    dest=$(expand_path "$dest")
    ensure_destination "$dest" || { dialog --msgbox "Invalid destination." 6 40; return; }
    check_space "/home" "$dest" || return

    local subdir="$dest/home_backup_$(timestamp)"; mkdir -p "$subdir"
    local cmd="rsync -aAXHv --delete --info=progress2 --progress /home/ \"$subdir\""
    run_with_progress "$cmd"
    dialog --msgbox "Home backup complete!\nLogs: $LOGFILE" 8 50
}

# Menu Selector
main_menu() {
    while true; do
        local opt
        opt=$(dialog --clear --backtitle "Backup Utility" \
             --title "Main Menu" \
             --menu "Choose backup type:" 15 60 4 \
             1 "System Backup (Excludes /home)" \
             2 "/home Backup" \
             3 "Exit" 3>&1 1>&2 2>&3) || { clear; break; }
        case "$opt" in
            1) system_backup ;;
            2) home_backup ;;
            3) clear; break ;;
        esac
    done
}

# Main
check_dependencies
log "=== Backup run started ==="
main_menu
log "=== Backup run ended ==="
exit 0
