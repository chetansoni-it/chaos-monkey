# Chaos Monkey Resilience Simulator

A lightweight "Chaos Monkey" implementation for Linux VMs. This script is designed to test system resilience by randomly stopping active services and spiking CPU utilization.

## ⚠️ Warning
**FOR TEST ENVIRONMENTS ONLY.** Do not run this on production servers. It will intentionally cause service outages and performance degradation.

## Features
- **Persistence**: Installs as a `systemd` service; stays active after reboots.
- **Dynamic Targeting**: Can target specific services or use `(*)` to target all active system services.
- **CPU Stress**: Automatically detects CPU cores and spikes utilization to 100%.
- **Self-Preservation**: Automatically avoids killing critical services like `ssh`, `dbus`, and itself.
- **Observability**: Includes a built-in dashboard to track the "carnage."

## Installation & Usage

1. **Make the script executable**:
   ```bash
   chmod +x systemdlog.sh
   ```

2. **Start the Chaos: Run the script once with sudo to install the service**:
   ```bash
   sudo ./systemdlog.sh
   ```

3. **Check the Dashboard: View a summary of killed services and CPU spikes**:
   ```bash
   ./systemdlog.sh --dashboard
   ```

4. **Monitor Logs: Follow the real-time chaos events**:
   ```bash
   tail -f /tmp/systemd_log.log
   ```

## Configuration
You can edit the variables at the top of `systemdlog.sh`:
- `TARGET_SERVICES`: Set to `("*")` for all services or `("nginx" "mysql")` for specific ones.
- `MIN_SLEEP` / `MAX_SLEEP`: The random window (in seconds) between chaos events.
- `CPU_LOAD_DURATION`: How long each CPU spike lasts.

## Uninstallation
To remove the simulator from your system:
```bash
sudo systemctl stop systemdlog
sudo systemctl disable systemdlog
sudo rm /etc/systemd/system/systemdlog.service
sudo systemctl daemon-reload
```
