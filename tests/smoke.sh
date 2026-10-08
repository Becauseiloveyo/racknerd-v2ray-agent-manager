#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
script="my_vps_manager.sh"

bash -n "$script"
bash "$script" help > /tmp/myvps-help.txt
grep -q '2.2.0-rc1' /tmp/myvps-help.txt
grep -q 'reality-init' /tmp/myvps-help.txt

# No privileged mutations should occur in read-only inspection.
bash "$script" status > /tmp/myvps-status.txt
bash "$script" doctor > /tmp/myvps-doctor.txt
grep -q 'read-only status' /tmp/myvps-status.txt
grep -q 'This does NOT diagnose' /tmp/myvps-doctor.txt

# Old third-party installer and legacy destructive network modifications must stay out.
if grep -E 'mack-a/v2ray-agent|vasma|ufw --force|printf .*nameserver .*resolv.conf' "$script"; then
  echo "Legacy upstream installer or destructive network mutation found" >&2
  exit 1
fi

# Existing service names must never be stopped or restarted by maintenance script.
if grep -E 'systemctl (stop|restart|disable) (nginx|xray|xray-racknerd-443|pm2)' "$script"; then
  echo "Existing service control detected" >&2
  exit 1
fi

echo "PASS: syntax, help, status, doctor, forbidden mutation guards"
