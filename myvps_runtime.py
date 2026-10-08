#!/usr/bin/env python3
"""Read-only diagnostics for the *existing* RackNerd VPS.
Never display client UUIDs, SOCKS passwords, upstream IPs, tokens or Xray keys.
"""
import argparse
import datetime as dt
import json
import os
from pathlib import Path
import re
import socket
import ssl
import subprocess
import sys
import urllib.request

XRAY = Path("/etc/xray-racknerd-443/config.json")
BACKUP_REMOTE = Path("/etc/myvps/backup.remote")
BACKUP_KEY = Path("/etc/myvps/backup.pass")
BASE = "VPS-Backups"
SERVICES = ("ssh", "nginx", "xray-racknerd-443", "fail2ban", "cron", "wg-quick@warp")
MANAGERS = {
    "legacy_main": Path("/root/my_vps_manager.sh"),
    "exit_switch": Path("/root/my_vps_exit_manager.sh"),
    "cloudflare_ws": Path("/root/my_vps_cf_ws_manager.sh"),
    "backup_companion": Path("/opt/myvps/backup/myvps_backup.sh"),
}


def run(args, timeout=8):
    try:
        return subprocess.run(args, capture_output=True, text=True, timeout=timeout, check=False)
    except (OSError, subprocess.TimeoutExpired):
        return None


def systemctl(*args):
    p = run(("systemctl", *args))
    return p.stdout.strip() if p and p.stdout.strip() else "unavailable"


def version(path):
    try:
        text = path.read_text(errors="replace")[:8192]
    except OSError:
        return "missing"
    match = re.search(r'^\s*(?:VERSION|SCRIPT_VERSION)="?([a-zA-Z0-9._-]+)', text, re.M)
    return match.group(1) if match else "present"


def config():
    try:
        return json.loads(XRAY.read_text())
    except (OSError, ValueError):
        return None


def chain_config_summary(data):
    outs = [o for o in data.get("outbounds", []) if o.get("protocol") == "socks"]
    tags = {o.get("tag") for o in outs}
    rules = data.get("routing", {}).get("rules", [])
    match = [r for r in rules if r.get("outboundTag") in tags]
    print("chain_socks_outbound_count=", len(outs), sep="")
    print("chain_rules_to_socks=", len(match), sep="")
    print("chain_upstream_count=", sum(len(o.get("settings", {}).get("servers", [])) for o in outs), sep="")
    print("chain_routing_active=", bool(match), sep="")
    for rule in match:
        scoped = any(k in rule for k in ("inboundTag", "domain", "ip", "port", "network"))
        print("chain_rule_scoped=", scoped, sep="")
    for inbound in data.get("inbounds", []):
        print("reality_vless_inbound=", inbound.get("protocol") == "vless" and inbound.get("streamSettings", {}).get("security") == "reality", sep="")


def status():
    print("manager_release=2.3.0-rc1")
    osr = Path("/etc/os-release")
    if osr.exists():
        m = re.search(r'^PRETTY_NAME=(.+)', osr.read_text(), re.M)
        if m:
            print("os=", m.group(1).strip('"'), sep="")
    for name, path in MANAGERS.items():
        print("script_", name, "=", version(path), sep="")
    for service in SERVICES:
        print("service_", service, "=", systemctl("is-active", service), sep="")
    data = config()
    if data:
        chain_config_summary(data)
    else:
        print("xray_config=unreadable")
    print("service_myvps-xhttp=", systemctl("is-active", "myvps-xhttp.service"), sep="")
    xhttp_cfg = Path("/etc/myvps/xhttp/config.json")
    xhttp_client = Path("/etc/myvps/xhttp/client-info.json")
    print("xhttp_config_present=", xhttp_cfg.is_file(), sep="")
    print("xhttp_client_info_present=", xhttp_client.is_file(), sep="")
    for name in ("config", "blog"):
        print("backup_timer_", name, "=", systemctl("is-active", f"myvps-backup-{name}.timer"), sep="")
        print("backup_timer_enabled_", name, "=", systemctl("is-enabled", f"myvps-backup-{name}.timer"), sep="")
    print("backup_key_present=", BACKUP_KEY.is_file() and BACKUP_KEY.stat().st_size > 0, sep="")
    print("backup_remote_configured=", BACKUP_REMOTE.is_file(), sep="")


