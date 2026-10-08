#!/usr/bin/env python3
"""Local encrypted-backup health check. Read-only; never prints remote names or secrets."""
import argparse
import datetime as dt
from pathlib import Path
import re
import subprocess
import sys

REMOTE_FILE = Path("/etc/myvps/backup.remote")
ROOT = "VPS-Backups"
KIND = ("config", "blog")
NAME_RE = {k: re.compile(r"^myvps-" + k + r"-(\d{8}T\d{6}Z)\.tar\.gz\.gpg$") for k in KIND}


def invoke(argv, timeout=40):
    try:
        return subprocess.run(argv, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def parse_timestamp(name, kind):
    m = NAME_RE[kind].fullmatch(name)
    if not m:
        return None
    try:
        return dt.datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc)
    except ValueError:
        return None


def check_age(names, now, max_hours):
    findings = []
    for kind in KIND:
        dates = [date for name in names if (date := parse_timestamp(name, kind)) is not None]
        if not dates:
            findings.append((kind, "MISSING", "No backup found"))
            continue
        age = (now - max(dates)).total_seconds() / 3600.0
        if age < -0.5:
            findings.append((kind, "FAILED", "Backup timestamp is in the future"))
        elif age > max_hours:
            findings.append((kind, "STALE", f"Last upload {age:.1f}h ago"))
        else:
            findings.append((kind, "OK", f"Last upload {age:.1f}h ago"))
    return findings


def self_test():
    now = dt.datetime(2026, 10, 8, 12, tzinfo=dt.timezone.utc)
    a = "myvps-config-20261008T110000Z.tar.gz.gpg"
    b = "myvps-blog-20261008T103000Z.tar.gz.gpg"
    assert all(row[1] == "OK" for row in check_age([a, b], now, 36))
    assert check_age([a], now, 36)[1][1] == "MISSING"
    assert check_age([a, b], now + dt.timedelta(hours=48), 36)[0][1] == "STALE"
    assert parse_timestamp("../bad", "blog") is None
    print("self-test=PASS")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--max-age-hours", type=int, default=36)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    if args.self_test:
        self_test()
        return 0
    if args.max_age_hours < 12:
        print("backup_watch=INVALID_MAX_AGE")
        return 2
    faults = []
    for kind in KIND:
        unit = f"myvps-backup-{kind}"
        for property_name, argv, expected in (
            ("timer-active", ("systemctl", "is-active", unit + ".timer"), "active"),
            ("timer-enabled", ("systemctl", "is-enabled", unit + ".timer"), "enabled"),
            ("last-run", ("systemctl", "show", unit + ".service", "-p", "Result", "--value"), "success"),
        ):
            p = invoke(argv, timeout=5)
            actual = p.stdout.strip() if p else "unavailable"
            if actual != expected:
                faults.append(f"{kind} {property_name}: {actual}")
    if not REMOTE_FILE.is_file():
        faults.append("Cloud remote not configured")
    else:
        remote = REMOTE_FILE.read_text().strip()
        if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*:", remote):
            faults.append("Invalid cloud remote configuration")
        else:
            p = invoke(("rclone", "lsf", remote + ROOT, "--files-only", "--max-depth", "1",
                        "--tpslimit", "1", "--tpslimit-burst", "1"), timeout=40)
            if not p or p.returncode != 0:
                faults.append("Google Drive listing failed")
            else:
                for kind, state, reason in check_age(p.stdout.splitlines(),
                                                      dt.datetime.now(dt.timezone.utc),
                                                      args.max_age_hours):
                    print(f"{kind}: {state} — {reason}")
                    if state != "OK":
                        faults.append(f"{kind} {state}: {reason}")
    if faults:
        for fault in faults:
            print("BACKUP_ALERT: " + fault)
        print(f"backup_watch=FAIL faults={len(faults)}")
        return 2
    print("backup_watch=PASS both cloud archives fresh, timer states and service results OK")
    return 0


if __name__ == "__main__":
    sys.exit(main())
