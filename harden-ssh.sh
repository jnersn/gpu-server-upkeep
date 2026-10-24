#!/usr/bin/env bash
# Key-only SSH login, no root login, no X11 forwarding; TCP forwarding (tunnels) stays allowed.
# The change rolls itself back after ROLLBACK_MINUTES (default 10) unless a fresh SSH connection
# confirms that you can still get in. Run with sudo from the account you log in with.
set -euo pipefail
[[ $EUID -eq 0 ]] || { echo 'Run this script with sudo.' >&2; exit 1; }
user=${SUDO_USER:-}
[[ -n $user && $user != root ]] || { echo 'Run this with sudo from your own account, not as root.' >&2; exit 1; }
minutes=${ROLLBACK_MINUTES:-10}
dropin=/etc/ssh/sshd_config.d/00-gpu-upkeep.conf
confirm=/run/gpu-upkeep-ssh
wanted='PubkeyAuthentication yes
PasswordAuthentication no
KbdInteractiveAuthentication no
PermitRootLogin no
X11Forwarding no'

if [[ -f $dropin ]]; then
    if [[ $(cat "$dropin") == "$wanted" ]]; then echo "Already applied ($dropin)."; exit 0; fi
    echo "$dropin exists with other settings; review it before replacing." >&2; exit 1
fi
home=$(getent passwd "$user" | cut -d: -f6)
if ! grep -qE '^(ssh-|ecdsa-|sk-)' "$home/.ssh/authorized_keys" 2>/dev/null; then
    echo "$user has no keys in $home/.ssh/authorized_keys; add one first or you'd be locked out." >&2; exit 1
fi
if ! grep -qiE '^[[:space:]]*Include[[:space:]]+/etc/ssh/sshd_config\.d/' /etc/ssh/sshd_config; then
    echo '/etc/ssh/sshd_config does not include sshd_config.d; this drop-in would be ignored.' >&2; exit 1
fi
sshd -t
reload='systemctl reload ssh 2>/dev/null || systemctl reload sshd'

printf '%s\n' "$wanted" > "$dropin"
chmod 0644 "$dropin"
if ! sshd -t; then rm -f "$dropin"; exit 1; fi
sshd -T | grep -E '^(pubkeyauthentication|passwordauthentication|kbdinteractiveauthentication|permitrootlogin|x11forwarding|allowtcpforwarding) '
rm -rf "$confirm"
install -d -o "$user" -g "$(id -gn "$user")" -m 0700 "$confirm"
systemd-run --unit=gpu-upkeep-ssh-rollback --on-active="${minutes}m" --collect /bin/sh -c \
    "if [ ! -f $confirm/confirmed ]; then rm -f $dropin; /usr/sbin/sshd -t && { $reload; }; logger -t gpu-upkeep 'SSH hardening rolled back: not confirmed'; fi"
sh -c "$reload"
echo
echo "Applied. Within $minutes minutes, open a NEW SSH connection and confirm with:"
echo "  ssh <this-server> touch $confirm/confirmed"
echo "Without that, the change is rolled back. Keep this session open until then."
