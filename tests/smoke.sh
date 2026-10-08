#!/usr/bin/env bash
set -Eeuo pipefail
cd "$(dirname "$0")/.."
script="my_vps_manager.sh"

bash -n "$script"
bash -n myvps_backup.sh
python3 -m py_compile myvps_runtime.py
python3 myvps_runtime.py status > /tmp/myvps-runtime-status.txt
python3 myvps_runtime.py backup-status > /tmp/myvps-runtime-backup.txt
grep -q "manager_release=2.3.0-rc1" /tmp/myvps-runtime-status.txt
grep -q "restore-test" myvps_backup.sh
bash "$script" help > /tmp/myvps-help.txt
grep -q '2.3.0-rc1' /tmp/myvps-help.txt
grep -q 'reality-init' /tmp/myvps-help.txt
grep -q 'legacy-exit' /tmp/myvps-help.txt
grep -q 'backup-status' /tmp/myvps-help.txt
grep -q 'chain-test' /tmp/myvps-help.txt

# No privileged mutations should occur in read-only inspection.
bash "$script" status > /tmp/myvps-status.txt
bash "$script" doctor > /tmp/myvps-doctor.txt
grep -q 'read-only status' /tmp/myvps-status.txt
grep -q 'This does NOT diagnose' /tmp/myvps-doctor.txt

# New RC must not take over production paths or silently fetch main.
grep -Fq 'SELF="/opt/myvps/bin/my_vps_manager.sh"' "$script"
grep -Fq '/usr/local/bin/myvps-next' "$script"
grep -Fq 'RC update disabled' "$script"
if grep -Eq 'ln -sfn .* /usr/local/bin/myvps$|SELF="/root/my_vps_manager.sh"' "$script"; then
  echo "Candidate would take over the production myvps command" >&2
  exit 1
fi

# Old third-party installer and legacy destructive network modifications must stay out.
if grep -E '^[[:space:]]*UPSTREAM=|^[[:space:]]*vasma([[:space:]]|$)|^[[:space:]]*ufw --force|^[[:space:]]*printf .*nameserver .*resolv.conf' "$script"; then
  echo "Legacy upstream installer or destructive network mutation found" >&2
  exit 1
fi

# Existing service names must never be stopped or restarted by maintenance script.
if grep -E 'systemctl (stop|restart|disable) (nginx|xray|xray-racknerd-443|pm2)' "$script"; then
  echo "Existing service control detected" >&2
  exit 1
fi

echo "PASS: syntax, help, status, doctor, forbidden mutation guards"
