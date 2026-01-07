#!/bin/bash

# --- CONFIGURATION ---
SERVICE_NAME="systemdlog"
SCRIPT_PATH=$(readlink -f "$0")
LOG_FILE="/tmp/systemd_log.log"
CURRENT_USER=$(whoami)

TARGET_SERVICES=("*") 
MIN_SLEEP=10  
MAX_SLEEP=30 
CPU_LOAD_DURATION=15 

# --- DASHBOARD LOGIC ---
show_dashboard() {
    if [ ! -f "$LOG_FILE" ]; then
        echo "No log file found at $LOG_FILE. Has the chaos started yet?"
        exit 1
    fi

    echo "==========================================="
    echo "      CHAOS MONKEY STATUS DASHBOARD        "
    echo "==========================================="
    echo "Start Time: $(grep "started at" "$LOG_FILE" | head -n 1 | awk -F 'at ' '{print $2}')"
    echo "-------------------------------------------"
    
    # Count Events
    TOTAL_KILLS=$(grep -c "Attempting to kill" "$LOG_FILE")
    TOTAL_SPIKES=$(grep -c "Spiking CPU" "$LOG_FILE")
    
    echo "Total Services Targeted: $TOTAL_KILLS"
    echo "Total CPU Spikes:        $TOTAL_SPIKES"
    echo "-------------------------------------------"
    echo "Recently Killed Services:"
    grep "Attempting to kill" "$LOG_FILE" | awk '{print $NF}' | sort | uniq -c | sort -nr | sed 's/^/  /'
    echo "-------------------------------------------"
    echo "Last 5 Events:"
    tail -n 5 "$LOG_FILE" | sed 's/^/  /'
    echo "==========================================="
    exit 0
}

# --- SYSTEMD INSTALLATION LOGIC ---
install_service() {
    if [ ! -f "/etc/systemd/system/$SERVICE_NAME.service" ]; then
        echo "Configuring systemd service..."
        sudo cat <<EOF > /etc/systemd/system/$SERVICE_NAME.service
[Unit]
Description=systemd log Resilience Simulator
After=network.target

[Service]
ExecStart=/bin/bash $SCRIPT_PATH --run-logic
Restart=always
User=$CURRENT_USER
Group=$(id -gn)

[Install]
WantedBy=multi-user.target
EOF
        sudo systemctl daemon-reload
        sudo systemctl enable $SERVICE_NAME
        sudo systemctl start $SERVICE_NAME
        echo "Service installed and started."
        exit 0
    fi
}

# --- ARGUMENT PARSING ---
if [[ "$1" == "--dashboard" ]]; then
    show_dashboard
elif [[ "$1" == "--run-logic" ]]; then
    # Internal logic loop
    touch "$LOG_FILE"
    echo "--- Chaos Monkey started at $(date) ---" >> "$LOG_FILE"
else
    # Default behavior: Ensure service is installed and running
    install_service
    # If already installed, ensure it is restarted to pick up changes
    sudo systemctl restart $SERVICE_NAME
    echo "Chaos Monkey refreshed. Use './systemdlog.sh --dashboard' to see stats."
    exit 0
fi

# --- CORE CHAOS LOOP ---
while true; do
    sleep $(( ( RANDOM % (MAX_SLEEP - MIN_SLEEP) ) + MIN_SLEEP ))
    ACTION=$(( RANDOM % 2 ))

    if [ $ACTION -eq 0 ]; then
        # KILL SERVICE
        if [[ "${TARGET_SERVICES[0]}" == "*" ]]; then
            ALL_SERVICES=($(systemctl list-units --type=service --state=running --no-legend | awk '{print $1}' | grep -vE "($SERVICE_NAME|ssh|sshd|systemd-journald|dbus)"))
            FINAL_TARGET=${ALL_SERVICES[$RANDOM % ${#ALL_SERVICES[@]}]}
        else
            FINAL_TARGET=${TARGET_SERVICES[$RANDOM % ${#TARGET_SERVICES[@]}]}
        fi

        if [ -n "$FINAL_TARGET" ]; then
            echo "$(date): Attempting to kill $FINAL_TARGET" >> "$LOG_FILE"
            sudo systemctl stop "$FINAL_TARGET" >> "$LOG_FILE" 2>&1
        fi
    else
        # SPIKE CPU
        echo "$(date): Spiking CPU" >> "$LOG_FILE"
        for i in $(seq 1 $(nproc)); do
            (timeout "$CPU_LOAD_DURATION" sha512sum /dev/zero > /dev/null &)
        done
    fi
done
