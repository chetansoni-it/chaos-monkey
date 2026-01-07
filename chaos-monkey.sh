#!/bin/bash

# --- CONFIGURATION ---
SERVICE_NAME="systemdlog"
SCRIPT_PATH=$(readlink -f "$0")
# Changed log location to /tmp so any user can write to it without permission issues
LOG_FILE="/tmp/systemd_log.log"
CURRENT_USER=$(whoami)

# TARGETS: ("*") or ("nginx" "mysql")
TARGET_SERVICES=("*") 

MIN_SLEEP=10  
MAX_SLEEP=30 
CPU_LOAD_DURATION=15 

# --- SYSTEMD INSTALLATION LOGIC ---
install_service() {
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo "Configuring systemd service for user: $CURRENT_USER"
        # We create the service as root, but it runs the script as your user
        sudo cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=systemd log Resilience Simulator
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH --run-logic
Restart=always
User=$CURRENT_USER
Group=$(id -gn)
# Environment variable to ensure log path is clean
Environment=LOG_PATH=$LOG_FILE

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl start $SERVICE_NAME
        echo "Service installed. Monitor logs with: tail -f $LOG_FILE"
        exit 0
    fi
}

# Auto-install if not running as logic
if [[ "$1" != "--run-logic" ]]; then
    install_service
    exit 0
fi

# --- CHAOS LOGIC ---
# Ensure log file exists and we can write to it
touch "$LOG_FILE"
echo "--- Chaos Monkey started at $(date) ---" >> "$LOG_FILE"

while true; do
    # Random sleep
    SLEEP_TIME=$(( ( RANDOM % (MAX_SLEEP - MIN_SLEEP) ) + MIN_SLEEP ))
    sleep "$SLEEP_TIME"

    ACTION=$(( RANDOM % 2 ))

    if [ $ACTION -eq 0 ]; then
        # ACTION: KILL SERVICE
        FINAL_TARGET=""

        if [[ "${TARGET_SERVICES[0]}" == "*" ]]; then
            # Filter: exclude this script, ssh, and critical systemd dbus/journal components
            ALL_SERVICES=($(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}' | grep -vE "($SERVICE_NAME|ssh|sshd|systemd-journald|dbus)"))
            if [ ${#ALL_SERVICES[@]} -gt 0 ]; then
                FINAL_TARGET=${ALL_SERVICES[$RANDOM % ${#ALL_SERVICES[@]}]}
            fi
        else
            FINAL_TARGET=${TARGET_SERVICES[$RANDOM % ${#TARGET_SERVICES[@]}]}
        fi

        if [ -n "$FINAL_TARGET" ]; then
            echo "$(date): Attempting to kill $FINAL_TARGET" >> "$LOG_FILE"
            # Note: systemctl stop requires sudo. 
            # If running as non-root, your user must have NOPASSWD sudo rights for systemctl.
            sudo systemctl stop "$FINAL_TARGET" >> "$LOG_FILE" 2>&1
        fi

    else
        # ACTION: SPIKE CPU
        echo "$(date): Spiking CPU" >> "$LOG_FILE"
        for i in $(seq 1 $(nproc)); do
            (timeout "$CPU_LOAD_DURATION" sha512sum /dev/zero > /dev/null &)
        done
    fi
done
