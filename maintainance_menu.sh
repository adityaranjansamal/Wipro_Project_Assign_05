#!/usr/bin/env bash
set -euo pipefail

# AUTHOR: ADITYA RANJAN SAMAL
# REGD NO: 2241019245
# BATCH : WIPRO BATCH 2
# TOOLS USED: Shell Scripting, Linux Mint (Ubuntu/Debian [apt]), Ncurses UI

#  Linux Maintenance Suite

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

# Detect the real user’s home, even under sudo
REAL_USER_HOME=$(getent passwd "${SUDO_USER:-$USER}" | cut -d: -f6)
CONF_FILE="$REAL_USER_HOME/.maintsuite.conf"

timestamp() { date +'%Y-%m-%d_%H-%M-%S'; }
MASTER_LOG="$LOG_DIR/suite-$(timestamp).log"

# Root Check
if [[ $EUID -ne 0 ]]; then
    echo "This suite requires admin privileges."
    echo "Re-run using: sudo $0"
    exit 1
fi

# Logging Utility
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$MASTER_LOG"; }
msgbox() { dialog --msgbox "$1" 10 70; }

# Dependency check
deps=(dialog rsync util-linux coreutils grep bc vim nano script ncurses-bin ncurses-base libncursesw6)
missing=()
for dep in "${deps[@]}"; do
    command -v "$dep" >/dev/null 2>&1 || missing+=("$dep")
done
if (( ${#missing[@]} )); then
    echo "Missing dependencies: ${missing[*]}"
    read -rp "Install them now? (Y/N): " yn
    if [[ "$yn" =~ ^[Yy]$ ]]; then
        if command -v apt >/dev/null 2>&1; then
            apt update && apt install -y "${missing[@]}"
        elif command -v dnf >/dev/null 2>&1; then
            dnf install -y "${missing[@]}"
        elif command -v zypper >/dev/null 2>&1; then
            zypper install -y "${missing[@]}"
        elif command -v pacman >/dev/null 2>&1; then
            pacman -Sy --noconfirm "${missing[@]}"
        else
            echo "Unsupported package manager."
            exit 1
        fi
    else
        echo "Dependencies not satisfied. Aborting."
        exit 1
    fi
fi

# Script paths
BACKUP_SCRIPT="$SCRIPT_DIR/backup.sh"
UPDATE_SCRIPT="$SCRIPT_DIR/system_update_and_cleanup.sh"
LOGMON_SCRIPT="$SCRIPT_DIR/log_monitor.sh"
for f in "$BACKUP_SCRIPT" "$UPDATE_SCRIPT" "$LOGMON_SCRIPT"; do
    [[ -f "$f" ]] || { echo "Missing: $f"; exit 1; }
    chmod +x "$f" 2>/dev/null || true
done

# Terminal cleanup
_restore_terminal() { stty sane 2>/dev/null || true; reset 2>/dev/null || true; clear; }
trap '_restore_terminal' EXIT
trap '_restore_terminal; exit 1' INT TERM

# Locate real editor
find_editor_binary() {
    local cmd="$1"
    local path
    path=$(command -v "$cmd" 2>/dev/null || true)
    if [[ -z "$path" ]]; then
        for p in /usr/bin /usr/local/bin /bin; do
            [[ -x "$p/$cmd" ]] && { path="$p/$cmd"; break; }
        done
    fi
    echo "$path"
}

# Persistent editor configuration
get_editor() {
    local editor=""
    if [[ -f "$CONF_FILE" ]]; then
        editor=$(grep "^editor=" "$CONF_FILE" | cut -d'=' -f2- || true)
    fi
    if [[ -z "$editor" ]]; then
        local choice
        choice=$(dialog --clear --backtitle "Maintenance Suite" \
            --title "Select Text Editor" \
            --menu "Choose editor to view logs:" 15 60 6 \
            1 "nano" \
            2 "vim" \
            3 "less" \
            4 "gedit (GUI)" \
            5 "other (manual input)" 3>&1 1>&2 2>&3) || return 1

        case "$choice" in
            1) editor="nano" ;;
            2) editor="vim" ;;
            3) editor="less" ;;
            4) editor="gedit" ;;
            5)
                editor=$(dialog --inputbox "Enter editor command (e.g. micro, nvim):" 8 60 3>&1 1>&2 2>&3) || return 1
                ;;
        esac
        echo "editor=$editor" >"$CONF_FILE"
        chown "${SUDO_USER:-$USER}":"${SUDO_USER:-$USER}" "$CONF_FILE" 2>/dev/null || true
        log "Saved preferred editor: $editor"
    fi
    echo "$editor"
}

