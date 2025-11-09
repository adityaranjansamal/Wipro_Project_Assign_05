#!/usr/bin/env bash
set -euo pipefail
# Log Monitoring Utility

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
LOG_DIR="$SCRIPT_DIR/logs"
mkdir -p "$LOG_DIR"

timestamp() { date +'%Y-%m-%d_%H-%M-%S'; }
LOGFILE="$LOG_DIR/logmonitor-$(timestamp).log"

# Root check
if [[ $EUID -ne 0 ]]; then
    echo "This script needs admin privileges to read system logs."
    echo "Please re-run using: sudo $0"
    exit 1
fi

# Utility helpers
log() { echo "[$(date +'%Y-%m-%d %H:%M:%S')] $*" | tee -a "$LOGFILE"; }
msgbox() { dialog --msgbox "$1" 8 60; }

# Default monitored logs & patterns
MONITOR_LOGS=(
    "/var/log/syslog"
    "/var/log/auth.log"
    "/var/log/kern.log"
)
PATTERNS="error|fail|failed|denied|critical|panic|segfault|unauthorized|refused"

# Checking availability of log files
for f in "${MONITOR_LOGS[@]}"; do
    [[ -f "$f" ]] || log "Skipping missing log file: $f"
done

# Tail + alert loop
monitor_logs() {
    local logfile
    local monitored=()
    for logfile in "${MONITOR_LOGS[@]}"; do
        [[ -r "$logfile" ]] && monitored+=("$logfile")
    done
    if (( ${#monitored[@]} == 0 )); then
        msgbox "No readable log files found."
        return
    fi

    log "===== Log Monitor Started ====="
    log "Monitoring: ${monitored[*]}"
    log "Patterns: $PATTERNS"

    dialog --infobox "Monitoring logs... Press Ctrl+C in terminal to stop." 6 60

    # Tail and grep continuously
    tail -Fn0 "${monitored[@]}" 2>/dev/null | \
    while read -r line; do
        if echo "$line" | grep -Eiq "$PATTERNS"; then
            alert="[$(date +'%H:%M:%S')] ALERT → $line"
            echo "$alert" | tee -a "$LOGFILE"
            # Alert via desktop notification interface
            if command -v notify-send >/dev/null 2>&1; then
                notify-send "Log Monitor Alert" "$line"
            fi
        fi
    done
}

# Menu
main_menu() {
    while true; do
        local choice
        choice=$(dialog --clear --backtitle "Log Monitoring Utility" \
            --title "Main Menu" \
            --menu "Choose an action:" 15 60 5 \
            1 "Start Log Monitoring" \
            2 "View Last Alerts" \
            3 "Exit" 3>&1 1>&2 2>&3) || { clear; break; }

        clear
        case "$choice" in
            1) monitor_logs ;;
            2)
                if [[ -f "$LOGFILE" ]]; then
                    dialog --textbox "$LOGFILE" 20 80
                else
                    msgbox "No alerts logged yet."
                fi
                ;;
            3) clear; log "Exited successfully."; break ;;
        esac
    done
}

# Main
log "===== Script started ====="
main_menu
log "===== Script ended ====="
exit 0