def latest_backups():
    if not BACKUP_REMOTE.is_file():
        print("backup_cloud=not-configured")
        return
    remote = BACKUP_REMOTE.read_text().strip()
    if not re.fullmatch(r"[A-Za-z][A-Za-z0-9_-]*:", remote):
        print("backup_cloud=invalid-remote-name")
        return
    p = run(("rclone", "lsf", remote + BASE, "--files-only", "--max-depth", "1", "--tpslimit", "1"), timeout=25)
    if not p or p.returncode != 0:
        print("backup_cloud=unavailable")
        return
    now = dt.datetime.now(dt.timezone.utc)
    for kind in ("config", "blog"):
        stamps = []
        for name in p.stdout.splitlines():
            m = re.fullmatch(r"myvps-" + kind + r"-(\d{8}T\d{6}Z)\.tar\.gz\.gpg", name)
            if not m:
                continue
            try:
                stamps.append(dt.datetime.strptime(m.group(1), "%Y%m%dT%H%M%SZ").replace(tzinfo=dt.timezone.utc))
            except ValueError:
                pass
        print(f"backup_{kind}_cloud_count={len(stamps)}")
        if stamps:
            hours = (now - max(stamps)).total_seconds() / 3600
            print(f"backup_{kind}_last_age_hours={hours:.1f}")
            print(f"backup_{kind}_fresh_36h={hours <= 36}")
    for kind in ("config", "blog"):
        service = f"myvps-backup-{kind}.service"
        print(f"backup_{kind}_last_service_result={systemctl('show', service, '-p', 'Result', '--value')}")


def read_exact(sock, length):
    result = bytearray()
    while len(result) < length:
        buf = sock.recv(length - len(result))
        if not buf:
            raise OSError("Connection closed")
        result.extend(buf)
    return bytes(result)


def chain_test():
    data = config()
    if not data:
        print("chain_test=CONFIG_UNREADABLE")
        return 1
    servers = [s for o in data.get("outbounds", []) if o.get("protocol") == "socks"
               for s in o.get("settings", {}).get("servers", [])]
    if not servers:
        print("chain_test=NO_SOCKS_OUTBOUND")
        return 1
    proxy = servers[0]
    users = proxy.get("users") or []
    try:
        with socket.create_connection((proxy["address"], int(proxy["port"])), timeout=8) as s:
            s.settimeout(10)
            methods = b"\x02" if users else b"\x00"
            s.sendall(b"\x05\x01" + methods)
            response = read_exact(s, 2)
            if response[0] != 5 or response[1] not in methods:
                raise OSError("SOCKS method rejected")
            if response[1] == 2:
                creds = users[0]
                username = str(creds.get("user", creds.get("username", ""))).encode()
                password = str(creds.get("pass", creds.get("password", ""))).encode()
                if not (0 < len(username) <= 255 and 0 < len(password) <= 255):
                    raise OSError("Invalid auth")
                s.sendall(b"\x01" + bytes((len(username),)) + username +
                          bytes((len(password),)) + password)
                if read_exact(s, 2) != b"\x01\x00":
                    raise OSError("Authentication failure")
            print("chain_socks_auth=PASS")
            target = b"www.cloudflare.com"
            s.sendall(b"\x05\x01\x00\x03" + bytes((len(target),)) + target + (443).to_bytes(2, "big"))
            header = read_exact(s, 4)
            if header[1] != 0:
                raise OSError("Upstream refused destination")
            atyp = header[3]
            n = {1: 4, 4: 16}.get(atyp)
            if atyp == 3:
                n = read_exact(s, 1)[0]
            if n is None:
                raise OSError("Invalid destination response")
            read_exact(s, n + 2)
            print("chain_socks_connect=PASS")
            with ssl.create_default_context().wrap_socket(s, server_hostname=target.decode()) as tls:
                tls.sendall(b"GET /cdn-cgi/trace HTTP/1.1\r\nHost: www.cloudflare.com\r\nConnection: close\r\n\r\n")
                first = tls.recv(512).split(b"\r\n", 1)[0]
                if b" 200 " not in first:
                    raise OSError("Target HTTP non-200")
            print("chain_tls_https=PASS")
            print("chain_test=PASS")
            return 0
    except (OSError, ValueError, KeyError, ssl.SSLError):
        print("chain_test=FAIL (details suppressed; credentials not logged)")
        return 1


def main():
    parser = argparse.ArgumentParser(description="Read-only live VPS diagnostics")
    parser.add_argument("command", choices=("status", "backup-status", "chain-test", "xhttp-status"))
    args = parser.parse_args()
    if args.command == "status":
        status()
    elif args.command == "backup-status":
        latest_backups()
    elif args.command == "xhttp-status":
        print("xhttp_service=", systemctl("is-active", "myvps-xhttp.service"), sep="")
        print("xhttp_config_present=", Path("/etc/myvps/xhttp/config.json").is_file(), sep="")
        print("xhttp_client_info_present=", Path("/etc/myvps/xhttp/client-info.json").is_file(), sep="")
    else:
        return chain_test()
    return 0


if __name__ == "__main__":
    sys.exit(main())
