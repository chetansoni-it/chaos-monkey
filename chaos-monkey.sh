#!/bin/bash

# --- CONFIGURATION ---
SERVICE_NAME="chaos-monkey"
SCRIPT_PATH=$(readlink -f "$0")
LOG_FILE="/var/log/chaos_monkey.log"

# TARGETS: 
# Use ("*") to target all active services.
# Use ("nginx" "mysql") to target specific ones.
TARGET_SERVICES=("*") 

MIN_SLEEP=30  
MAX_SLEEP=120 
CPU_LOAD_DURATION=20 

# --- SYSTEMD INSTALLATION LOGIC ---
install_service() {
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo "Configuring systemd service..."
        cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=Chaos Monkey Resilience Simulator
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH --run-logic
Restart=always
User=root

[Install]
WantedBy=multi-user.target
EOF
        systemctl daemon-reload
        systemctl enable $SERVICE_NAME
        systemctl start $SERVICE_NAME
        echo "Chaos Monkey is now installed and running."
        exit 0
    else
        if ! systemctl is-active --quiet $SERVICE_NAME; then
            systemctl start $SERVICE_NAME
        fi
    fi
}

# Root check
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root."
   exit 1
fi

if [[ "$1" != "--run-logic" ]]; then
    install_service
    exit 0
fi

# --- CHAOS LOGIC ---
echo "Chaos Monkey started at $(date)" >> $LOG_FILE

while true; do
    sleep $(( ( RANDOM % (MAX_SLEEP - MIN_SLEEP) ) + MIN_SLEEP ))

    ACTION=$(( RANDOM % 2 ))

    if [ $ACTION -eq 0 ]; then
        # ACTION: KILL SERVICE
        FINAL_TARGET=""

        if [[ "${TARGET_SERVICES[0]}" == "*" ]]; then
            # Get all active services, filter out the chaos monkey itself and the ssh service
            # to prevent you from being locked out immediately.
            ALL_SERVICES=($(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}' | grep -vE "($SERVICE_NAME|ssh|sshd)"))
            FINAL_TARGET=${ALL_SERVICES[$RANDOM % ${#ALL_SERVICES[@]}]}
        else
            FINAL_TARGET=${TARGET_SERVICES[$RANDOM % ${#TARGET_SERVICES[@]}]}
        fi

        if [ ! -z "$FINAL_TARGET" ]; then
            echo "$(date): Killing service $FINAL_TARGET" >> $LOG_FILE
            systemctl stop "$FINAL_TARGET"
        fi

    else
        # ACTION: SPIKE CPU
        echo "$(date): Increasing CPU utilization" >> $LOG_FILE
        # Runs sha512sum against zero-fill to max out cores
        for i in $(seq 1 $(nproc)); do
            (timeout $CPU_LOAD_DURATION sha512sum /dev/zero > /dev/null &)
        done
    fi
done
