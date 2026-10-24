#!/usr/bin/env bash
# Remove gpu-upkeep. Keeps /etc/gpu-upkeep.conf and the state in /var/lib/gpu-upkeep unless --purge.
# The SSH hardening drop-in (harden-ssh.sh) is not touched.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
systemctl disable --now gpu-upkeep-health.timer gpu-upkeep-update.timer 2>/dev/null || true
for unit in gpu-upkeep-health.service gpu-upkeep-health.timer gpu-upkeep-update.service gpu-upkeep-update.timer; do
    rm -f "/etc/systemd/system/$unit"
done
systemctl daemon-reload
rm -f /usr/local/bin/gpu-upkeep /etc/profile.d/gpu-upkeep.sh
if [[ ${1:-} == --purge ]]; then
    rm -rf /etc/gpu-upkeep.conf /var/lib/gpu-upkeep
fi
echo 'gpu-upkeep removed. smartmontools stays installed and running.'