# Run module in PTY
run_module() {
    local script_path="$1"
    local label="$2"
    local tmp_capture
    tmp_capture="$(mktemp --tmpdir "suite_${label// /_}_XXXXXX.log")"

    log "=== Launching: $label ==="
    dialog --clear
    clear
    echo "Running ${label}..."
    echo "Captured output → $tmp_capture"
    echo "Press Ctrl+C to cancel."
    sleep 0.4

    script -q -c "bash '$script_path'" "$tmp_capture" || echo "(exit code non-zero)"

    {
        echo "----- Begin captured output for: $label ($(date +'%F %T')) -----"
        cat "$tmp_capture"
        echo "----- End captured output for: $label ($(date +'%F %T')) -----"
    } >>"$MASTER_LOG"

    rm -f "$tmp_capture"
    _restore_terminal
    sleep 0.1
    dialog --title "${label} Finished" --msgbox "The ${label} completed.\nOutput appended to suite log:\n$MASTER_LOG" 10 70
    log "=== Completed: $label ==="
}

launch_backup()   { run_module "$BACKUP_SCRIPT" "Backup Utility"; }
launch_updater()  { run_module "$UPDATE_SCRIPT" "System Update & Cleanup"; }
launch_logmon()   { run_module "$LOGMON_SCRIPT" "Log Monitor"; }

# View log using chosen editor
view_master_log() {
    if [[ ! -f "$MASTER_LOG" ]]; then
        msgbox "No suite log found."
        return
    fi

    local editor selected_bin
    editor=$(get_editor) || return
    selected_bin=$(find_editor_binary "$editor")

    if [[ -z "$selected_bin" ]]; then
        msgbox "Editor '$editor' not found in PATH.\nReconfigure your editor."
        rm -f "$CONF_FILE"
        return
    fi

    _restore_terminal
    echo "Opening suite log with: $selected_bin"
    sleep 0.3
    sudo -u "${SUDO_USER:-$USER}" "$selected_bin" "$MASTER_LOG"
    _restore_terminal
}

# About
about_suite() {
    dialog --msgbox "Linux Maintenance Suite\n\nModules:\n - Backup Utility\n - System Update & Cleanup\n - Log Monitor\n\nLogs stored in:\n$LOG_DIR\n\nEditor config: $CONF_FILE" 14 70
}

# Main Menu
main_menu() {
    while true; do
        choice=$(dialog --clear --backtitle "Linux Maintenance Suite" \
            --title "Main Menu" \
            --menu "Choose operation:" 20 76 8 \
            1 "System Backup Utility" \
            2 "System Update & Cleanup" \
            3 "Log Monitoring Tool" \
            4 "View Last Suite Log (open in editor)" \
            5 "About" \
            6 "Exit" 3>&1 1>&2 2>&3) || { clear; break; }

        clear
        case "$choice" in
            1) launch_backup ;;
            2) launch_updater ;;
            3) launch_logmon ;;
            4) view_master_log ;;
            5) about_suite ;;
            6) clear; log "Exited successfully."; break ;;
        esac
    done
}

# Start
log "===== Maintenance Suite Started ====="
main_menu
log "===== Maintenance Suite Ended ====="
_restore_terminal
exit 0
