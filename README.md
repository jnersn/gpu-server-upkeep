# gpu-server-upkeep

Unattended upkeep for a Linux GPU server: daily distribution updates that wait
while GPU jobs are running, hourly disk-health and free-space checks, warnings
when you log in over SSH, and optional SSH hardening that rolls itself back if
it would lock you out.

It runs on the server itself with systemd timers, and sends no email or
other messages to outside services. You see its warnings when you log in, or
with `gpu-upkeep`.

## What it does

- **Updates** (`gpu-upkeep-update.timer`, daily around 04:00 server time):
  upgrades installed packages and pulls in new dependencies, keeps your local
  configuration files, never removes packages and never reboots. While NVIDIA
  compute jobs are running, the update is skipped and tried again the next day,
  so a long training or generation job isn't disrupted by library upgrades
  underneath it. Shutdown is blocked while an update is installing.
- **Disk health** (`gpu-upkeep-health.timer`, after boot and hourly): reads
  SMART data from every drive with `smartctl` and warns about failed health
  checks, NVMe critical warnings, media errors, low spare capacity, worn-out
  endurance, reallocated or pending sectors and high temperatures. It also
  warns when a filesystem you listed is low on space or not mounted.
- **Warnings at SSH login**: interactive SSH logins print any current warnings,
  for example a failed or long-deferred update, a pending reboot or a disk
  problem.
- **SSH hardening** (`harden-ssh.sh`, optional): key-only login, no root login,
  no X11 forwarding. TCP forwarding stays on, so SSH tunnels keep working. The
  change rolls itself back after 10 minutes unless you confirm it from a new
  SSH connection.

## Requirements

- A Debian-based distribution with systemd: Debian, Ubuntu, Linux Mint and
  similar. Python 3 is installed if missing.
- `sudo` on the server.
- An NVIDIA GPU is optional. Without `nvidia-smi`, updates never wait, and
  everything else works the same.

## Install

```sh
git clone https://github.com/jnersn/gpu-server-upkeep.git
sudo gpu-server-upkeep/install.sh
```

The installer adds `smartmontools` and `nvme-cli`, installs
`/usr/local/bin/gpu-upkeep`, the systemd units and `/etc/profile.d/gpu-upkeep.sh`,
creates `/etc/gpu-upkeep.conf` if it doesn't exist, runs the first disk check
and shows the status. To update, `git pull` and run it again. Your config is
kept.

If your models or datasets are on another disk, add it to `MOUNTS` in
`/etc/gpu-upkeep.conf` so you're warned when it fills up or fails to mount.

## Usage

```sh
gpu-upkeep            # disk checks, update outcome and any warnings
gpu-upkeep status --warnings
```

```
Disk checks: 2026-01-15 09:00
  /dev/nvme0: Example NVMe SSD 2TB; 38 C; OK
  /dev/sda: Example SATA SSD 4TB; 31 C; OK
  /: 1402.6 GiB free (75.3%)
  /mnt/data: 2210.0 GiB free (60.3%)
Automatic updates: successful
Last successful update: 2026-01-15 04:12
Logs: journalctl -u gpu-upkeep-health.service -u gpu-upkeep-update.service
No health or update warnings.
```

To run a check or an update now:

```sh
sudo systemctl start gpu-upkeep-health.service
sudo systemctl start gpu-upkeep-update.service
```

From another machine, `ssh <server> gpu-upkeep` shows the same report.

## Configuration

`/etc/gpu-upkeep.conf` holds `KEY=value` lines. Quote values that contain spaces.

| Setting | Default | What |
|---|---|---|
| `MOUNTS` | `"/"` | Filesystems to check, separated by spaces; each must be mounted |
| `MIN_FREE_PERCENT` | `10` | Warn below this much free space |
| `MAX_DISK_TEMP` | `70` | Warn at this disk temperature (°C) |
| `MAX_ENDURANCE_USED` | `90` | Warn when an NVMe drive has used this much of its rated endurance (%) |
| `DEFER_FOR_GPU` | `yes` | Skip the update run while NVIDIA compute jobs are running |
| `STALE_UPDATE_DAYS` | `3` | Warn when the last successful update is older than this |
| `STALE_CHECK_HOURS` | `2` | Warn when the last disk check is older than this |

To change when updates run, override the timer:
`sudo systemctl edit gpu-upkeep-update.timer`, then add
`[Timer]`, an empty `OnCalendar=` to clear the default and your own, for example
`OnCalendar=Sun *-*-* 03:00`.

A GPU job that runs for days keeps updates waiting for days. The login warning
then tells you since when, so you can pick a moment to stop it. Set
`DEFER_FOR_GPU=no` if you'd rather update regardless. If `nvidia-smi` itself
fails, typically after a driver update that needs a reboot, updates go ahead
and the reboot warning tells you what to do.

## SSH hardening

Run it with `sudo` from the account you log in with, which must already have a
key in `~/.ssh/authorized_keys`:

```sh
sudo gpu-server-upkeep/harden-ssh.sh
```

It writes `/etc/ssh/sshd_config.d/00-gpu-upkeep.conf`, validates it with
`sshd -t`, reloads SSH and starts a 10-minute rollback timer. Keep that session
open, then from a **new** connection run:

```sh
ssh <server> touch /run/gpu-upkeep-ssh/confirmed
```

If the new connection fails, wait out the timer, and the old configuration is
back. `sudo ROLLBACK_MINUTES=20 gpu-server-upkeep/harden-ssh.sh` gives you longer. Running it again is
harmless. To undo it later, delete the drop-in and run
`sudo systemctl reload ssh`.

## Uninstall

```sh
sudo gpu-server-upkeep/uninstall.sh            # keeps the config and the last results
sudo gpu-server-upkeep/uninstall.sh --purge    # removes those too
```

The SSH hardening drop-in and `smartmontools` are left in place.

## License

MIT. See [LICENSE](LICENSE).
