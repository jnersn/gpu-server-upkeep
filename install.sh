#!/usr/bin/env bash
# Install or update gpu-upkeep: the command, its systemd timers and the SSH login warnings.
# Run with sudo on a Debian-based server (Debian, Ubuntu, Linux Mint). Safe to re-run;
# an existing /etc/gpu-upkeep.conf is left alone.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
command -v apt-get >/dev/null || { echo 'gpu-upkeep needs a Debian-based system (apt-get).' >&2; exit 1; }
here=$(cd -- "$(dirname -- "$0")" && pwd)
units="gpu-upkeep-health.service gpu-upkeep-health.timer gpu-upkeep-update.service gpu-upkeep-update.timer"

apt-get -o APT::Update::Error-Mode=any update
DEBIAN_FRONTEND=noninteractive apt-get -o DPkg::Lock::Timeout=300 install -y --no-install-recommends \
    python3 smartmontools nvme-cli
install -o root -g root -m 0755 "$here/gpu-upkeep" /usr/local/bin/gpu-upkeep
for unit in $units; do
    install -o root -g root -m 0644 "$here/systemd/$unit" "/etc/systemd/system/$unit"
done
install -o root -g root -m 0644 "$here/systemd/gpu-upkeep-login.sh" /etc/profile.d/gpu-upkeep.sh
if [[ ! -e /etc/gpu-upkeep.conf ]]; then
    install -o root -g root -m 0644 "$here/gpu-upkeep.conf.example" /etc/gpu-upkeep.conf
    echo 'Created /etc/gpu-upkeep.conf; add data disks to MOUNTS there.'
fi
install -d -o root -g root -m 0755 /var/lib/gpu-upkeep

(cd /etc/systemd/system && systemd-analyze verify $units)
systemctl daemon-reload
systemctl enable --now gpu-upkeep-health.timer gpu-upkeep-update.timer
# smartd may refuse to run without SMART-capable disks (VMs, cloud); the hourly checks still run.
systemctl enable --now smartmontools.service || echo 'smartd did not start; continuing without it.'
systemctl start gpu-upkeep-health.service
echo
gpu-upkeep status
echo
echo 'gpu-upkeep is installed. The first update runs at the next timer (around 04:00);'
echo 'to run it now: sudo systemctl start gpu-upkeep-update.service'
